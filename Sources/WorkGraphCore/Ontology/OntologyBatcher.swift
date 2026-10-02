import Foundation
import GRDB

public struct BatchConfig: Sendable {
    /// 가장 오래된 미처리 행이 이만큼 지나야 배치를 돈다 (초).
    public var minAge: Double = 300
    /// LLM 호출 한 번에 담는 활동 구간의 최대 길이 (초).
    public var maxWindow: Double = 1800
    public var maxRows: Int = 150
    /// 수집기 생존 신호 간격(60초)의 1.5배. 이보다 긴 간격은 체류시간으로 치지 않는다.
    public var maxGap: Double = 90
    public var snippetChars: Int = 300
    public var snippetTopN: Int = 24
    public var fetchLimit: Int = 3000
    public var maxBackoff: Double = 1800
    /// 화면 기억 카드: 대표 화면을 멀티모달 LLM 에 보내 카드를 만들고 업무 배정의 근거로 쓴다 (LLM 이 이미지를 받을 때만)
    public var screenCards: Bool = true
    /// 같은 화면의 카드를 다시 쓰는 기간 (초)
    public var cardReuseWindow: Double = 24 * 3600

    public init() {}
}

public enum BatchOutcome: Equatable, Sendable {
    case skipped(String)
    case ok(ApplyStats)
    case failed(String)
}

/// 미처리 행을 모아 LLM을 한 번 호출하고, 결과를 그래프에 반영한다.
/// 반영과 "처리 완료 표시"는 한 트랜잭션이라 중간에 죽어도 중복이 생기지 않는다.
public actor OntologyBatcher {
    private let db: WGDatabase
    private let store: EventStore
    private var llm: any LLMClient
    private var config: BatchConfig
    private let home: String
    private let fileExists: @Sendable (String) -> Bool
    private let clock: @Sendable () -> Double

    private var isRunning = false
    private var failures = 0
    private var nextAllowedAt = 0.0

    public init(db: WGDatabase, llm: any LLMClient, config: BatchConfig = BatchConfig(), home: String = NSHomeDirectory(),
                fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) {
        self.db = db; self.store = EventStore(db); self.llm = llm; self.config = config
        self.home = home; self.fileExists = fileExists; self.clock = clock
    }

    public func setScreenCards(_ enabled: Bool) { config.screenCards = enabled }

    public func setLLM(_ client: any LLMClient) {
        llm = client
        failures = 0; nextAllowedAt = 0
    }

    public func runIfDue(force: Bool) async -> BatchOutcome {
        guard !isRunning else { return .skipped("이미 실행 중") }
        isRunning = true
        defer { isRunning = false }
        do {
            return try await run(force: force)
        } catch {
            return .failed("\(error)")
        }
    }

    private func run(force: Bool) async throws -> BatchOutcome {
        let now = clock()
        if !force, now < nextAllowedAt { return .skipped("재시도 대기 중 (\(Int(nextAllowedAt - now))초 남음)") }

        let pending = try store.unprocessed(limit: config.fetchLimit)
        guard let head = pending.first else { return .skipped("미처리 행 없음") }
        if !force, now - head.ts < config.minAge { return .skipped("가장 오래된 행이 아직 \(Int(config.minAge))초가 안 됨") }

        // 한 번에 maxWindow 만큼만. 그 뒤에 남은 행은 다음 배치가 가져간다.
        var window = pending.filter { $0.ts <= head.ts + config.maxWindow }
        var windowEnd = pending.count > window.count ? pending[window.count].ts : now
        // 지금 보고 있는 마지막 행은 체류시간이 아직 안 정해졌으므로 다음 배치로 넘긴다.
        if !force, pending.count == window.count, window.count > 1, let last = window.last, now - last.ts < config.maxGap {
            window.removeLast()
            windowEnd = last.ts
        }
        guard let first = window.first, let last = window.last else { return .skipped("미처리 행 없음") }

        let idle = try store.idleSpans(from: first.ts, to: windowEnd)
        let texts = try store.texts(ids: window.compactMap(\.textId))
        let compressed = EventCompressor.compress(window, idle: idle, texts: texts, windowEnd: windowEnd, home: home,
                                                  fileExists: fileExists, maxRows: config.maxRows, maxGap: config.maxGap,
                                                  snippetChars: config.snippetChars, snippetTopN: config.snippetTopN)
        let includedIds = compressed.flatMap(\.observationIds)
        guard !compressed.isEmpty, !includedIds.isEmpty else { return .skipped("압축 결과 없음") }
        // 창 안의 대화 + 아직 어느 배치에도 안 들어간 지난 대화(늦게 읽혔거나 앱이 꺼져 있던 동안 것)
        let chats = (try? store.unprocessedChatMessages(upTo: windowEnd, notOlderThan: first.ts - 24 * 3600)) ?? []
        let rows = EventCompressor.merge(compressed, chats: chats, home: home, fileExists: fileExists, snippetChars: config.snippetChars)

        // 최근 7일의 업무 전부 (최대 40개): 행이 어느 목표에 기여하는지 보려면 목표 목록이 다 있어야 한다
        let openTasks = try await db.writer.read { try GraphTx($0).openTasks(limit: 40, since: now - 7 * 86_400) }
        // 화면 기억 카드 (실패해도 배정은 카드 없이 계속한다)
        var cards: [Int: [ScreenCard]] = [:]
        if config.screenCards, let vision = llm as? any VisionLLMClient {
            cards = await makeCards(rows: rows, window: window, llm: vision, now: now)
        }
        let prompt = OntologyPrompt.build(rows: rows, openTasks: openTasks, now: now, cards: cards)
        let model = llm.modelName

        let result: LLMResult
        do {
            result = try await llm.callFunction(system: prompt.system, user: prompt.user, tool: AssignmentSchema.tool)
        } catch {
            // 서버가 죽었거나 토큰이 만료된 경우: 데이터는 그대로 두고 기다린다. 건너뛰지 않는다.
            let message = (error as? LLMError)?.description ?? "\(error)"
            try recordFailure(message: message, model: model, first: first, last: last, rowCount: rows.count, raw: nil, now: now, prompt: prompt)
            scheduleBackoff(now: now)
            return .failed(message)
        }

        let patch = AssignmentPatch.decodeLenient(from: result.arguments)
        guard let patch, !patch.rows.isEmpty else {
            let message = "LLM 응답에 행 배정이 없음"
            try recordFailure(message: message,
                              model: result.model, first: first, last: last, rowCount: rows.count, raw: result.raw, now: now,
                              tokens: (result.promptTokens, result.completionTokens), prompt: prompt)
            scheduleBackoff(now: now)
            return .failed(message)
        }

        // 행마다 정해진 업무를 그래프에 반영하고, 판단 원본은 원시 행에 남긴다.
        let stats: ApplyStats
        do {
            stats = try await db.writer.write { conn -> ApplyStats in
                let tx = GraphTx(conn)
                let (stats, assignments) = try AssignmentApplier().apply(patch, rows: rows, tx: tx, now: now, requireComplete: true)
                var record = BatchRecord(startedAt: now, finishedAt: Date().timeIntervalSince1970, fromObs: first.id, toObs: last.id,
                                         rowCount: rows.count, status: "ok", model: result.model,
                                         promptTokens: result.promptTokens, completionTokens: result.completionTokens,
                                         rawResponse: String(result.raw.prefix(20_000)),
                                         stats: (try? JSONEncoder().encode(stats)).flatMap { String(data: $0, encoding: .utf8) },
                                         systemPrompt: prompt.system, userPrompt: prompt.user,
                                         llmPatch: patch.prettyJSON, appliedPatch: Self.describe(assignments, tx: tx))
                try record.insert(conn)
                let batchId = record.id ?? conn.lastInsertedRowID
                try EventStore.mark(conn, observationIds: includedIds, batchId: batchId)
                try EventStore.markChats(conn, ids: rows.flatMap(\.chatMessageIds), batchId: batchId)
                for item in assignments {
                    try EventStore.assign(conn, observationIds: item.row.observationIds, taskId: item.taskId, relevant: item.resource, offTask: item.offTask, reason: item.reason)
                    try EventStore.assignChats(conn, ids: item.row.chatMessageIds, taskId: item.taskId)
                }
                return stats
            }
        } catch {
            let message = "행 배정 반영 실패: \(error)"
            try recordFailure(message: message, model: result.model, first: first, last: last, rowCount: rows.count,
                              raw: result.raw, now: now, tokens: (result.promptTokens, result.completionTokens), prompt: prompt)
            scheduleBackoff(now: now)
            return .failed(message)
        }
        failures = 0; nextAllowedAt = 0
        // 새 업무가 생겼으면 제목만 다른 같은 목표가 아닌지 LLM 에 묻는다 (합치기)
        if stats.tasksCreated > 0 {
            var merged = stats
            if let outcome = try? await TaskMerger.run(db: db, llm: llm, since: now - 7 * 86_400, now: now) { merged.tasksMerged = outcome.merged }
            return .ok(merged)
        }
        return .ok(stats)
    }

    /// 대표 화면을 골라 카드를 만들거나(같은 화면이면 재사용) 행에 연결한다. 행 번호 → 카드
    private func makeCards(rows: [ActivityRow], window: [Observation], llm: any VisionLLMClient, now: Double) async -> [Int: [ScreenCard]] {
        var shots: [Int64: KeyframeSelector.Shot] = [:]
        for observation in window {
            guard let id = observation.id, let path = observation.screenshotPath, let hash = observation.screenHash, fileExists(path) else { continue }
            shots[id] = KeyframeSelector.Shot(observationId: id, ts: observation.ts, path: path, hash: UInt64(bitPattern: hash))
        }
        let groups = KeyframeSelector.select(rows: rows, shots: shots)
        guard !groups.isEmpty else { return [:] }

        // 같은 화면의 최근 카드가 있으면 재사용
        let reuseWindow = config.cardReuseWindow
        let split: (reused: [(group: KeyframeSelector.Group, card: ScreenCard)], fresh: [KeyframeSelector.Group])
        do {
            split = try await db.writer.read { conn in
                var reused: [(group: KeyframeSelector.Group, card: ScreenCard)] = [], fresh: [KeyframeSelector.Group] = []
                for group in groups {
                    // 1) 이 화면의 행들이 이미 카드에 연결돼 있으면 그 카드 (재생성, 재시도)
                    if let linked = try ScreenCardStore.linkedCard(conn, observationIds: group.observationIds) {
                        reused.append((group, linked)); continue
                    }
                    // 2) 같은 앱·제목·주소에 비슷한 화면의 최근 카드
                    let candidates = try ScreenCardStore.recentCards(conn, appBundle: group.appBundle, title: group.title, uri: group.uri, since: group.start - reuseWindow)
                    if let match = candidates.first(where: { KeyframeSelector.distance(UInt64(bitPattern: $0.screenHash), group.representative.hash) <= KeyframeSelector.sameScreenDistance }) {
                        reused.append((group, match))
                    } else {
                        fresh.append(group)
                    }
                }
                return (reused, fresh)
            }
        } catch {
            AppLog.write("카드 재사용 조회 실패: \(error)")
            split = ([], groups)
        }
        let reused = split.reused, fresh = split.fresh
        let toSend = Array(fresh.prefix(CardMaker.maxImages))                  // 머문 시간 긴 순으로 이미 정렬됨

        var made: [(group: KeyframeSelector.Group, draft: CardMaker.Draft)] = []
        if !toSend.isEmpty {
            do {
                let (drafts, result) = try await CardMaker.make(toSend, llm: llm)
                for (index, draft) in drafts.enumerated() { if let draft { made.append((toSend[index], draft)) } }
                if let result { AppLog.write("화면 카드 \(made.count)/\(toSend.count)장 (재사용 \(reused.count)) 토큰 \(result.promptTokens)+\(result.completionTokens)") }
            } catch {
                AppLog.write("화면 카드 실패 (카드 없이 계속): \(String(describing: error).prefix(200))")
            }
        }

        let madeFinal = made
        var byRow: [Int: [ScreenCard]] = [:]
        do {
            byRow = try await db.writer.write { conn in
                var byRow: [Int: [ScreenCard]] = [:]
                for (group, card) in reused {
                    guard let id = card.id else { continue }
                    try ScreenCardStore.extend(conn, cardId: id, to: group.end)
                    try ScreenCardStore.link(conn, observationIds: group.observationIds, cardId: id)
                    for row in group.rows { byRow[row, default: []].append(card) }
                }
                for (group, draft) in madeFinal {
                    let shot = group.representative
                    let card = try ScreenCardStore.insert(conn, ScreenCard(
                        tsStart: group.start, tsEnd: group.end, screenHash: Int64(bitPattern: shot.hash), screenshotPath: shot.path,
                        appBundle: group.appBundle, appName: group.appName, windowTitle: group.title, uri: group.uri,
                        activity: draft.activity, content: draft.content.joined(separator: "\n"), kind: draft.kind,
                        entities: CardMaker.entitiesJSON(draft.entities), createdAt: now))
                    guard let id = card.id else { continue }
                    try ScreenCardStore.link(conn, observationIds: group.observationIds, cardId: id)
                    for row in group.rows { byRow[row, default: []].append(card) }
                }
                return byRow
            }
        } catch { AppLog.write("카드 저장 실패: \(error)") }
        return byRow.mapValues { $0.sorted { $0.tsStart < $1.tsStart } }
    }

    /// 사람이 읽는 배정 결과: 행 | 업무 | 자료 여부
    static func describe(_ assignments: [RowAssignment], tx: GraphTx) -> String {
        var titles: [Int64: String] = [:]
        var lines: [String] = ["row | task | resource"]
        for item in assignments {
            var title = "-"
            if let taskId = item.taskId {
                if titles[taskId] == nil { titles[taskId] = (try? tx.node(id: taskId))?.title ?? "#\(taskId)" }
                title = titles[taskId] ?? "-"
            }
            lines.append("\(item.row.row) | \(item.offTask ? "(이탈)" : title)\(item.resource ? "" : " | 자료 아님")\(item.reason.map { " | \($0)" } ?? "")")
        }
        return lines.joined(separator: "\n")
    }

    private func recordFailure(message: String, model: String, first: Observation, last: Observation, rowCount: Int,
                               raw: String?, now: Double, tokens: (Int, Int) = (0, 0),
                               prompt: (system: String, user: String)? = nil) throws {
        try db.writer.write { conn in
            var record = BatchRecord(startedAt: now, finishedAt: Date().timeIntervalSince1970, fromObs: first.id, toObs: last.id,
                                     rowCount: rowCount, status: "failed", model: model,
                                     promptTokens: tokens.0, completionTokens: tokens.1, error: String(message.prefix(1000)),
                                     rawResponse: raw.map { String($0.prefix(20_000)) },
                                     systemPrompt: prompt?.system, userPrompt: prompt?.user)
            try record.insert(conn)
        }
    }

    /// 1분 → 2분 → 4분 … 최대 30분.
    private func scheduleBackoff(now: Double) {
        failures += 1
        nextAllowedAt = now + min(60 * pow(2, Double(failures - 1)), config.maxBackoff)
    }
}

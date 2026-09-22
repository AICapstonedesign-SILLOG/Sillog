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
    /// 같은 구간에서 "쓸 수 없는 답"이 이만큼 반복되면 그 구간을 건너뛴다.
    public var maxContentFailures: Int = 5

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
    private var contentFailures: (head: Int64, count: Int) = (-1, 0)

    public init(db: WGDatabase, llm: any LLMClient, config: BatchConfig = BatchConfig(), home: String = NSHomeDirectory(),
                fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) {
        self.db = db; self.store = EventStore(db); self.llm = llm; self.config = config
        self.home = home; self.fileExists = fileExists; self.clock = clock
    }

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
        let prompt = OntologyPrompt.build(rows: rows, openTasks: openTasks, now: now)
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
            let headId = first.id ?? -1
            contentFailures = contentFailures.head == headId ? (headId, contentFailures.count + 1) : (headId, 1)
            let giveUp = contentFailures.count >= config.maxContentFailures
            try recordFailure(message: giveUp ? "\(message) — \(contentFailures.count)회 반복되어 이 구간은 건너뜀" : message,
                              model: result.model, first: first, last: last, rowCount: rows.count, raw: result.raw, now: now,
                              markSkipped: giveUp ? includedIds : [], tokens: (result.promptTokens, result.completionTokens), prompt: prompt)
            if giveUp { contentFailures = (-1, 0) }
            scheduleBackoff(now: now)
            return .failed(message)
        }

        // 행마다 정해진 업무를 그래프에 반영하고, 판단 원본은 원시 행에 남긴다.
        let stats = try await db.writer.write { conn -> ApplyStats in
            let tx = GraphTx(conn)
            let (stats, assignments) = try AssignmentApplier().apply(patch, rows: rows, tx: tx, now: now)
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
                try EventStore.assign(conn, observationIds: item.row.observationIds, taskId: item.taskId, relevant: item.resource)
                try EventStore.assignChats(conn, ids: item.row.chatMessageIds, taskId: item.taskId)
            }
            return stats
        }
        failures = 0; nextAllowedAt = 0; contentFailures = (-1, 0)
        // 새 업무가 생겼으면 제목만 다른 같은 목표가 아닌지 LLM 에 묻는다 (합치기)
        if stats.tasksCreated > 0 {
            var merged = stats
            if let outcome = try? await TaskMerger.run(db: db, llm: llm, since: now - 7 * 86_400, now: now) { merged.tasksMerged = outcome.merged }
            return .ok(merged)
        }
        return .ok(stats)
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
            lines.append("\(item.row.row) | \(title)\(item.resource ? "" : " | 보이기만 함")")
        }
        return lines.joined(separator: "\n")
    }

    private func recordFailure(message: String, model: String, first: Observation, last: Observation, rowCount: Int,
                               raw: String?, now: Double, markSkipped: [Int64] = [], tokens: (Int, Int) = (0, 0),
                               prompt: (system: String, user: String)? = nil) throws {
        try db.writer.write { conn in
            var record = BatchRecord(startedAt: now, finishedAt: Date().timeIntervalSince1970, fromObs: first.id, toObs: last.id,
                                     rowCount: rowCount, status: "failed", model: model,
                                     promptTokens: tokens.0, completionTokens: tokens.1, error: String(message.prefix(1000)),
                                     rawResponse: raw.map { String($0.prefix(20_000)) },
                                     systemPrompt: prompt?.system, userPrompt: prompt?.user)
            try record.insert(conn)
            if !markSkipped.isEmpty {
                try EventStore.mark(conn, observationIds: markSkipped, batchId: record.id ?? conn.lastInsertedRowID)
            }
        }
    }

    /// 1분 → 2분 → 4분 … 최대 30분.
    private func scheduleBackoff(now: Double) {
        failures += 1
        nextAllowedAt = now + min(60 * pow(2, Double(failures - 1)), config.maxBackoff)
    }
}

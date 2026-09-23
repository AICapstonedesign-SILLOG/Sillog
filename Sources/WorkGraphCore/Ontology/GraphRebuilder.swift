import Foundation
import GRDB

/// LLM 없이 그래프의 시간 층(세션·앱·자료·흐름·프로젝트)을 행 판단(observations.task_id)에서 다시 만든다.
/// 업무·주제·문제·나중에 할 일 노드는 그대로 둔다. 세션 규칙을 바꿨을 때 쓴다.
public struct GraphRebuilder {
    public struct Stats: Equatable, Sendable {
        public var batches = 0, rows = 0, tasks = 0, sessions = 0, resources = 0
        public init() {}
    }

    let db: WGDatabase
    let store: EventStore
    let config: BatchConfig
    let home: String
    let fileExists: (String) -> Bool

    public init(db: WGDatabase, store: EventStore, config: BatchConfig = BatchConfig(), home: String = NSHomeDirectory(),
                fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.db = db; self.store = store; self.config = config; self.home = home; self.fileExists = fileExists
    }

    public func rebuildFromAssignments(now: Double) throws -> Stats {
        var stats = Stats()
        let observations = try store.assignedObservations()
        let chats = try store.assignedChatMessages()
        let batches = try store.recentBatches(limit: 100_000).filter { $0.status == "ok" }.sorted { ($0.startedAt, $0.id ?? 0) < ($1.startedAt, $1.id ?? 0) }
        let byBatch = Dictionary(grouping: observations, by: { $0.batchId ?? -1 })
        let chatsByBatch = Dictionary(grouping: chats, by: { $0.batchId ?? -1 })

        try db.writer.write { conn in
            let tx = GraphTx(conn)
            // 1. 시간 층을 지운다: 세션 노드와 세션에 닿은 엣지, 업무 → 프로젝트
            try conn.execute(sql: "DELETE FROM edges WHERE src IN (SELECT id FROM nodes WHERE label = 'Session') OR dst IN (SELECT id FROM nodes WHERE label = 'Session')")
            try conn.execute(sql: "DELETE FROM nodes WHERE label = 'Session'")
            try conn.execute(sql: "DELETE FROM edges WHERE type = 'ON'")
            for task in try tx.nodes(label: NodeLabel.task) {
                try conn.execute(sql: "UPDATE nodes SET props = json_set(json_remove(props, '$.project_seconds'), '$.active_seconds', 0) WHERE id = ?", arguments: [task.id])
            }

            // 2. 배치 순서대로 행을 다시 만들고 세션을 계산한다
            var taskIds = Set<Int64>()
            var seconds: [Int64: Double] = [:], lastActive: [Int64: Double] = [:]
            var sessionStats = SessionBuilder.Stats()
            for (index, batch) in batches.enumerated() {
                guard let batchId = batch.id, let window = byBatch[batchId], !window.isEmpty else { continue }
                let next = batches.dropFirst(index + 1).lazy.compactMap { $0.id.flatMap { byBatch[$0]?.first?.ts } }.first
                let windowEnd = next ?? ((window.last?.ts ?? now) + config.maxGap)
                let idle = try EventStore.idleSpans(conn, from: window.first!.ts, to: windowEnd)
                let rows = EventCompressor.merge(
                    EventCompressor.compress(window, idle: idle, texts: [:], windowEnd: windowEnd, home: home, fileExists: fileExists,
                                             maxRows: config.maxRows, maxGap: config.maxGap, snippetChars: 0, snippetTopN: 0),
                    chats: chatsByBatch[batchId] ?? [], home: home, fileExists: fileExists, snippetChars: 0)
                let taskOfObservation = Dictionary(window.compactMap { obs in obs.id.map { ($0, (obs.taskId, obs.resourceRelevant)) } }, uniquingKeysWith: { first, _ in first })
                let taskOfChat = Dictionary((chatsByBatch[batchId] ?? []).compactMap { chat in chat.id.map { ($0, chat.taskId) } }, uniquingKeysWith: { first, _ in first })

                var assignments: [RowAssignment] = []
                for row in rows {
                    var taskId: Int64?, resource = true
                    if row.isChat {
                        taskId = row.chatMessageIds.compactMap { taskOfChat[$0] ?? nil }.first
                    } else {
                        // 행을 이루는 관측들의 다수결
                        var votes: [Int64: Int] = [:]
                        for id in row.observationIds {
                            guard let decision = taskOfObservation[id] else { continue }
                            if let task = decision.0 { votes[task, default: 0] += 1 }
                            if !decision.1 { resource = false }
                        }
                        taskId = votes.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key
                    }
                    assignments.append(RowAssignment(row: row, taskId: taskId, resource: resource))
                    if let taskId {
                        taskIds.insert(taskId)
                        seconds[taskId, default: 0] += Double(row.dwell)
                        lastActive[taskId] = max(lastActive[taskId] ?? 0, row.end)
                        if resource, let project = row.projectKey { try tx.addProjectSeconds(taskId: taskId, projectKey: project, seconds: Double(row.dwell), at: row.end) }
                    }
                }
                let summaries = Self.summaries(from: batch, tx: tx)
                try SessionBuilder().apply(assignments, summaries: summaries, tx: tx, stats: &sessionStats)
                stats.batches += 1; stats.rows += rows.count
            }
            for (taskId, active) in seconds {
                try tx.setProps(nodeId: taskId, ["active_seconds": .number(active), "last_active": .number(lastActive[taskId] ?? now)], at: lastActive[taskId] ?? now)
            }
            // 3. 문제·파일을 시간으로 세션에 다시 잇는다
            for problem in try tx.nodes(label: NodeLabel.problem) {
                let at = problem.props["at"]?.doubleValue ?? problem.createdAt
                if let session = try tx.latestSession(startedBefore: at + 1, excluding: nil) {
                    try tx.upsertEdge(src: session.id, dst: problem.id, type: EdgeType.hit, props: [:], addWeight: 0, at: at)
                }
            }
            try tx.rebindProjects(at: now)
            try tx.pruneOrphanResources()                                   // 이제 아무 세션도 안 만지는 자료는 뺀다
            stats.tasks = taskIds.count; stats.sessions = sessionStats.sessions; stats.resources = sessionStats.resources
        }
        return stats
    }

    /// 배치가 저장한 LLM 답(work)에서 업무별 요약을 되찾는다
    static func summaries(from batch: BatchRecord, tx: GraphTx) -> [Int64: String] {
        guard let raw = batch.llmPatch, let patch = AssignmentPatch.decodeLenient(from: Data(raw.utf8)) else { return [:] }
        var byRef: [String: Int64] = [:]
        for def in patch.tasks {
            if let id = def.id, let node = try? tx.node(label: NodeLabel.task, key: id) { byRef[def.ref] = node.id; continue }
            if let title = def.title {
                let wanted = AssignmentApplier.normalizeTitle(title).lowercased()
                if let node = try? tx.nodes(label: NodeLabel.task).first(where: { AssignmentApplier.normalizeTitle($0.title).lowercased() == wanted }) { byRef[def.ref] = node.id }
            }
        }
        var result: [Int64: String] = [:]
        for work in patch.work { if let id = byRef[work.task], !work.summary.isEmpty { result[id] = work.summary } }
        return result
    }
}

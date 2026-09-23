import Foundation

public struct ApplyStats: Codable, Equatable, Sendable {
    public var sessions = 0
    public var sessionsExtended = 0
    public var tasksCreated = 0
    public var resources = 0
    public var topics = 0
    public var problems = 0
    public var laterItems = 0
    public var uncoveredRows = 0
    /// 일이 아니라고 판단된 행 (task null)
    public var unassignedRows = 0
    /// 어떤 목표에도 기여하지 않는 행 (집중 이탈, task "off")
    public var offTaskRows = 0
    /// 같은 목표라서 합쳐진 업무 수 (배치 뒤 합치기 단계)
    public var tasksMerged = 0

    public init() {}
}

/// LLM 의 행 배정을 그래프에 반영한다.
///   1. 업무: 기존 id → 그 노드, 새 업무 → 같은 제목이 있으면 그것, 없으면 생성
///   2. 행마다 업무·자료 여부를 정하고 (배정 결과는 호출자가 원시 행에 기록한다)
///   3. 업무의 작업 시간·주제·프로젝트 시간을 더하고
///   4. 세션은 SessionBuilder 가 시간으로 계산한다
///   5. 문제·나중에 할 일은 행의 세션에 붙이고, 업무 ↔ 프로젝트를 1:1 로 맞춘다
public struct AssignmentApplier: Sendable {
    public var sessions = SessionBuilder()

    public init() {}

    public func apply(_ patch: AssignmentPatch, rows: [ActivityRow], tx: GraphTx, now: Double) throws -> (stats: ApplyStats, assignments: [RowAssignment]) {
        var stats = ApplyStats()
        let byNumber = Dictionary(rows.map { ($0.row, $0) }, uniquingKeysWith: { first, _ in first })

        // 1. 업무
        var taskByRef: [String: Int64] = [:]
        for def in patch.tasks where !def.ref.isEmpty {
            let (id, created) = try resolveTask(def, tx: tx, now: now)
            if let id { taskByRef[def.ref] = id }
            if created { stats.tasksCreated += 1 }
        }

        // 2. 행 배정
        let decided = patch.byRow()
        var assignments: [RowAssignment] = []
        var covered = 0
        for row in rows {
            guard let decision = decided[row.row] else { assignments.append(RowAssignment(row: row, taskId: nil, resource: true)); continue }
            covered += 1
            if decision.task == AssignmentPatch.offTask {
                stats.offTaskRows += 1
                assignments.append(RowAssignment(row: row, taskId: nil, resource: false, offTask: true, reason: decision.reason))
                continue
            }
            let taskId = decision.task.flatMap { taskByRef[$0] }
            if taskId == nil { stats.unassignedRows += 1 }
            assignments.append(RowAssignment(row: row, taskId: taskId, resource: decision.resource ?? Self.defaultResource(row), reason: decision.reason))
        }
        stats.uncoveredRows = rows.count - covered

        // 3. 업무의 시간·프로젝트 시간
        var seconds: [Int64: Double] = [:], lastActive: [Int64: Double] = [:]
        for item in assignments {
            guard let taskId = item.taskId else { continue }
            seconds[taskId, default: 0] += Double(item.row.dwell)
            lastActive[taskId] = max(lastActive[taskId] ?? 0, item.row.end)
            if item.resource, let project = item.row.projectKey {
                try tx.addProjectSeconds(taskId: taskId, projectKey: project, seconds: Double(item.row.dwell), at: item.row.end)
            }
        }
        for (taskId, active) in seconds {
            guard let task = try tx.node(id: taskId) else { continue }
            try tx.setProps(nodeId: taskId, ["active_seconds": .number((task.props["active_seconds"]?.doubleValue ?? 0) + active),
                                             "last_active": .number(max(task.props["last_active"]?.doubleValue ?? 0, lastActive[taskId] ?? 0))],
                            at: lastActive[taskId] ?? now)
        }

        // 주제와 요약 (업무별)
        let knownApps = Set(try tx.nodes(label: NodeLabel.app).map(\.title)).union(rows.map(\.app))
        let knownProjects = Set(try tx.nodes(label: NodeLabel.project).map(\.title)).union(rows.compactMap(\.projectTitle))
        var summaries: [Int64: String] = [:]
        var topicKeys = Set<String>()
        for work in patch.work {
            guard let taskId = taskByRef[work.task] else { continue }
            let summary = work.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty { summaries[taskId] = summary }
            let at = lastActive[taskId] ?? now
            for name in TopicFilter.clean(Array(work.topics.prefix(8)), apps: knownApps, projects: knownProjects).prefix(6) {
                let key = TopicFilter.normalize(name)
                let existing = try tx.node(label: NodeLabel.topic, key: key)
                let topicId = try tx.upsertNode(label: NodeLabel.topic, key: key, subtype: nil, title: existing == nil ? name : nil, props: [:], at: at)
                try tx.upsertEdge(src: taskId, dst: topicId, type: EdgeType.about, props: [:], addWeight: 0, at: at)
                if topicKeys.insert(key).inserted { stats.topics += 1 }
            }
        }

        // 4. 세션 (시간으로 계산)
        var sessionStats = SessionBuilder.Stats()
        let sessionByRow = try sessions.apply(assignments, summaries: summaries, tx: tx, stats: &sessionStats)
        stats.sessions = sessionStats.sessions; stats.sessionsExtended = sessionStats.sessionsExtended; stats.resources = sessionStats.resources

        // 5. 문제 · 나중에 할 일
        for problem in patch.problems ?? [] {
            let message = problem.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty, let sessionId = sessionByRow[problem.row] else { continue }
            let at = byNumber[problem.row]?.start ?? now
            let problemId = try tx.upsertNode(label: NodeLabel.problem, key: "problem:\(problem.kind):\(StableHash.short(message.lowercased()))",
                                              subtype: problem.kind, title: message, props: ["kind": .string(problem.kind), "at": .number(at)], at: at)
            try tx.upsertEdge(src: sessionId, dst: problemId, type: EdgeType.hit, props: [:], addWeight: 0, at: at)
            if let solvedRow = problem.resolvedByRow, let uri = byNumber[solvedRow]?.uri, let solver = try tx.node(label: NodeLabel.resource, key: uri) {
                try tx.upsertEdge(src: problemId, dst: solver.id, type: EdgeType.resolvedBy, props: [:], addWeight: 0, at: byNumber[solvedRow]?.end ?? at)
            }
            stats.problems += 1
        }
        for item in patch.laterItems ?? [] {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let taskId = assignments.first(where: { $0.row.row == item.row })?.taskId else { continue }
            let at = byNumber[item.row]?.start ?? now
            let itemId = try tx.upsertNode(label: NodeLabel.laterItem, key: "later:\(StableHash.short(text.lowercased()))", subtype: nil, title: text,
                                           props: ["done": .bool(false), "at": .number(at)], at: at)
            try tx.upsertEdge(src: itemId, dst: taskId, type: EdgeType.forTask, props: [:], addWeight: 0, at: at)
            stats.laterItems += 1
        }

        // 6. 업무 ↔ 프로젝트 1:1
        if assignments.contains(where: { $0.taskId != nil && $0.resource && $0.row.projectKey != nil }) { try tx.rebindProjects(at: now) }
        return (stats, assignments)
    }

    /// LLM 이 resource 를 안 적었을 때: 파일·AI 대화·문서류는 자료, 그냥 웹페이지·미리보기·메시지는 아니다
    public static func defaultResource(_ row: ActivityRow) -> Bool {
        if row.isChat || (row.uri?.hasPrefix("file:") ?? false) { return true }
        return ["CodeFile", "Document", "Design", "Note", "AIChat", "Documentation", "QnA", "Paper", "Video"].contains(row.type ?? "")
    }

    /// existing → id 로 찾고, 못 찾으면 제목으로 찾고, 그래도 없으면 새로 만든다.
    func resolveTask(_ def: AssignmentPatch.TaskDef, tx: GraphTx, now: Double) throws -> (id: Int64?, created: Bool) {
        if def.match == "existing", let id = def.id, let node = try tx.node(label: NodeLabel.task, key: id) { return (node.id, false) }
        let title = Self.normalizeTitle(def.title ?? "")
        guard !title.isEmpty else {
            if let id = def.id, let node = try tx.node(label: NodeLabel.task, key: id) { return (node.id, false) }
            return (nil, false)
        }
        if let same = try tx.nodes(label: NodeLabel.task).first(where: { Self.normalizeTitle($0.title).lowercased() == title.lowercased() }) {
            return (same.id, false)
        }
        let key = "t_\(StableHash.short("\(title)|\(Int(now))"))"
        let taskId = try tx.upsertNode(label: NodeLabel.task, key: key, subtype: nil, title: title,
                                       props: ["status": "active", "started_at": .number(now)], at: now)
        let typeName = TBox.leafTaskTypes.contains(def.taskType ?? "") ? def.taskType! : TBox.fallbackTaskType
        if let typeNode = try tx.node(label: NodeLabel.taskType, key: typeName) {
            try tx.upsertEdge(src: taskId, dst: typeNode.id, type: EdgeType.instanceOf, props: [:], addWeight: 0, at: now, countHit: false)
        }
        return (taskId, true)
    }

    public static func normalizeTitle(_ title: String) -> String {
        title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

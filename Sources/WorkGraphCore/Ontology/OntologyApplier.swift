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

    public init() {}
}

/// LLM 패치를 그래프 upsert 로 바꾼다. "무엇이 어떤 업무에 속하고 서로 어떤 관계인가"를 붙이는 단계.
public struct OntologyApplier: Sendable {
    /// 같은 업무의 직전 세션이 이 시간 안에 끝났으면 새 세션을 만들지 않고 이어 붙인다.
    public var sessionGap: Double = 300
    static let switchKinds: Set<String> = ["planned", "drift", "blocked"]

    public init() {}

    public func apply(_ patch: OntologyPatch, rows: [ActivityRow], tx: GraphTx, now: Double) throws -> ApplyStats {
        var stats = ApplyStats()
        var covered = Set<Int>()
        var resourceKeys = Set<String>(), topicKeys = Set<String>()
        let byNumber = Dictionary(rows.map { ($0.row, $0) }, uniquingKeysWith: { first, _ in first })
        let lastRow = rows.map(\.row).max() ?? 0

        for segment in patch.segments.sorted(by: { $0.fromRow < $1.fromRow }) {
            let low = max(1, segment.fromRow), high = min(lastRow, segment.toRow)
            guard low <= high else { continue }
            let segmentRows = (low...high).compactMap { byNumber[$0] }.filter { !covered.contains($0.row) }
            guard let first = segmentRows.first, let last = segmentRows.last else { continue }
            segmentRows.forEach { covered.insert($0.row) }
            let start = first.start, end = last.end
            let active = Double(segmentRows.reduce(0) { $0 + $1.dwell })

            // 1. Task
            let (taskId, created) = try resolveTask(segment.task, start: start, tx: tx)
            if created { stats.tasksCreated += 1 }
            let previous = try tx.node(id: taskId)
            let total = (previous?.props["active_seconds"]?.doubleValue ?? 0) + active
            let lastActive = max(previous?.props["last_active"]?.doubleValue ?? 0, end)
            try tx.setProps(nodeId: taskId, ["active_seconds": .number(total), "last_active": .number(lastActive)], at: end)

            // 2. Session (직전 세션이 가까우면 이어 붙임)
            let sessionId: Int64
            let summary = segment.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if let latest = try tx.latestSession(ofTask: taskId),
               let latestEnd = latest.props["end"]?.doubleValue,
               start - latestEnd < sessionGap, start >= (latest.props["start"]?.doubleValue ?? 0) {
                sessionId = latest.id
                var props: [String: JSONValue] = [
                    "end": .number(max(latestEnd, end)),
                    "active_seconds": .number((latest.props["active_seconds"]?.doubleValue ?? 0) + active),
                ]
                if !summary.isEmpty { props["summary"] = .string(summary) }
                try tx.upsertNode(label: NodeLabel.session, key: latest.key, subtype: nil,
                                  title: summary.isEmpty ? nil : summary, props: props, at: end)
                stats.sessionsExtended += 1
            } else {
                let taskKey = previous?.key ?? "t"
                let title = summary.isEmpty ? (previous?.title ?? "세션") : summary
                sessionId = try tx.upsertNode(label: NodeLabel.session, key: "s_\(taskKey)_\(Int(start))", subtype: nil, title: title,
                                              props: ["start": .number(start), "end": .number(end),
                                                      "active_seconds": .number(active), "summary": .string(summary)], at: end)
                try tx.upsertEdge(src: sessionId, dst: taskId, type: EdgeType.partOf, props: [:], addWeight: 0, at: end)
                stats.sessions += 1
            }

            // 3. 행마다 App / Resource / Project
            var resourceIdByRow: [Int: Int64] = [:]
            for row in segmentRows {
                if !row.isChat {           // AI 대화 행은 앱 사용 시간이 아니라 자료(AIChat)로만 남긴다
                    let appId = try tx.upsertNode(label: NodeLabel.app, key: row.appBundle, subtype: nil, title: row.app, props: [:], at: row.end)
                    try tx.upsertEdge(src: sessionId, dst: appId, type: EdgeType.used, props: [:], addWeight: Double(row.dwell), at: row.end)
                }

                guard let uri = row.uri, !uri.isEmpty else { continue }
                let resourceId = try tx.upsertNode(label: NodeLabel.resource, key: uri, subtype: row.type, title: row.title,
                                                   props: ["last_seen": .number(row.end)], at: row.end)
                resourceIdByRow[row.row] = resourceId
                if resourceKeys.insert(uri).inserted { stats.resources += 1 }
                try tx.upsertEdge(src: sessionId, dst: resourceId, type: EdgeType.touched, props: [:], addWeight: Double(row.dwell), at: row.end)
                if let type = row.type, let typeNode = try tx.node(label: NodeLabel.resourceType, key: type) {
                    try tx.upsertEdge(src: resourceId, dst: typeNode.id, type: EdgeType.instanceOf, props: [:], addWeight: 0, at: row.end, countHit: false)
                }
                if let projectKey = row.projectKey {
                    let projectId = try tx.upsertNode(label: NodeLabel.project, key: projectKey, subtype: nil,
                                                      title: row.projectTitle ?? projectKey, props: [:], at: row.end)
                    try tx.upsertEdge(src: resourceId, dst: projectId, type: EdgeType.belongsTo, props: [:], addWeight: 0, at: row.end, countHit: false)
                    try tx.upsertEdge(src: taskId, dst: projectId, type: EdgeType.on, props: [:], addWeight: 0, at: row.end, countHit: false)
                }
            }

            // 4. Topic
            for raw in segment.topics.prefix(6) {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let key = name.lowercased()
                let existing = try tx.node(label: NodeLabel.topic, key: key)
                let topicId = try tx.upsertNode(label: NodeLabel.topic, key: key, subtype: nil,
                                                title: existing == nil ? name : nil, props: [:], at: end)
                try tx.upsertEdge(src: taskId, dst: topicId, type: EdgeType.about, props: [:], addWeight: 0, at: end)
                if topicKeys.insert(key).inserted { stats.topics += 1 }
            }

            // 5. Problem — 자료가 아니라 "겪은 상태"라서 별도 클래스
            for problem in segment.problems ?? [] {
                let message = problem.message.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !message.isEmpty else { continue }
                let at = byNumber[problem.row]?.start ?? start
                let problemId = try tx.upsertNode(label: NodeLabel.problem, key: "problem:\(problem.kind):\(StableHash.short(message.lowercased()))",
                                                  subtype: problem.kind, title: message, props: ["kind": .string(problem.kind)], at: at)
                try tx.upsertEdge(src: sessionId, dst: problemId, type: EdgeType.hit, props: [:], addWeight: 0, at: at)
                if let solvedRow = problem.resolvedByRow {
                    var solver = resourceIdByRow[solvedRow]
                    if solver == nil, let uri = byNumber[solvedRow]?.uri { solver = try tx.node(label: NodeLabel.resource, key: uri)?.id }
                    if let solver {
                        try tx.upsertEdge(src: problemId, dst: solver, type: EdgeType.resolvedBy, props: [:], addWeight: 0,
                                          at: byNumber[solvedRow]?.end ?? end)
                    }
                }
                stats.problems += 1
            }

            // 6. LaterItem
            for item in segment.laterItems ?? [] {
                let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let source = byNumber[item.row]
                var props: [String: JSONValue] = ["done": false, "at": .number(source?.start ?? end)]
                if let app = source?.app { props["source_app"] = .string(app) }
                let itemId = try tx.upsertNode(label: NodeLabel.laterItem, key: "later:\(StableHash.short(text.lowercased()))",
                                               subtype: nil, title: text, props: props, at: source?.start ?? end)
                try tx.upsertEdge(src: itemId, dst: taskId, type: EdgeType.forTask, props: [:], addWeight: 0, at: end)
                stats.laterItems += 1
            }

            // 7. 업무 전환: 직전 세션이 다른 업무였다면 SWITCHED_TO
            if let previousSession = try tx.latestSession(startedBefore: start, excluding: sessionId),
               try tx.edges(from: previousSession.id, type: EdgeType.partOf).first?.dst != taskId {
                let kind = segment.switchKind.flatMap { Self.switchKinds.contains($0) ? $0 : nil } ?? "unknown"
                try tx.upsertEdge(src: previousSession.id, dst: sessionId, type: EdgeType.switchedTo,
                                  props: ["kind": .string(kind)], addWeight: 0, at: start)
            }
        }
        stats.uncoveredRows = rows.count - covered.count
        _ = now
        return stats
    }

    /// existing → id 로 찾고, 못 찾으면 제목으로 찾고, 그래도 없으면 새로 만든다.
    func resolveTask(_ ref: OntologyPatch.TaskRef, start: Double, tx: GraphTx) throws -> (id: Int64, created: Bool) {
        if ref.match == "existing", let id = ref.id, let node = try tx.node(label: NodeLabel.task, key: id) {
            return (node.id, false)
        }
        let title = Self.normalizeTitle(ref.title)
        if !title.isEmpty, let same = try tx.nodes(label: NodeLabel.task).first(where: { Self.normalizeTitle($0.title).lowercased() == title.lowercased() }) {
            return (same.id, false)
        }
        let finalTitle = title.isEmpty ? "이름 없는 업무" : title
        let key = "t_\(StableHash.short("\(finalTitle)|\(Int(start))"))"
        let taskId = try tx.upsertNode(label: NodeLabel.task, key: key, subtype: nil, title: finalTitle,
                                       props: ["status": "active", "started_at": .number(start)], at: start)
        let typeName = TBox.leafTaskTypes.contains(ref.taskType) ? ref.taskType : TBox.fallbackTaskType
        if let typeNode = try tx.node(label: NodeLabel.taskType, key: typeName) {
            try tx.upsertEdge(src: taskId, dst: typeNode.id, type: EdgeType.instanceOf, props: [:], addWeight: 0, at: start, countHit: false)
        }
        return (taskId, true)
    }

    static func normalizeTitle(_ title: String) -> String {
        title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

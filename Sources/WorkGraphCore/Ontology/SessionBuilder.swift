import Foundation

/// 행 하나의 판단 결과: 어느 업무인가, 그 행의 파일·페이지가 그 업무의 자료인가
public struct RowAssignment: Equatable, Sendable {
    public var row: ActivityRow
    public var taskId: Int64?
    public var resource: Bool
    /// 어떤 목표에도 기여하지 않는 행 (집중 이탈). 업무·세션·자료를 만들지 않고 시간만 남는다
    public var offTask: Bool
    /// LLM 이 적은 판정 이유 (한 구절)
    public var reason: String?
    public init(row: ActivityRow, taskId: Int64?, resource: Bool = true, offTask: Bool = false, reason: String? = nil) {
        self.row = row; self.taskId = taskId; self.resource = resource; self.offTask = offTask; self.reason = reason
    }
}

/// 세션 = 같은 업무의 행이 시간순으로 이어진 구간. 업무를 정하는 데는 쓰이지 않고, 정해진 행을 시간으로 묶어 보여 주는 것이다.
///   - 같은 업무가 gap(30분) 안에 다시 나오면 같은 세션으로 잇는다
///   - 다른 업무가 끼어들어도 세션은 갈리지 않는다 (끼어든 업무는 제 세션을 갖고, 흐름은 SWITCHED_TO 로 남는다)
/// LLM 없이 행 판단(observations.task_id)에서 언제든 다시 계산할 수 있다.
public struct SessionBuilder: Sendable {
    public struct Stats: Equatable, Sendable {
        public var sessions = 0, sessionsExtended = 0, resources = 0
        public init() {}
    }

    public var gap: Double = 1_800

    public init(gap: Double = 1_800) { self.gap = gap }

    /// 세션 제목: "9/22 14:45–20:01 · 업무 제목"
    static func title(task: String, start: Double, end: Double) -> String {
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "M/d HH:mm"
        let clock = DateFormatter(); clock.locale = Locale(identifier: "en_US_POSIX"); clock.dateFormat = "HH:mm"
        return "\(day.string(from: Date(timeIntervalSince1970: start)))–\(clock.string(from: Date(timeIntervalSince1970: end))) · \(task)"
    }

    /// 행들을 세션에 반영한다. summaries: 업무 id → 이 행들에서 한 일 (세션 요약). 돌려주는 값: 행 번호 → 세션 id
    @discardableResult
    public func apply(_ assignments: [RowAssignment], summaries: [Int64: String], tx: GraphTx, stats: inout Stats) throws -> [Int: Int64] {
        let ordered = assignments.filter { $0.taskId != nil }.sorted { ($0.row.start, $0.row.row) < ($1.row.start, $1.row.row) }
        var sessionOf: [Int64: Int64] = [:]            // 업무 → 이번에 쓰는 세션
        var sessionByRow: [Int: Int64] = [:]
        var resourceKeys = Set<String>()
        var previousSession: Int64?

        for item in ordered {
            guard let taskId = item.taskId, let task = try tx.node(id: taskId) else { continue }
            let row = item.row
            let sessionId: Int64
            if let known = sessionOf[taskId] {
                sessionId = known
            } else if let latest = try tx.latestSession(ofTask: taskId), let latestEnd = latest.props["end"]?.doubleValue,
                      row.start - latestEnd <= gap, row.start >= (latest.props["start"]?.doubleValue ?? 0) - gap {
                sessionId = latest.id
                stats.sessionsExtended += 1
            } else {
                sessionId = try tx.upsertNode(label: NodeLabel.session, key: "s_\(task.key)_\(Int(row.start))", subtype: nil,
                                              title: Self.title(task: task.title, start: row.start, end: row.end),
                                              props: ["start": .number(row.start), "end": .number(row.end), "active_seconds": .number(0),
                                                      "summary": .string(""), "summaries": .array([])], at: row.start)
                try tx.upsertEdge(src: sessionId, dst: taskId, type: EdgeType.partOf, props: [:], addWeight: 0, at: row.start)
                stats.sessions += 1
            }
            sessionOf[taskId] = sessionId
            sessionByRow[row.row] = sessionId

            // 시간 범위, 실제 작업 시간, 요약(배치마다 한 문장씩 누적 — 덮어쓰면 마지막 5분만 남는다)
            if let session = try tx.node(id: sessionId) {
                let start = min(session.props["start"]?.doubleValue ?? row.start, row.start)
                let end = max(session.props["end"]?.doubleValue ?? row.end, row.end)
                var props: [String: JSONValue] = [
                    "start": .number(start), "end": .number(end),
                    "active_seconds": .number((session.props["active_seconds"]?.doubleValue ?? 0) + Double(row.dwell)),
                ]
                if let summary = summaries[taskId], !summary.isEmpty {
                    var list = session.props["summaries"]?.arrayValue?.compactMap(\.stringValue) ?? []
                    if !list.contains(summary) { list.append(summary) }
                    props["summaries"] = .array(list.suffix(40).map { .string($0) })
                    props["summary"] = .string(summary)                      // 가장 최근 것 (업무 후보 목록의 recent work 용)
                }
                try tx.upsertNode(label: NodeLabel.session, key: session.key, subtype: nil,
                                  title: Self.title(task: task.title, start: start, end: end), props: props, at: row.end)
            }

            // 앱
            if !row.isChat {
                let appId = try tx.upsertNode(label: NodeLabel.app, key: row.appBundle, subtype: nil, title: row.app, props: [:], at: row.end)
                try tx.upsertEdge(src: sessionId, dst: appId, type: EdgeType.used, props: [:], addWeight: Double(row.dwell), at: row.end)
            }
            // 자료 (보이기만 한 것, 검색 결과·빈 탭·로그인 같은 지나가는 페이지는 제외)
            if item.resource, let uri = row.uri, !uri.isEmpty, !TransientPages.isTransient(url: uri, title: row.title) {
                let resourceId = try tx.upsertNode(label: NodeLabel.resource, key: uri, subtype: row.type, title: row.title,
                                                   props: ["last_seen": .number(row.end)], at: row.end)
                if resourceKeys.insert(uri).inserted { stats.resources += 1 }
                try tx.upsertEdge(src: sessionId, dst: resourceId, type: EdgeType.touched, props: [:], addWeight: Double(row.dwell), at: row.end)
                if let type = row.type, let typeNode = try tx.node(label: NodeLabel.resourceType, key: type) {
                    try tx.upsertEdge(src: resourceId, dst: typeNode.id, type: EdgeType.instanceOf, props: [:], addWeight: 0, at: row.end, countHit: false)
                }
                if let projectKey = row.projectKey {
                    let projectId = try tx.upsertNode(label: NodeLabel.project, key: projectKey, subtype: nil,
                                                      title: row.projectTitle ?? projectKey, props: [:], at: row.end)
                    try tx.upsertEdge(src: resourceId, dst: projectId, type: EdgeType.belongsTo, props: [:], addWeight: 0, at: row.end, countHit: false)
                }
            }

            // 흐름: 직전 행의 세션에서 이 세션으로
            if previousSession == nil, let before = try tx.latestSession(startedBefore: row.start, excluding: sessionId),
               (before.props["end"]?.doubleValue ?? 0) >= row.start - gap {
                previousSession = before.id
            }
            if let previous = previousSession, previous != sessionId {
                try tx.upsertEdge(src: previous, dst: sessionId, type: EdgeType.switchedTo, props: ["kind": .string("unknown")], addWeight: 0, at: row.start)
            }
            previousSession = sessionId
        }
        return sessionByRow
    }
}

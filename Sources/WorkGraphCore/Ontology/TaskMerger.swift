import Foundation
import GRDB

/// 제목만 다른 같은 목표를 합친다. 판단은 LLM ("이 업무들이 같은 목표인가"), 반영은 기계적으로:
/// 행 판단(task_id)·세션·주제·나중에 할 일·시간을 남길 업무로 옮기고 나머지 노드를 지운다.
/// 시간이나 제목 유사도로 자동 병합하지 않는다.
public struct TaskMerger: Sendable {
    public struct Group: Codable, Equatable, Sendable {
        public var keep: String
        public var merge: [String]
        public var title: String?
        public init(keep: String, merge: [String], title: String? = nil) { self.keep = keep; self.merge = merge; self.title = title }
    }

    public struct Result: Equatable, Sendable {
        public var groups: [Group] = []
        public var merged = 0
        public var raw = ""
        public init() {}
    }

    static let system = """
    You decide which of the user's tasks are the SAME GOAL recorded twice under different titles, for a personal work graph.
    A task is a goal: a project or deliverable, a course being studied, a recurring routine, a leisure activity. Two tasks are the same goal when their titles, topics, recent work and resources describe the same project/deliverable, the same course, the same routine or the same kind of leisure. Sub-steps of one goal (reading docs for it, checking a tool's usage for it, installing a tool for it, looking at examples for it) are that goal, not separate goals.
    Do NOT merge different goals that merely share an app, a website or a topic word; do not merge a course with a project; do not merge work with leisure.
    Return groups only for tasks that should be merged; keep = the id whose title best names the goal (prefer the specific, established one); title = a better Korean title if the kept one is vague. Leave everything else alone. Always answer by calling merge_tasks.
    """

    static var tool: ToolSpec {
        ToolSpec(name: "merge_tasks", description: "Groups of task ids that are the same goal.", parameters: .object([
            "type": "object",
            "properties": .object([
                "groups": .object(["type": "array", "items": .object([
                    "type": "object",
                    "properties": .object([
                        "keep": .object(["type": "string", "description": "남길 업무 id"]),
                        "merge": .object(["type": "array", "items": .object(["type": "string"]), "description": "keep 에 합칠 업무 id 들"]),
                        "title": .object(["type": "string", "description": "남길 업무의 제목이 모호할 때만, 더 나은 한국어 제목"]),
                    ]),
                    "required": .array(["keep", "merge"]),
                ])]),
            ]),
            "required": .array(["groups"]),
        ]))
    }

    static func prompt(_ tasks: [TaskDigest]) -> String {
        var lines = ["TASKS:"]
        for task in tasks {
            var line = "- id=\(task.id) | \(task.title) | \(task.taskType ?? "기타")"
            if !task.topics.isEmpty { line += " | topics: \(task.topics.joined(separator: ", "))" }
            if !task.recentSummaries.isEmpty { line += " | recent work: \(task.recentSummaries.map { OntologyPrompt.clip($0, 120) }.joined(separator: " / "))" }
            if !task.recentResources.isEmpty { line += " | resources: \(task.recentResources.prefix(4).map { OntologyPrompt.clip($0, 50) }.joined(separator: "; "))" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// LLM 에 묻고 (dry 가 아니면) 반영한다. 돌려주는 값에 그룹과 합친 수
    public static func run(db: WGDatabase, llm: any LLMClient, since: Double, now: Double, dry: Bool = false) async throws -> Result {
        let tasks = try await db.writer.read { try GraphTx($0).openTasks(limit: 60, since: since) }
        var result = Result()
        guard tasks.count >= 2 else { return result }
        let answer = try await llm.callFunction(system: system, user: prompt(tasks), tool: tool)
        result.raw = answer.raw
        guard let parsed = try? JSONDecoder().decode([String: [Group]].self, from: answer.arguments), let groups = parsed["groups"] else { return result }
        let known = Set(tasks.map(\.id))
        result.groups = groups.compactMap { group in
            let targets = group.merge.filter { known.contains($0) && $0 != group.keep }
            return known.contains(group.keep) && !targets.isEmpty ? Group(keep: group.keep, merge: targets, title: group.title) : nil
        }
        guard !dry else { return result }
        let accepted = result.groups
        result.merged = try await db.writer.write { conn in
            var count = 0
            for group in accepted { count += try merge(group, conn: conn, now: now) }
            return count
        }
        return result
    }

    /// 한 그룹 반영. 합친 업무 수를 돌려준다
    static func merge(_ group: Group, conn: Database, now: Double) throws -> Int {
        let tx = GraphTx(conn)
        guard let keep = try tx.node(label: NodeLabel.task, key: group.keep) else { return 0 }
        var accumulated = keep.props
        var merged = 0
        for key in group.merge {
            guard let victim = try tx.node(label: NodeLabel.task, key: key), victim.id != keep.id else { continue }
            // 행 판단
            try conn.execute(sql: "UPDATE observations SET task_id = ? WHERE task_id = ?", arguments: [keep.id, victim.id])
            try conn.execute(sql: "UPDATE chat_messages SET task_id = ? WHERE task_id = ?", arguments: [keep.id, victim.id])
            // 세션, 나중에 할 일 → 남길 업무로. 주제는 겹치지 않는 것만
            try conn.execute(sql: "UPDATE edges SET dst = ? WHERE dst = ? AND type IN ('PART_OF', 'FOR')", arguments: [keep.id, victim.id])
            for edge in try tx.edges(from: victim.id, type: EdgeType.about) {
                try tx.upsertEdge(src: keep.id, dst: edge.dst, type: EdgeType.about, props: [:], addWeight: 0, at: edge.lastAt)
            }
            // 시간
            var props: [String: JSONValue] = [
                "active_seconds": .number((accumulated["active_seconds"]?.doubleValue ?? 0) + (victim.props["active_seconds"]?.doubleValue ?? 0)),
                "last_active": .number(max(accumulated["last_active"]?.doubleValue ?? 0, victim.props["last_active"]?.doubleValue ?? 0)),
            ]
            var tally = accumulated["project_seconds"]?.objectValue ?? [:]
            for (project, seconds) in victim.props["project_seconds"]?.objectValue ?? [:] {
                tally[project] = .number((tally[project]?.doubleValue ?? 0) + (seconds.doubleValue ?? 0))
            }
            if !tally.isEmpty { props["project_seconds"] = .object(tally) }
            try tx.setProps(nodeId: keep.id, props, at: now)
            accumulated.merge(props) { _, new in new }
            try conn.execute(sql: "DELETE FROM edges WHERE src = ? OR dst = ?", arguments: [victim.id, victim.id])
            try conn.execute(sql: "DELETE FROM nodes WHERE id = ?", arguments: [victim.id])
            merged += 1
        }
        if let title = group.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title != keep.title {
            try tx.upsertNode(label: NodeLabel.task, key: keep.key, subtype: nil, title: title, props: [:], at: now)
        }
        if merged > 0 { try tx.rebindProjects(at: now) }
        return merged
    }
}

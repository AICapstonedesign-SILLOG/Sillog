import Foundation

public enum OntologyPrompt {
    public static let system = """
    You turn raw desktop activity rows into an ontology patch for a personal work graph.

    You receive:
    - TASK_TYPES: the only allowed values for task_type.
    - OPEN_TASKS: tasks the user worked on recently (id, title, type, topics, recent resources).
    - ROWS: time-ordered activity rows. One row = one app/window context with its dwell seconds. `type` and `uri` were assigned by rules and are reliable.
      Rows whose app is "Claude Code" or "Codex CLI" (type AIChat, dwell 0) are the user's own messages to an AI coding assistant, quoted in `text:`. They state what the user is trying to do in their own words: use them as the strongest evidence for the task title and topics, and keep them in the same segment as the surrounding work in that project.

    Do this:
    1. Split ROWS into contiguous segments. One segment = one stretch of work on ONE task. Every row belongs to exactly one segment. Prefer few, long segments: looking something up, checking a preview, running a command or answering a quick message is part of the surrounding task, not a new segment.
    2. Pick the task of each segment. Compare with OPEN_TASKS by project, topic and resources first; if it continues or resumes one of them use match="existing" with that id. When in doubt, reuse. Otherwise use match="new" with a short, specific Korean title that says what is being produced or learned (for example "대시보드 카드 UI 구현"), never an app name.
       A new task needs roughly 3 minutes of focused activity or a clearly distinct deliverable. Shorter visits belong to the surrounding task. Checking the same messenger, channel or inbox repeatedly is ONE recurring task, not a new task each time. Looking at the same subject twice (for example two visits to the same repository) is the same task even if the pages differ.
    3. task_type must be one of TASK_TYPES. Use "기타" when nothing fits.
    4. summary: one Korean sentence about what was done in the segment.
    5. topics: 1-4 short subject tags (technology, subject, project name). Reuse the spelling from OPEN_TASKS when it is the same thing.
    6. problems: only when the rows show an error or blocker (build error, failed command, searching an error message). Set resolved_by_row to the row of the page that solved it when that is evident.
    7. later_items: requests or todos that arrived during the segment but were not handled in it (for example a chat message asking for a change).
    8. switch_kind says how the user ARRIVED at the segment from the previous one: "planned" (natural next task), "blocked" (left the previous task because stuck or waiting), "drift" (distraction unrelated to work). Omit it for the first segment or when unclear.
    9. Entertainment or social browsing unrelated to any task is its own segment with task_type "기타" and switch_kind "drift".

    Always answer by calling record_activity. Do not write prose.
    """

    public static func build(rows: [ActivityRow], openTasks: [TaskDigest], now: Double, timeZone: TimeZone = .current) -> (system: String, user: String) {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = timeZone
        clock.dateFormat = "HH:mm"
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = timeZone
        day.dateFormat = "yyyy-MM-dd HH:mm"

        var lines: [String] = []
        lines.append("NOW: \(day.string(from: Date(timeIntervalSince1970: now)))")
        lines.append("TASK_TYPES: \(TBox.leafTaskTypes.joined(separator: ", "))")
        lines.append("OPEN_TASKS:")
        if openTasks.isEmpty {
            lines.append("(none)")
        } else {
            for task in openTasks {
                var line = "- id=\(task.id) | \(task.title) | \(task.taskType ?? "기타")"
                if !task.topics.isEmpty { line += " | topics: \(task.topics.joined(separator: ", "))" }
                if !task.recentResources.isEmpty { line += " | recent: \(task.recentResources.joined(separator: "; "))" }
                lines.append(line)
            }
        }
        lines.append("ROWS (row | time | dwell | app | type | title | uri):")
        for row in rows {
            let time = "\(clock.string(from: Date(timeIntervalSince1970: row.start)))-\(clock.string(from: Date(timeIntervalSince1970: row.end)))"
            let fields = ["\(row.row)", time, "\(row.dwell)s", row.app, row.type ?? "-", clip(row.title ?? "-", 90), clip(row.uri ?? "-", 140)]
            lines.append(fields.joined(separator: " | "))
            if let snippet = row.snippet, !snippet.isEmpty { lines.append("    text: \(snippet)") }
        }
        return (system, lines.joined(separator: "\n"))
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "/")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}

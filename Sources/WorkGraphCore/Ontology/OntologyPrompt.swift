import Foundation

public enum OntologyPrompt {
    public static let system = """
    You assign raw desktop activity rows to tasks for a personal work graph.

    You receive:
    - TASK_TYPES: the only allowed values for task_type.
    - OPEN_TASKS: the user's current tasks (goals) from the last days: id, title, type, topics, what was done in its recent sessions (`recent work:`), recent resources.
    - ROWS: time-ordered activity rows. One row = one app/window context with its dwell seconds. `type` and `uri` were assigned by rules and are reliable.
      Rows whose app is "Claude Code" or "Codex CLI" (type AIChat, dwell 0) are the user's own messages to an AI coding assistant, quoted in `text:`. They say in the user's own words what they are trying to do: use them as the strongest evidence for what the surrounding rows are about.

    Do this:
    1. For EVERY row decide which task it is about, from the row's own content: its file, page, title and text. A row is never assigned to a task because neighbouring rows are; the rows arrive together only because they happened in the same minutes. Rows that are not work or leisure (lock screen, the desktop, app switching, the WorkGraph app itself) get task null.
    2. A task is a GOAL the user is pursuing, usually spanning hours or days: a project or its deliverable (building the capstone app, writing the 계획서), studying a course (its lectures, labs, notices), a recurring routine (checking the team's Discord), or a leisure activity (watching YouTube). Ask of each row: which goal does this serve? Sub-steps that serve a goal belong to that goal's task even when they look different from its title: reading documentation for it, checking the settings or usage of a tool used for it, installing a tool for it, looking at examples or references for it, understanding its design. Example: checking Codex usage, installing DBeaver to inspect the app's database and reading MCP docs while building the capstone app are all rows of the capstone app task, not new tasks.
       Reuse an OPEN_TASKS task (match="existing", its id) whenever the row serves that goal, judged by comparing the row's content with the task's title, `recent work:` text and resources. Create a new task (match="new") only for a goal that is not in OPEN_TASKS: a different course, a different project or deliverable, a different routine or leisure. Example: a machine-learning course lab notebook is a different goal from the capstone app, even though both are code in VS Code.
       A new task gets a short, specific Korean title that names the course/project and the goal (예: "AI 캡스톤디자인2 온톨로지 그래프 서비스 개발", "기학기 회귀분석 실습", "KFPL 팀 디스코드 확인", "YouTube 시청"). Never an app name alone, never a catch-all like "자잘한 확인", "프로젝트 작업 검토", "기타 작업". There is no minimum duration: a 10-second row about a distinct goal is that goal's row.
    3. resource=false for a row whose file or page was merely visible while the text shows the user was working on the task elsewhere: an editor tab that happened to be active, a window left open in the background. Its app time still counts; the file or page must not be linked to the task.
    4. work: for each task you used, one Korean sentence about what was done in these rows, and 1-4 topics: what the work is ABOUT (a concept, technique, technology, course subject or problem domain, 예: 선형대수, 온톨로지, 장치 코드 인증, Swift). NOT the app, website or platform used (Discord, GitHub, ChatGPT, e-Class, VS Code are tools), not the project name, no filler. Reuse the spelling from OPEN_TASKS when it is the same thing.
    5. problems: only when the rows show an error or blocker (build error, failed command, searching an error message). Set resolved_by_row to the row of the page that solved it when that is evident.
    6. later_items: requests or todos that arrived in these rows but were not handled (for example a chat message asking for a change).
    7. task_type must be one of TASK_TYPES.

    Cover every row exactly once. Use ranges like "5-12" only when every row in the range has the same task and the same resource value.
    Always answer by calling assign_rows. Do not write prose.
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
                if !task.recentSummaries.isEmpty { line += " | recent work: \(task.recentSummaries.map { clip($0, 140) }.joined(separator: " / "))" }
                if !task.recentResources.isEmpty { line += " | recent: \(task.recentResources.prefix(3).map { clip($0, 50) }.joined(separator: "; "))" }
                lines.append(line)
            }
        }
        lines.append("ROWS (row | time | dwell | app | type | title | uri) — assign every row:")
        for row in rows {
            let time = "\(clock.string(from: Date(timeIntervalSince1970: row.start)))-\(clock.string(from: Date(timeIntervalSince1970: row.end)))"
            let fields = ["\(row.row)", time, "\(row.dwell)s", row.app, row.type ?? "-", clip(row.title ?? "-", 90), clip(row.uri ?? "-", 140)]
            lines.append(fields.joined(separator: " | "))
            if let snippet = row.snippet, !snippet.isEmpty { lines.append("    text: \(snippet)") }
        }
        return (system, lines.joined(separator: "\n"))
    }

    public static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "/")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}

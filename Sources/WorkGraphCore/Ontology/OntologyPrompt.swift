import Foundation

public enum OntologyPrompt {
    public static let system = """
    You assign raw desktop activity rows to tasks for a personal work graph.

    You receive:
    - TASK_TYPES: the only allowed values for task_type.
    - OPEN_TASKS: the user's current tasks (goals) from the last days: id, title, type, topics, what was done in its recent sessions (`recent work:`), recent resources.
    - ROWS: time-ordered activity rows. One row = one app/window context with its dwell seconds. `type` and `uri` were assigned by rules and are reliable.
      Under a row, `screen:` is a description of what the screenshot of that moment showed in the front window (what the user was doing, and the content visible), written by a model that looked at the screen; it is the most reliable evidence of what the row is about. `text:` is raw text read from the window when no screenshot description exists; it may include menus and sidebars.
      Rows whose app is "Claude Code" or "Codex CLI" (type AIChat, dwell 0) are the user's own messages to an AI coding assistant, quoted in `text:`. They say in the user's own words what they are trying to do: use them as the strongest evidence for what the surrounding rows are about.

    Do this:
    1. For EVERY row decide one of three things:
       - task null: the row has no content the user engaged with — a system screen, a transition between apps, an empty, loading or authentication page, the WorkGraph app itself. Nothing to read or do.
       - task "off": the user engaged with content, but that content serves none of the user's goals (entertainment, idle browsing, looking at things unrelated to any goal).
       - a task: the content serves one of the user's goals (an existing id, or a new task).
       Weigh the row's evidence in this order: what the user typed or read (the `screen:` description, chat messages, then `text:`) > the window title > the file or page name. When the text contradicts the title — the text shows work on one goal while the file or page in front belongs to something else — the task follows the text, and that file or page is not a resource of the task.
       A row is never assigned to a task because neighbouring rows are; the rows arrive together only because they happened in the same minutes. Judge by content, not by the app or site: the same kind of page is a task's row when it is used for that goal and off-task when it serves no goal. For each entry, state in `reason` what the row contributes to the goal, in a few Korean words; if you cannot name a contribution, the row is "off".
    2. A task is a GOAL the user is pursuing, usually spanning hours or days: a project or one of its deliverables, a course being studied (its lectures, labs, notices), or a recurring routine the user keeps (a team channel, a community they run). Ask of each row: which goal does this serve? Sub-steps that serve a goal belong to that goal's task even when they look different from its title: reading documentation for it, checking the settings or usage of a tool used for it, installing a tool for it, looking at examples or references for it, understanding its design. Passive consumption that serves no goal is not a task; it is off-task.
       Reuse an OPEN_TASKS task (match="existing", its id) whenever the row serves that goal, judged by comparing the row's content with the task's title, `recent work:` text and resources. Create a new task (match="new") only for a goal that is not in OPEN_TASKS: a different course, a different project or deliverable, a different routine. Two goals stay separate even when they share an app or a tool.
       A new task gets a short, specific Korean title that names the course/project and the goal. Never an app name alone, never a catch-all like "자잘한 확인", "프로젝트 작업 검토", "기타 작업", "기타 웹 탐색" — browsing that serves no goal is "off", not a task. There is no minimum duration: a 10-second row about a distinct goal is that goal's row.
    3. resource (give it for every entry): true only when the row's file or page is a real reference or artifact of that task — something the user read, used or produced for it and would want to find again: a document, code file, notebook, design, note, docs page, paper, Q&A thread, video, AI chat, a page whose content the user actually read. false for everything else: a page merely visible while the user worked elsewhere (an editor tab that happened to be active, a background window), search results, blank or new tabs, login or redirect pages, listings, profiles and navigation pages passed through, notification or inbox checks, tool settings and usage pages, a chat channel merely glanced at. When in doubt, false — the graph should hold only material worth coming back to. The row's app time counts either way; only the resource link is dropped.
    4. work: for each task you used, one Korean sentence about what was done in these rows, and 1-4 topics: what the work is ABOUT (a concept, technique, technology, course subject or problem domain, 예: 선형대수, 온톨로지, 장치 코드 인증, Swift). NOT the app, website or platform used (Discord, GitHub, ChatGPT, e-Class, VS Code are tools), not the project name, no filler. Reuse the spelling from OPEN_TASKS when it is the same thing.
    5. problems: only when the rows show an error or blocker (build error, failed command, searching an error message). Set resolved_by_row to the row of the page that solved it when that is evident.
    6. later_items: requests or todos that arrived in these rows but were not handled (for example a chat message asking for a change).
    7. task_type must be one of TASK_TYPES.

    Cover every row exactly once. Use ranges like "5-12" only when every row in the range has the same task (or the same "off"/null), the same resource value and the same reason.
    Always answer by calling assign_rows. Do not write prose.
    """

    /// cards: 행 번호 → 그 행을 덮는 화면 기억 카드 (있으면 text: 대신 screen: 으로 넣는다)
    public static func build(rows: [ActivityRow], openTasks: [TaskDigest], now: Double, timeZone: TimeZone = .current,
                             cards: [Int: [ScreenCard]] = [:]) -> (system: String, user: String) {
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
        var shown: [Int64: Int] = [:]                       // 카드 id → 처음 보인 행
        for row in rows {
            let time = "\(clock.string(from: Date(timeIntervalSince1970: row.start)))-\(clock.string(from: Date(timeIntervalSince1970: row.end)))"
            let fields = ["\(row.row)", time, "\(row.dwell)s", row.app, row.type ?? "-", clip(row.title ?? "-", 90), clip(row.uri ?? "-", 140)]
            lines.append(fields.joined(separator: " | "))
            let rowCards = cards[row.row] ?? []
            if rowCards.isEmpty || row.isChat {
                if let snippet = row.snippet, !snippet.isEmpty { lines.append("    text: \(snippet)") }
                continue
            }
            for card in rowCards {
                guard let id = card.id else { continue }
                if let first = shown[id] { lines.append("    screen: (same screen as row \(first))"); continue }
                shown[id] = row.row
                lines.append("    screen: \(clip(card.activity, 200))")
                for line in card.contentLines.prefix(6) { lines.append("      · \(clip(line, 160))") }
            }
        }
        return (system, lines.joined(separator: "\n"))
    }

    public static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "/")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}

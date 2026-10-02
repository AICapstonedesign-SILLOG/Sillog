import Foundation
import GRDB

public struct ContextSearch: Sendable {
    let db: WGDatabase
    let projectID: String?
    let includeActivity: Bool
    /// Args: db는 수집 기록과 그래프가 저장된 DB이다.
    /// Returns: 읽기 전용 컨텍스트 검색기.
    /// Raises: 없음.
    public init(_ db: WGDatabase, projectID: String? = nil, includeActivity: Bool = true) {
        self.db = db; self.projectID = projectID; self.includeActivity = includeActivity
    }

    static func migrate(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v14-complete-chat-search") { conn in
            let content = "COALESCE(json_extract(payload, '$.text'), '') || char(10) || COALESCE((SELECT group_concat(json_extract(value, '$.title') || char(10) || json_extract(value, '$.content'), char(10)) FROM json_each(payload, '$.artifacts')), '')"
            try conn.execute(sql: """
                CREATE VIRTUAL TABLE app_messages_fts USING fts5(message_id UNINDEXED, text, tokenize='trigram');
                INSERT INTO app_messages_fts SELECT id, \(content) FROM app_messages WHERE json_extract(payload, '$.status') = 'complete';
                CREATE TRIGGER app_message_search_ai AFTER INSERT ON app_messages BEGIN
                  INSERT INTO app_messages_fts SELECT id, \(content) FROM app_messages WHERE id = new.id AND json_extract(payload, '$.status') = 'complete';
                END;
                CREATE TRIGGER app_message_search_ad AFTER DELETE ON app_messages BEGIN
                  DELETE FROM app_messages_fts WHERE message_id = old.id;
                END;
                CREATE TRIGGER app_message_search_au AFTER UPDATE ON app_messages BEGIN
                  DELETE FROM app_messages_fts WHERE message_id = old.id;
                  INSERT INTO app_messages_fts SELECT id, \(content) FROM app_messages WHERE id = new.id AND json_extract(payload, '$.status') = 'complete';
                END;
                """)
        }
    }

    private func conversationFilter(_ conn: Database) throws -> (String, StatementArguments) {
        if let projectID, try ProjectStore.projects(conn).first(where: { $0.id == projectID })?.memoryMode == .projectOnly {
            return ("c.project_id = ?", [projectID])
        }
        return ("(c.project_id IS NULL OR c.project_id NOT IN (SELECT id FROM app_projects WHERE json_extract(payload, '$.memoryMode') = 'projectOnly'))", [])
    }

    /// 프로젝트에 명시적으로 공유한 자료도 기억 범위에 포함한다. 대화 전용 첨부는 포함하지 않는다.
    func projectSourceIDs() throws -> [String] {
        try db.writer.read { conn in
            let filter = try conversationFilter(conn)
            return try String.fetchAll(conn, sql: "SELECT DISTINCT c.item_id FROM library_project_sources c WHERE \(filter.0)", arguments: filter.1)
        }
    }

    /// 전용 프로젝트는 대화뿐 아니라 그 업무의 화면·원문·그래프에서도 제외한다.
    private func access(_ conn: Database) throws -> (nodes: Set<Int64>?, tasks: Set<Int64>?, projectOnly: Bool) {
        let projects = try ProjectStore.projects(conn)
        if let projectID, projects.first(where: { $0.id == projectID })?.memoryMode == .projectOnly {
            return (try Self.nodeIDs(projectID, conn), Set(try Int64.fetchAll(conn, sql: "SELECT task_id FROM project_tasks WHERE project_id = ?", arguments: [projectID])), true)
        }
        let privateProjects = projects.filter { $0.memoryMode == .projectOnly }
        guard !privateProjects.isEmpty else { return (nil, nil, false) }
        var hiddenNodes: Set<Int64> = [], hiddenTasks: Set<Int64> = []
        for project in privateProjects {
            hiddenNodes.formUnion(try Self.nodeIDs(project.id, conn))
            hiddenTasks.formUnion(try Int64.fetchAll(conn, sql: "SELECT task_id FROM project_tasks WHERE project_id = ?", arguments: [project.id]))
        }
        let tasks = Set(try Int64.fetchAll(conn, sql: "SELECT id FROM nodes WHERE label = 'Task'")).subtracting(hiddenTasks)
        let publicMembers = tasks.union(try Int64.fetchAll(conn, sql: "SELECT src FROM edges WHERE type = 'PART_OF'\(Self.restriction("dst", tasks))"))
        let publicNodes = publicMembers.union(try Int64.fetchAll(conn, sql: "SELECT id FROM nodes WHERE label NOT IN ('Task', 'Session') AND (id IN (SELECT dst FROM edges WHERE 1\(Self.restriction("src", publicMembers))) OR id IN (SELECT src FROM edges WHERE 1\(Self.restriction("dst", publicMembers))))"))
        let nodes = Set(try Int64.fetchAll(conn, sql: "SELECT id FROM nodes")).subtracting(hiddenNodes.subtracting(publicNodes))
        return (nodes, tasks, false)
    }

    private static func taskRestriction(_ column: String, _ access: (nodes: Set<Int64>?, tasks: Set<Int64>?, projectOnly: Bool)) -> String {
        guard let tasks = access.tasks else { return "" }
        if access.projectOnly { return restriction(column, tasks) }
        let list = tasks.sorted().map(String.init).joined(separator: ",")
        return " AND (\(column) IS NULL\(list.isEmpty ? "" : " OR \(column) IN (\(list))"))"
    }

    private static func cardRestriction(_ access: (nodes: Set<Int64>?, tasks: Set<Int64>?, projectOnly: Bool)) -> String {
        guard access.tasks != nil else { return "" }
        let condition = String(taskRestriction("task_id", access).dropFirst(5))
        let forbidden = access.projectOnly ? "(task_id IS NULL OR NOT (\(condition)))" : "NOT (\(condition))"
        return " AND EXISTS (SELECT 1 FROM observations WHERE card_id = screen_cards.id AND \(condition)) AND NOT EXISTS (SELECT 1 FROM observations WHERE card_id = screen_cards.id AND \(forbidden))"
    }

    /// 프로젝트 업무와 직접 연결된 세션·자료만 허용한다. 공유 자료를 통해 다른 업무로 검색 범위를 넓히지 않는다.
    static func nodeIDs(_ projectID: String, _ conn: Database) throws -> Set<Int64> {
        Set(try Int64.fetchAll(conn, sql: """
            WITH members(id) AS (
              SELECT task_id FROM project_tasks WHERE project_id = ?
              UNION SELECT e.src FROM edges e JOIN project_tasks p ON p.task_id = e.dst
                WHERE p.project_id = ? AND e.type = 'PART_OF'
            )
            SELECT id FROM nodes WHERE id IN (SELECT id FROM members)
              OR (label NOT IN ('Task', 'Session') AND id IN (
                SELECT dst FROM edges WHERE src IN (SELECT id FROM members)
                UNION SELECT src FROM edges WHERE dst IN (SELECT id FROM members)
              ))
            """, arguments: [projectID, projectID]))
    }

    static func restriction(_ column: String, _ ids: Set<Int64>?) -> String {
        guard let ids else { return "" }
        return ids.isEmpty ? " AND 0" : " AND \(column) IN (\(ids.sorted().map(String.init).joined(separator: ",")))"
    }

    /// 짧은 한국어 검색어는 trigram 색인에 없으므로 부분 문자열 검색을 쓴다.
    /// Args: query는 검색어, 나머지는 코드에 정의된 테이블·열 이름이다.
    /// Returns: SQL 조건과 바인딩할 검색 값.
    /// Raises: 없음.
    static func match(_ query: String, index: String, row: String, fallback: String) -> (String, String) {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if !words.isEmpty, words.allSatisfy({ $0.count >= 3 }) {
            let phrase = words.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " OR ")
            return ("\(row) IN (SELECT rowid FROM \(index) WHERE \(index) MATCH ?)", phrase)
        }
        return ("instr(lower(\(fallback)), lower(?)) > 0", query)
    }

    /// Args: query는 핵심어, from·to는 검색 기간의 Unix 시각이다.
    /// Returns: 업무·요약·원문·사용자 요청에서 찾은 출처 목록.
    /// Raises: DB 검색 오류.
    public func search(query: String, from: Double = 0, to: Double = Date().timeIntervalSince1970) throws -> [ChatSource] {
        try db.writer.read { conn in
            var results: [ChatSource] = []
            let access = try access(conn), allowedNodes = access.nodes
            let activity = includeActivity ? "" : " AND 0"
            let needle = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            let node = Self.match(needle, index: "nodes_chat_fts", row: "id", fallback: "title || ' ' || key || ' ' || props")
            let nodes = try Row.fetchAll(conn, sql: "SELECT id, label, title, key, props FROM nodes WHERE label NOT IN ('TaskType', 'ResourceType') AND updated_at >= ? AND created_at <= ? AND (\(node.0))\(Self.restriction("id", allowedNodes))\(activity) ORDER BY updated_at DESC LIMIT 12", arguments: [from, to, node.1])
            for row in nodes {
                results.append(.init(id: "node:\(row["id"] as Int64)", title: "\(row["label"] as String) · \(row["title"] as String)", location: row["key"], excerpt: String((row["props"] as String).prefix(1200))))
            }
            let card = Self.match(needle, index: "screen_cards_fts", row: "id", fallback: "activity || ' ' || content || ' ' || COALESCE(uri, '')")
            let cards = Self.cardRestriction(access)
            for row in try Row.fetchAll(conn, sql: "SELECT * FROM screen_cards WHERE ts_end >= ? AND ts_start <= ? AND (\(card.0))\(cards)\(activity) ORDER BY ts_start DESC LIMIT 10", arguments: [from, to, card.1]) {
                results.append(.init(id: "card:\(row["id"] as Int64)", title: "화면 요약 · \(row["activity"] as String)", location: row["uri"] ?? "", excerpt: "\(Self.date(row["ts_start"])) (AI 요약)\n" + String((row["content"] as String).prefix(1600))))
            }
            let snapshot = Self.match(needle, index: "text_snapshots_chat_fts", row: "o.text_id", fallback: "COALESCE(t.text, '')")
            for row in try Row.fetchAll(conn, sql: """
                SELECT o.id, o.ts, o.app_name, o.window_title, o.url, o.doc_path, t.text
                FROM observations o LEFT JOIN text_snapshots t ON t.id = o.text_id
                WHERE o.ts >= ? AND o.ts <= ? AND ((\(snapshot.0)) OR instr(lower(COALESCE(o.window_title, '') || ' ' || COALESCE(o.url, '') || ' ' || COALESCE(o.doc_path, '')), lower(?)) > 0)
                \(Self.taskRestriction("o.task_id", access))\(activity) ORDER BY o.ts DESC LIMIT 10
                """, arguments: [from, to, snapshot.1, needle]) {
                results.append(.init(id: "observation:\(row["id"] as Int64)", title: "\(row["app_name"] as String) · \(row["window_title"] as String? ?? "활동")", location: row["url"] ?? row["doc_path"] ?? "", excerpt: "\(Self.date(row["ts"]))\n" + String((row["text"] as String? ?? "화면 텍스트 없음").prefix(1600))))
            }
            let chat = Self.match(needle, index: "chat_messages_chat_fts", row: "id", fallback: "text || ' ' || COALESCE(cwd, '')")
            for row in try Row.fetchAll(conn, sql: "SELECT * FROM chat_messages WHERE ts >= ? AND ts <= ? AND (\(chat.0))\(Self.taskRestriction("task_id", access))\(activity) ORDER BY ts DESC LIMIT 8", arguments: [from, to, chat.1]) {
                results.append(.init(id: "chat:\(row["id"] as Int64)", title: "\(row["tool"] as String) 사용자 메시지", location: row["cwd"] ?? "", excerpt: "\(Self.date(row["ts"]))\n" + String((row["text"] as String).prefix(1600))))
            }
            let filter = try conversationFilter(conn)
            let words = needle.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).prefix(24)
            let match = words.allSatisfy { $0.count >= 3 } && !words.isEmpty
                ? "m.id IN (SELECT message_id FROM app_messages_fts WHERE app_messages_fts MATCH ?)"
                : "(" + (words.isEmpty ? ["1"] : words.map { _ in "instr(lower(f.text || ' ' || json_extract(c.payload, '$.title')), lower(?)) > 0" }).joined(separator: " OR ") + ")"
            var arguments: StatementArguments = [from, to]
            if words.allSatisfy({ $0.count >= 3 }) && !words.isEmpty { arguments += [words.map { "\"\($0)\"" }.joined(separator: " OR ")] }
            else { arguments += StatementArguments(Array(words)) }
            arguments += [needle]
            arguments += filter.1; arguments += [projectID]
            let conversations = try Row.fetchAll(conn, sql: """
                SELECT m.id, json_extract(c.payload, '$.title') AS title, f.text
                FROM app_messages m JOIN app_conversations c ON c.id = m.conversation_id
                JOIN app_messages_fts f ON f.message_id = m.id
                WHERE m.created_at >= ? AND m.created_at <= ? AND json_extract(m.payload, '$.status') = 'complete'
                  AND (\(match) OR instr(lower(json_extract(c.payload, '$.title')), lower(?)) > 0) AND \(filter.0)
                ORDER BY CASE WHEN c.project_id = ? THEN 0 ELSE 1 END, m.created_at DESC, m.rowid DESC LIMIT 8
                """, arguments: arguments)
            for row in conversations {
                let text: String = row["text"]
                let range = words.compactMap { text.range(of: $0, options: .caseInsensitive) }.first
                let start = range.map { text.distance(from: text.startIndex, to: $0.lowerBound) } ?? 0
                results.append(.init(id: "message:\(row["id"] as String)", title: "대화 · \(row["title"] as String)", location: "", excerpt: String(text.dropFirst(max(0, start - 200)).prefix(1600))))
            }
            return results
        }
    }

    /// Args: sourceID는 검색 결과에 포함된 출처 식별자이다.
    /// Returns: 상세 원문. 노드이면 연결된 자료도 반환한다.
    /// Raises: DB 조회 오류.
    public func read(_ sourceID: String, start: Int = 1) throws -> [ChatSource] {
        let pieces = sourceID.split(separator: ":")
        guard pieces.count >= 2 else { return [] }
        if pieces[0] == "conversation" || pieces[0] == "message" {
            return try db.writer.read { conn in
                let filter = try conversationFilter(conn)
                if pieces[0] == "message" {
                    var args: StatementArguments = [String(pieces[1])]; args += filter.1
                    guard let row = try Row.fetchOne(conn, sql: "SELECT f.text, c.payload FROM app_messages_fts f JOIN app_messages m ON m.id = f.message_id JOIN app_conversations c ON c.id = m.conversation_id WHERE m.id = ? AND \(filter.0)", arguments: args) else { return [] }
                    let text: String = row["text"], offset = max(1, start), page = String(text.dropFirst(offset - 1).prefix(18000))
                    let title = try JSONDecoder().decode(ChatConversation.self, from: Data((row["payload"] as String).utf8)).title
                    return [.init(id: "message:\(pieces[1]):\(offset)", title: "대화 · \(title)", location: "", excerpt: page + "\n[전체 \(text.count)자 · 다음 시작 위치 \(offset + page.count)]")]
                }
                var args: StatementArguments = [String(pieces[1])]; args += filter.1
                guard let row = try Row.fetchOne(conn, sql: "SELECT c.payload FROM app_conversations c WHERE c.id = ? AND \(filter.0)", arguments: args) else { return [] }
                let title = try JSONDecoder().decode(ChatConversation.self, from: Data((row["payload"] as String).utf8)).title
                let rows = try Row.fetchAll(conn, sql: "SELECT m.id, f.text FROM app_messages m JOIN app_messages_fts f ON f.message_id = m.id WHERE conversation_id = ? ORDER BY created_at, m.rowid LIMIT 20 OFFSET ?", arguments: [String(pieces[1]), max(0, start - 1)])
                let text = rows.map { "[message:\($0["id"] as String)]\n\(String(($0["text"] as String).prefix(700)))" }.joined(separator: "\n\n")
                return [.init(id: "conversation:\(pieces[1]):\(max(1, start))", title: "대화 · \(title)", location: "", excerpt: text + "\n[다음 메시지 위치 \(max(1, start) + rows.count). 메시지 원문은 message ID로 조회하세요.]" )]
            }
        }
        guard includeActivity, let id = Int64(pieces[1]) else { return [] }
        return try db.writer.read { conn in
            let access = try access(conn), allowedNodes = access.nodes
            if access.tasks != nil {
                let allowed: Bool
                switch pieces[0] {
                case "node": allowed = allowedNodes?.contains(id) == true
                case "observation": allowed = try Bool.fetchOne(conn, sql: "SELECT EXISTS(SELECT 1 FROM observations WHERE id = ?\(Self.taskRestriction("task_id", access)))", arguments: [id]) == true
                case "card": allowed = try Bool.fetchOne(conn, sql: "SELECT EXISTS(SELECT 1 FROM screen_cards WHERE id = ?\(Self.cardRestriction(access)))", arguments: [id]) == true
                case "chat": allowed = try Bool.fetchOne(conn, sql: "SELECT EXISTS(SELECT 1 FROM chat_messages WHERE id = ?\(Self.taskRestriction("task_id", access)))", arguments: [id]) == true
                default: allowed = false
                }
                guard allowed else { return [] }
            }
            switch pieces[0] {
            case "node":
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT * FROM nodes WHERE (id = ? OR id IN (
                      SELECT dst FROM edges WHERE src = ? UNION SELECT src FROM edges WHERE dst = ?
                    ))\(Self.restriction("id", allowedNodes)) ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END, updated_at DESC LIMIT 25
                    """, arguments: [id, id, id, id])
                return rows.map { row in .init(id: "node:\(row["id"] as Int64)", title: "\(row["label"] as String) · \(row["title"] as String)", location: row["key"], excerpt: String((row["props"] as String).prefix(2500))) }
            case "observation":
                guard let row = try Row.fetchOne(conn, sql: "SELECT o.*, t.text FROM observations o LEFT JOIN text_snapshots t ON t.id = o.text_id WHERE o.id = ?", arguments: [id]) else { return [] }
                return [.init(id: sourceID, title: row["window_title"] ?? "활동 기록", location: row["url"] ?? row["doc_path"] ?? "", excerpt: "\(Self.date(row["ts"]))\n" + String((row["text"] as String? ?? "텍스트 없음").prefix(18000)))]
            case "card":
                guard let row = try Row.fetchOne(conn, sql: "SELECT * FROM screen_cards WHERE id = ?", arguments: [id]) else { return [] }
                return [.init(id: sourceID, title: row["activity"], location: row["uri"] ?? "", excerpt: "AI 화면 요약 (원문 아님)\n\(row["content"] as String)\n\(row["entities"] as String)")]
            case "chat":
                guard let row = try Row.fetchOne(conn, sql: "SELECT * FROM chat_messages WHERE id = ?", arguments: [id]) else { return [] }
                return [.init(id: sourceID, title: "사용자의 요청 (실행 완료 증거 아님)", location: row["cwd"] ?? "", excerpt: String((row["text"] as String).prefix(18000)))]
            default: return []
            }
        }
    }

    /// Args: time은 Unix 시각이다.
    /// Returns: 현지 시간으로 표시한 기록 시각.
    /// Raises: 없음.
    private static func date(_ time: Double) -> String { Date(timeIntervalSince1970: time).formatted(date: .numeric, time: .shortened) }
}

import Foundation
import GRDB

public struct ContextSearch: Sendable {
    let db: WGDatabase
    /// Args: db는 수집 기록과 그래프가 저장된 DB이다.
    /// Returns: 읽기 전용 컨텍스트 검색기.
    /// Raises: 없음.
    public init(_ db: WGDatabase) { self.db = db }

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
            let needle = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            let node = Self.match(needle, index: "nodes_chat_fts", row: "id", fallback: "title || ' ' || key || ' ' || props")
            let nodes = try Row.fetchAll(conn, sql: "SELECT id, label, title, key, props FROM nodes WHERE label NOT IN ('TaskType', 'ResourceType') AND updated_at >= ? AND created_at <= ? AND (\(node.0)) ORDER BY updated_at DESC LIMIT 12", arguments: [from, to, node.1])
            for row in nodes {
                results.append(.init(id: "node:\(row["id"] as Int64)", title: "\(row["label"] as String) · \(row["title"] as String)", location: row["key"], excerpt: String((row["props"] as String).prefix(1200))))
            }
            let card = Self.match(needle, index: "screen_cards_fts", row: "id", fallback: "activity || ' ' || content || ' ' || COALESCE(uri, '')")
            for row in try Row.fetchAll(conn, sql: "SELECT * FROM screen_cards WHERE ts_end >= ? AND ts_start <= ? AND (\(card.0)) ORDER BY ts_start DESC LIMIT 10", arguments: [from, to, card.1]) {
                results.append(.init(id: "card:\(row["id"] as Int64)", title: "화면 요약 · \(row["activity"] as String)", location: row["uri"] ?? "", excerpt: "\(Self.date(row["ts_start"])) (AI 요약)\n" + String((row["content"] as String).prefix(1600))))
            }
            let snapshot = Self.match(needle, index: "text_snapshots_chat_fts", row: "o.text_id", fallback: "COALESCE(t.text, '')")
            for row in try Row.fetchAll(conn, sql: """
                SELECT o.id, o.ts, o.app_name, o.window_title, o.url, o.doc_path, t.text
                FROM observations o LEFT JOIN text_snapshots t ON t.id = o.text_id
                WHERE o.ts >= ? AND o.ts <= ? AND ((\(snapshot.0)) OR instr(lower(COALESCE(o.window_title, '') || ' ' || COALESCE(o.url, '') || ' ' || COALESCE(o.doc_path, '')), lower(?)) > 0)
                ORDER BY o.ts DESC LIMIT 10
                """, arguments: [from, to, snapshot.1, needle]) {
                results.append(.init(id: "observation:\(row["id"] as Int64)", title: "\(row["app_name"] as String) · \(row["window_title"] as String? ?? "활동")", location: row["url"] ?? row["doc_path"] ?? "", excerpt: "\(Self.date(row["ts"]))\n" + String((row["text"] as String? ?? "화면 텍스트 없음").prefix(1600))))
            }
            let chat = Self.match(needle, index: "chat_messages_chat_fts", row: "id", fallback: "text || ' ' || COALESCE(cwd, '')")
            for row in try Row.fetchAll(conn, sql: "SELECT * FROM chat_messages WHERE ts >= ? AND ts <= ? AND (\(chat.0)) ORDER BY ts DESC LIMIT 8", arguments: [from, to, chat.1]) {
                results.append(.init(id: "chat:\(row["id"] as Int64)", title: "\(row["tool"] as String) 사용자 메시지", location: row["cwd"] ?? "", excerpt: "\(Self.date(row["ts"]))\n" + String((row["text"] as String).prefix(1600))))
            }
            return results
        }
    }

    /// Args: sourceID는 검색 결과에 포함된 출처 식별자이다.
    /// Returns: 상세 원문. 노드이면 연결된 자료도 반환한다.
    /// Raises: DB 조회 오류.
    public func read(_ sourceID: String) throws -> [ChatSource] {
        let pieces = sourceID.split(separator: ":")
        guard pieces.count == 2, let id = Int64(pieces[1]) else { return [] }
        return try db.writer.read { conn in
            switch pieces[0] {
            case "node":
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT * FROM nodes WHERE id = ? OR id IN (
                      SELECT dst FROM edges WHERE src = ? UNION SELECT src FROM edges WHERE dst = ?
                    ) ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END, updated_at DESC LIMIT 25
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

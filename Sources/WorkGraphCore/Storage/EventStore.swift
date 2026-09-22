import Foundation
import GRDB
import CryptoKit

/// L0 원시층 읽기/쓰기. append-only 로 쌓고, 배치가 끝난 행에는 batch_id 만 찍는다.
public struct EventStore: Sendable {
    let db: WGDatabase

    public init(_ db: WGDatabase) { self.db = db }

    // MARK: 쓰기

    @discardableResult
    public func insert(_ observation: Observation) throws -> Int64 {
        try db.writer.write { conn in
            var copy = observation
            try copy.insert(conn)
            return copy.id ?? conn.lastInsertedRowID
        }
    }

    /// 같은 텍스트는 해시로 한 번만 저장한다.
    @discardableResult
    public func upsertText(_ text: String, source: String, at: Double) throws -> Int64 {
        let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        return try db.writer.write { conn in
            if let id = try Int64.fetchOne(conn, sql: "SELECT id FROM text_snapshots WHERE hash = ?", arguments: [hash]) { return id }
            try conn.execute(sql: "INSERT INTO text_snapshots(hash, source, text, created_at) VALUES (?, ?, ?, ?)",
                             arguments: [hash, source, text, at])
            return conn.lastInsertedRowID
        }
    }

    public func attach(observationId: Int64, textId: Int64?, screenshotPath: String?) throws {
        try db.writer.write { conn in
            try conn.execute(sql: """
                UPDATE observations SET text_id = COALESCE(?, text_id), screenshot_path = COALESCE(?, screenshot_path) WHERE id = ?
                """, arguments: [textId, screenshotPath, observationId])
        }
    }

    public func insertFileEvent(_ event: FileEvent) throws {
        try db.writer.write { conn in
            var copy = event
            try copy.insert(conn)
        }
    }

    public func openIdle(at: Double) throws {
        try db.writer.write { conn in
            let open = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM idle_spans WHERE end_ts IS NULL") ?? 0
            if open == 0 { try conn.execute(sql: "INSERT INTO idle_spans(start_ts) VALUES (?)", arguments: [at]) }
        }
    }

    public func closeIdle(at: Double) throws {
        try db.writer.write { conn in
            try conn.execute(sql: "UPDATE idle_spans SET end_ts = ? WHERE end_ts IS NULL", arguments: [at])
        }
    }

    public static func mark(_ conn: Database, observationIds: [Int64], batchId: Int64) throws {
        guard !observationIds.isEmpty else { return }
        let list = observationIds.map(String.init).joined(separator: ",")
        try conn.execute(sql: "UPDATE observations SET batch_id = ? WHERE id IN (\(list))", arguments: [batchId])
    }

    // MARK: AI 대화 기록

    /// 같은 (도구, 세션, 시각) 메시지는 한 번만 저장한다. 새로 들어간 개수를 돌려준다.
    @discardableResult
    public func insertChatMessages(_ messages: [ChatMessage]) throws -> Int {
        guard !messages.isEmpty else { return 0 }
        return try db.writer.write { conn in
            var inserted = 0
            for message in messages {
                try conn.execute(sql: """
                    INSERT OR IGNORE INTO chat_messages(ts, tool, session_id, cwd, text, ingested_at) VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [message.ts, message.tool, message.sessionId, message.cwd, message.text, message.ingestedAt])
                inserted += conn.changesCount
            }
            return inserted
        }
    }

    public func chatMessages(from: Double, to: Double) throws -> [ChatMessage] {
        try db.writer.read { conn in
            try ChatMessage.fetchAll(conn, sql: "SELECT * FROM chat_messages WHERE ts >= ? AND ts <= ? ORDER BY ts", arguments: [from, to])
        }
    }

    /// 아직 어느 배치에도 쓰이지 않은 메시지 중 `upTo` 이전 것. 창보다 오래된 메시지도 포함해서 빠지는 게 없게 한다.
    public func unprocessedChatMessages(upTo: Double, notOlderThan: Double) throws -> [ChatMessage] {
        try db.writer.read { conn in
            try ChatMessage.fetchAll(conn, sql: "SELECT * FROM chat_messages WHERE batch_id IS NULL AND ts <= ? AND ts >= ? ORDER BY ts",
                                     arguments: [upTo, notOlderThan])
        }
    }

    public static func markChats(_ conn: Database, ids: [Int64], batchId: Int64) throws {
        guard !ids.isEmpty else { return }
        let list = ids.map(String.init).joined(separator: ",")
        try conn.execute(sql: "UPDATE chat_messages SET batch_id = ? WHERE id IN (\(list))", arguments: [batchId])
    }

    public func chatMessage(id: Int64) throws -> ChatMessage? {
        try db.writer.read { conn in try ChatMessage.fetchOne(conn, key: id) }
    }

    public func chatCursor(path: String) throws -> Int64? {
        try db.writer.read { conn in try Int64.fetchOne(conn, sql: "SELECT offset FROM chat_cursors WHERE path = ?", arguments: [path]) }
    }

    public func setChatCursor(path: String, offset: Int64) throws {
        try db.writer.write { conn in
            try conn.execute(sql: "INSERT INTO chat_cursors(path, offset) VALUES (?, ?) ON CONFLICT(path) DO UPDATE SET offset = excluded.offset",
                             arguments: [path, offset])
        }
    }

    // MARK: 읽기

    public func unprocessed(limit: Int) throws -> [Observation] {
        try db.writer.read { conn in
            try Observation.fetchAll(conn, sql: "SELECT * FROM observations WHERE batch_id IS NULL ORDER BY ts ASC, id ASC LIMIT ?", arguments: [limit])
        }
    }

    public func oldestUnprocessedTs() throws -> Double? {
        try db.writer.read { conn in try Double.fetchOne(conn, sql: "SELECT MIN(ts) FROM observations WHERE batch_id IS NULL") }
    }

    public func texts(ids: [Int64]) throws -> [Int64: String] {
        guard !ids.isEmpty else { return [:] }
        let list = Set(ids).map(String.init).joined(separator: ",")
        return try db.writer.read { conn in
            var result: [Int64: String] = [:]
            for row in try Row.fetchAll(conn, sql: "SELECT id, text FROM text_snapshots WHERE id IN (\(list))") {
                result[row["id"]] = row["text"]
            }
            return result
        }
    }

    /// [from, to] 구간과 겹치는 유휴 구간.
    public func idleSpans(from: Double, to: Double) throws -> [IdleSpan] {
        try db.writer.read { conn in
            try IdleSpan.fetchAll(conn, sql: """
                SELECT * FROM idle_spans WHERE start_ts <= ? AND COALESCE(end_ts, ?) >= ? ORDER BY start_ts
                """, arguments: [to, to, from])
        }
    }

    public func recent(limit: Int) throws -> [Observation] {
        try db.writer.read { conn in
            try Observation.fetchAll(conn, sql: "SELECT * FROM observations ORDER BY ts DESC, id DESC LIMIT ?", arguments: [limit])
        }
    }

    public func recentBatches(limit: Int) throws -> [BatchRecord] {
        try db.writer.read { conn in
            try BatchRecord.fetchAll(conn, sql: "SELECT * FROM batches ORDER BY id DESC LIMIT ?", arguments: [limit])
        }
    }

    /// 목록 화면용: 프롬프트·응답 같은 큰 열은 빼고 읽는다 (배치당 수십 KB 라 주기적으로 읽으면 부담).
    public func recentBatchSummaries(limit: Int) throws -> [BatchRecord] {
        try db.writer.read { conn in
            try BatchRecord.fetchAll(conn, sql: """
                SELECT id, started_at, finished_at, from_obs, to_obs, row_count, status, model, prompt_tokens, completion_tokens, error,
                       NULL AS raw_response, stats, NULL AS system_prompt, NULL AS user_prompt, NULL AS llm_patch, NULL AS applied_patch
                FROM batches ORDER BY id DESC LIMIT ?
                """, arguments: [limit])
        }
    }

    public func batch(id: Int64) throws -> BatchRecord? {
        try db.writer.read { conn in try BatchRecord.fetchOne(conn, key: id) }
    }

    public func counts(since: Double) throws -> (total: Int, unprocessed: Int) {
        try db.writer.read { conn in
            let total = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM observations WHERE ts >= ?", arguments: [since]) ?? 0
            let pending = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM observations WHERE batch_id IS NULL") ?? 0
            return (total, pending)
        }
    }
}

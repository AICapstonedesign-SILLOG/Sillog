import Foundation
import GRDB

public struct ChatScope: Codable, Equatable, Sendable {
    public var projectID: String?
    public var conversationID: String?
    public var paths: [String] = []
    public var libraryIDs: [String] = []
    public var useActivity = true
    public var useWeb = false
    public var useGitHub = false
    public var plugins: [String] = []
    private enum CodingKeys: String, CodingKey { case paths, libraryIDs, useActivity, useWeb, useGitHub, plugins, projectID }

    /// Args: 없음.
    /// Returns: 활동 기록만 사용하는 기본 범위.
    /// Raises: 없음.
    public init() {}

    /// Args: decoder는 저장된 대화의 자료 설정이다.
    /// Returns: 기존 웹·GitHub 통합 설정을 유지하는 자료 범위.
    /// Raises: 저장된 값의 디코딩 오류.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        projectID = try values.decodeIfPresent(String.self, forKey: .projectID)
        paths = try values.decodeIfPresent([String].self, forKey: .paths) ?? []
        libraryIDs = try values.decodeIfPresent([String].self, forKey: .libraryIDs) ?? []
        useActivity = try values.decodeIfPresent(Bool.self, forKey: .useActivity) ?? true
        useWeb = try values.decodeIfPresent(Bool.self, forKey: .useWeb) ?? false
        useGitHub = try values.decodeIfPresent(Bool.self, forKey: .useGitHub) ?? useWeb
        plugins = try values.decodeIfPresent([String].self, forKey: .plugins) ?? []
    }
}

public struct ChatSource: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var location: String
    public var excerpt: String
}

public struct ChatArtifact: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID().uuidString
    public var title: String
    public var format: String
    public var content: String
    public init(title: String, format: String, content: String) {
        self.title = title; self.format = format; self.content = content
    }
}

public struct ChatAutomationProposal: Codable, Equatable, Sendable {
    public var title: String
    public var prompt: String
    public var intervalHours: Int
}

public struct ChatConversation: Codable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var title = "새 대화"
    public var skillID = "general"
    public var scope = ChatScope()
    public var projectID: String?
    public var updatedAt = Date().timeIntervalSince1970
    /// Args: 없음.
    /// Returns: 고유 ID를 가진 빈 대화.
    /// Raises: 없음.
    public init() {}
}

public struct ConversationMessage: Codable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var conversationID: String
    public var role: String
    public var text: String
    public var status = "complete"
    public var createdAt = Date().timeIntervalSince1970
    public var sources: [ChatSource] = []
    public var artifacts: [ChatArtifact] = []
    public var steps: [String] = []
    public var automation: ChatAutomationProposal?
    public var approvedAutomationID: String?

    /// Args: conversationID는 소속 대화, role·text·status는 메시지 내용과 상태이다.
    /// Returns: 저장 가능한 채팅 메시지.
    /// Raises: 없음.
    public init(conversationID: String, role: String, text: String, status: String = "complete") {
        self.conversationID = conversationID; self.role = role; self.text = text; self.status = status
    }
}

public struct ChatAutomation: Codable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var title: String
    public var prompt: String
    public var skillID: String
    public var scope: ChatScope
    public var intervalHours: Int
    public var nextRun: Double
    public var enabled = true
    public var lastStatus = "실행 대기"
    public var lastConversationID: String?

    /// Args: proposal은 승인된 예약안, conversation은 권한 범위, now는 등록 시각이다.
    /// Returns: 첫 실행 시각이 지정된 예약.
    /// Raises: 없음.
    public init(proposal: ChatAutomationProposal, conversation: ChatConversation, now: Double = Date().timeIntervalSince1970) {
        title = proposal.title; prompt = proposal.prompt; skillID = conversation.skillID
        scope = conversation.scope; scope.projectID = conversation.projectID; intervalHours = proposal.intervalHours
        nextRun = now + Double(intervalHours) * 3600
    }
}

public struct ChatStore: Sendable {
    let db: WGDatabase
    /// Args: db는 앱 데이터베이스이다.
    /// Returns: 채팅 전용 저장소.
    /// Raises: 없음.
    public init(_ db: WGDatabase) { self.db = db }

    /// Args: migrator는 기존 DB 마이그레이션 목록이다.
    /// Returns: 없음. 채팅 테이블과 검색 색인 생성 단계를 등록한다.
    /// Raises: 등록 시 없음. 적용 시 DB 오류를 전달한다.
    static func migrate(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v11-context-chat") { db in
            try db.execute(sql: """
                CREATE TABLE app_conversations (id TEXT PRIMARY KEY, updated_at REAL NOT NULL, payload TEXT NOT NULL);
                CREATE TABLE app_messages (
                  id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES app_conversations(id) ON DELETE CASCADE,
                  created_at REAL NOT NULL, payload TEXT NOT NULL
                );
                CREATE INDEX idx_app_messages_conversation ON app_messages(conversation_id, created_at);
                CREATE TABLE app_automations (id TEXT PRIMARY KEY, payload TEXT NOT NULL);
                """)
            // 기존 원문에도 검색 색인을 추가한다. 원문은 기존 테이블에만 보관한다.
            for (table, columns) in [("nodes", ["title", "key", "props"]), ("text_snapshots", ["text"]), ("chat_messages", ["text", "cwd"])] {
                let fields = columns.joined(separator: ", ")
                let newFields = columns.map { "new.\($0)" }.joined(separator: ", ")
                let oldFields = columns.map { "old.\($0)" }.joined(separator: ", ")
                let index = "\(table)_chat_fts"
                try db.execute(sql: """
                    CREATE VIRTUAL TABLE \(index) USING fts5(\(fields), content='\(table)', content_rowid='id', tokenize='trigram');
                    INSERT INTO \(index)(\(index)) VALUES ('rebuild');
                    CREATE TRIGGER \(index)_ai AFTER INSERT ON \(table) BEGIN
                      INSERT INTO \(index)(rowid, \(fields)) VALUES (new.id, \(newFields));
                    END;
                    CREATE TRIGGER \(index)_ad AFTER DELETE ON \(table) BEGIN
                      INSERT INTO \(index)(\(index), rowid, \(fields)) VALUES ('delete', old.id, \(oldFields));
                    END;
                    CREATE TRIGGER \(index)_au AFTER UPDATE ON \(table) BEGIN
                      INSERT INTO \(index)(\(index), rowid, \(fields)) VALUES ('delete', old.id, \(oldFields));
                      INSERT INTO \(index)(rowid, \(fields)) VALUES (new.id, \(newFields));
                    END;
                    """)
            }
        }
    }

    /// Args: 없음.
    /// Returns: 최신순 대화 목록.
    /// Raises: DB·디코딩 오류.
    public func conversations() throws -> [ChatConversation] {
        try db.writer.read { conn in
            try Row.fetchAll(conn, sql: "SELECT payload, project_id FROM app_conversations ORDER BY updated_at DESC")
                .map { row in
                    var conversation = try JSONDecoder().decode(ChatConversation.self, from: Data((row["payload"] as String).utf8))
                    conversation.projectID = row["project_id"]
                    return conversation
                }
        }
    }

    /// Args: 없음.
    /// Returns: 대화 목록에 표시할 마지막 메시지의 짧은 미리보기.
    /// Raises: DB 조회 오류.
    public func conversationPreviews() throws -> [String: String] {
        try db.writer.read { conn in
            let rows = try Row.fetchAll(conn, sql: """
                SELECT c.id, (
                    SELECT substr(json_extract(m.payload, '$.text'), 1, 240)
                    FROM app_messages m WHERE m.conversation_id = c.id
                      AND json_extract(m.payload, '$.text') != ''
                      AND json_extract(m.payload, '$.status') = 'complete'
                    ORDER BY m.created_at DESC, m.rowid DESC LIMIT 1
                ) AS preview FROM app_conversations c
                """)
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                (row["id"] as String, row["preview"] as String? ?? "")
            })
        }
    }

    /// Args: conversation은 저장할 대화 설정이다.
    /// Returns: 없음. 기존 ID가 있으면 갱신한다.
    /// Raises: 인코딩·DB 오류.
    public func save(_ conversation: ChatConversation) throws {
        let payload = String(decoding: try JSONEncoder().encode(conversation), as: UTF8.self)
        try db.writer.write { conn in
            try conn.execute(sql: "INSERT INTO app_conversations (id, updated_at, payload, project_id) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, payload = excluded.payload",
                             arguments: [conversation.id, conversation.updatedAt, payload, conversation.projectID])
        }
    }

    /// Args: conversationID는 삭제할 대화 ID이다.
    /// Returns: 없음. 메시지·결과물을 함께 삭제하고 예약의 결과 링크만 해제한다.
    /// Raises: DB 쓰기 오류. 승인된 예약과 원본 활동 기록은 유지한다.
    public func deleteConversation(_ conversationID: String) throws {
        try db.writer.write { conn in
            try conn.execute(sql: "DELETE FROM app_conversations WHERE id = ?", arguments: [conversationID])
            try ProjectStore.removeFromProposals("conversation:\(conversationID)", conn)
            try conn.execute(sql: "UPDATE app_automations SET payload = json_remove(payload, '$.lastConversationID') WHERE json_extract(payload, '$.lastConversationID') = ?", arguments: [conversationID])
        }
    }

    /// Args: conversationID는 대화 ID, title은 새 이름이다.
    /// Returns: 없음. 자료 범위나 대화 순서는 바꾸지 않고 이름만 저장한다.
    /// Raises: DB 쓰기 오류.
    public func renameConversation(_ conversationID: String, title: String) throws {
        try db.writer.write { conn in
            try conn.execute(sql: "UPDATE app_conversations SET payload = json_set(payload, '$.title', ?) WHERE id = ?", arguments: [title, conversationID])
        }
    }

    /// Args: conversationID는 읽을 대화 ID이다.
    /// Returns: 작성 순서의 대화 메시지.
    /// Raises: DB·디코딩 오류.
    public func messages(_ conversationID: String) throws -> [ConversationMessage] {
        try db.writer.read { conn in
            try String.fetchAll(conn, sql: "SELECT payload FROM app_messages WHERE conversation_id = ? ORDER BY created_at, rowid", arguments: [conversationID])
                .map { try JSONDecoder().decode(ConversationMessage.self, from: Data($0.utf8)) }
        }
    }

    /// Args: message는 저장할 요청·응답·진행 기록이다.
    /// Returns: 없음. 기존 ID가 있으면 갱신한다.
    /// Raises: 인코딩·DB 오류.
    public func save(_ message: ConversationMessage) throws {
        let payload = String(decoding: try JSONEncoder().encode(message), as: UTF8.self)
        try db.writer.write { conn in
            try conn.execute(sql: "INSERT INTO app_messages VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload",
                             arguments: [message.id, message.conversationID, message.createdAt, payload])
        }
    }

    /// Args: 없음.
    /// Returns: 등록된 예약 목록.
    /// Raises: DB·디코딩 오류.
    public func automations() throws -> [ChatAutomation] {
        try db.writer.read { conn in
            try String.fetchAll(conn, sql: "SELECT payload FROM app_automations ORDER BY rowid DESC")
                .map { try JSONDecoder().decode(ChatAutomation.self, from: Data($0.utf8)) }
        }
    }

    /// Args: automation은 저장할 예약과 실행 상태이다.
    /// Returns: 없음. 기존 ID가 있으면 갱신한다.
    /// Raises: 인코딩·DB 오류.
    public func save(_ automation: ChatAutomation) throws {
        let payload = String(decoding: try JSONEncoder().encode(automation), as: UTF8.self)
        try db.writer.write { conn in
            try conn.execute(sql: "INSERT INTO app_automations VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", arguments: [automation.id, payload])
        }
    }

    /// Args: id는 삭제할 예약 ID이다.
    /// Returns: 없음. 원래 대화와 실행 결과는 보존하고 승인 표시만 해제한다.
    /// Raises: DB 쓰기 오류.
    public func deleteAutomation(_ id: String) throws {
        try db.writer.write { conn in
            try conn.execute(sql: "DELETE FROM app_automations WHERE id = ?", arguments: [id])
            try conn.execute(sql: "UPDATE app_messages SET payload = json_remove(payload, '$.approvedAutomationID') WHERE json_extract(payload, '$.approvedAutomationID') = ?", arguments: [id])
        }
    }

    /// Args: 없음.
    /// Returns: 없음. 이전 실행이 종료된 작업을 중단 상태로 표시한다.
    /// Raises: DB 읽기·쓰기 오류.
    public func recoverInterruptedRuns() throws {
        try db.writer.write { conn in
            try conn.execute(sql: """
                UPDATE app_messages SET payload = json_set(payload, '$.status', 'interrupted')
                WHERE json_extract(payload, '$.status') = 'running'
                """)
        }
        for var job in try automations() where job.lastStatus == "실행 중" {
            job.lastStatus = "앱 종료로 중단됨"; try save(job)
        }
    }

    /// Args: conversation은 대화, user·answer는 새 요청과 응답 자리이다.
    /// Returns: 없음. 한 요청을 이루는 세 레코드를 함께 저장한다.
    /// Raises: 인코딩·DB 오류. 실패하면 모두 반영하지 않는다.
    public func startTurn(conversation: ChatConversation, user: ConversationMessage, answer: ConversationMessage) throws {
        let encoder = JSONEncoder()
        let payload = String(decoding: try encoder.encode(conversation), as: UTF8.self)
        let records = try [user, answer].map { ($0, String(decoding: try encoder.encode($0), as: UTF8.self)) }
        try db.writer.write { conn in
            try conn.execute(sql: "INSERT INTO app_conversations (id, updated_at, payload, project_id) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, payload = excluded.payload", arguments: [conversation.id, conversation.updatedAt, payload, conversation.projectID])
            for (message, json) in records {
                try conn.execute(sql: "INSERT INTO app_messages VALUES (?, ?, ?, ?)", arguments: [message.id, message.conversationID, message.createdAt, json])
            }
        }
    }

    /// Args: automation은 승인한 예약, message는 승인 상태를 반영한 답변이다.
    /// Returns: 없음. 예약과 답변의 승인 상태를 함께 저장한다.
    /// Raises: 인코딩·DB 오류.
    public func approve(_ automation: ChatAutomation, message: ConversationMessage) throws {
        let job = String(decoding: try JSONEncoder().encode(automation), as: UTF8.self)
        let answer = String(decoding: try JSONEncoder().encode(message), as: UTF8.self)
        try db.writer.write { conn in
            try conn.execute(sql: "INSERT INTO app_automations VALUES (?, ?)", arguments: [automation.id, job])
            try conn.execute(sql: "UPDATE app_messages SET payload = ? WHERE id = ?", arguments: [answer, message.id])
        }
    }
}

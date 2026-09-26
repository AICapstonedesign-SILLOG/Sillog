import XCTest
@testable import WorkGraphCore

final class ChatTests: XCTestCase {
    /// Args: 없음.
    /// Returns: 없음. 이름 변경 저장과 대상 대화의 메시지 삭제를 확인한다.
    /// Raises: 테스트 DB 오류.
    func testRenameAndDeleteConversation() throws {
        let store = ChatStore(try .inMemory()), conversation = ChatConversation(), other = ChatConversation()
        try store.startTurn(conversation: conversation,
                            user: .init(conversationID: conversation.id, role: "user", text: "요청"),
                            answer: .init(conversationID: conversation.id, role: "assistant", text: "결과"))
        try store.save(other)
        try store.renameConversation(conversation.id, title: "바꾼 이름")
        XCTAssertEqual(try store.conversations().first(where: { $0.id == conversation.id })?.title, "바꾼 이름")
        try store.deleteConversation(conversation.id)
        XCTAssertTrue(try store.messages(conversation.id).isEmpty)
        XCTAssertEqual(try store.conversations().map(\.id), [other.id])
    }

    /// Args: 없음.
    /// Returns: 없음. 중단된 응답 복구와 외부 도구 대화와의 저장 분리를 확인한다.
    /// Raises: 테스트 DB 오류.
    func testConversationPersistenceAndRecovery() throws {
        let db = try WGDatabase.inMemory(), store = ChatStore(db), conversation = ChatConversation()
        let user = ConversationMessage(conversationID: conversation.id, role: "user", text: "요청")
        let answer = ConversationMessage(conversationID: conversation.id, role: "assistant", text: "일부 응답", status: "running")
        try store.startTurn(conversation: conversation, user: user, answer: answer)
        try store.recoverInterruptedRuns()
        XCTAssertEqual(try store.messages(conversation.id).map(\.status), ["complete", "interrupted"])
        XCTAssertEqual(try EventStore(db).chatMessages(from: 0, to: Date().timeIntervalSince1970).count, 0)
    }

    /// Args: 없음.
    /// Returns: 없음. 짧은 한국어·FTS 검색·연결 노드 조회를 확인한다.
    /// Raises: 테스트 DB 오류.
    func testContextSearchAndGraphExpansion() throws {
        let db = try WGDatabase.inMemory()
        let node = try db.writer.write { conn in
            let tx = GraphTx(conn)
            let task = try tx.upsertNode(label: "Task", key: "test-task", subtype: nil, title: "문서 검색 구현", props: [:], at: 10)
            let project = try tx.upsertNode(label: "Project", key: "test-project", subtype: nil, title: "설계 자료", props: [:], at: 10)
            _ = try tx.upsertEdge(src: task, dst: project, type: "ON", props: [:], addWeight: 0, at: 10)
            return task
        }
        let search = ContextSearch(db)
        XCTAssertFalse(try search.search(query: "문서").isEmpty)
        XCTAssertFalse(try search.search(query: "문서 검색 구현").isEmpty)
        XCTAssertFalse(try search.search(query: "test-task").isEmpty)
        XCTAssertEqual(try search.read("node:\(node)").count, 2)
        XCTAssertTrue(try search.search(query: "\" OR *").isEmpty)
    }

    /// Args: 없음.
    /// Returns: 없음. 연결 범위 밖·심볼릭 링크·인증 파일 접근 차단을 확인한다.
    /// Raises: 임시 파일·DB 오류.
    func testFileScope() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("outside"), withDestinationURL: directory.deletingLastPathComponent())
        var scope = ChatScope(); scope.paths = [directory.path]
        let tools = ChatTools(db: try .inMemory(), scope: scope)
        XCTAssertNoThrow(try tools.allowedURL(directory.appendingPathComponent("Sources/App.swift").path))
        XCTAssertThrowsError(try tools.allowedURL(directory.appendingPathComponent(".env").path))
        XCTAssertThrowsError(try tools.allowedURL(directory.appendingPathComponent("outside/secret.txt").path))
        XCTAssertThrowsError(try tools.allowedURL(directory.path + "-other/file.txt"))
    }

    /// Args: 없음.
    /// Returns: 이전 통합 외부 조회 설정을 보존하고 웹·GitHub 도구가 독립적으로 노출되는지 확인한다.
    /// Raises: JSON·테스트 DB 오류.
    func testSeparateExternalSources() throws {
        let saved = Data(#"{"paths":[],"useActivity":true,"useWeb":true}"#.utf8)
        let migrated = try JSONDecoder().decode(ChatScope.self, from: saved)
        XCTAssertTrue(migrated.useWeb)
        XCTAssertTrue(migrated.useGitHub)

        var scope = ChatScope()
        scope.useGitHub = true
        let github = ChatTools(db: try .inMemory(), scope: scope, searchKey: "search-key", searchModel: "test-model")
        XCTAssertTrue(github.specs.contains { $0.name == "github_read" })
        XCTAssertFalse(github.specs.contains { $0.name == "web_search" })

        scope.useGitHub = false
        scope.useWeb = true
        let web = ChatTools(db: try .inMemory(), scope: scope, searchKey: "search-key", searchModel: "test-model")
        XCTAssertTrue(web.specs.contains { $0.name == "web_search" })
        XCTAssertFalse(web.specs.contains { $0.name == "github_read" })

        scope.plugins = ["gmail", "drive", "notion"]
        let plugins = ChatTools(db: try .inMemory(), scope: scope)
        XCTAssertTrue(plugins.specs.contains { $0.name == "gmail_search" })
        XCTAssertTrue(plugins.specs.contains { $0.name == "drive_read" })
        XCTAssertTrue(plugins.specs.contains { $0.name == "notion_search" })
    }

    /// Args: 없음.
    /// Returns: 없음. 미완료 도구 호출은 실행 가능한 응답으로 반환되지 않음을 확인한다.
    /// Raises: JSON 해석 오류.
    func testStreamRequiresCompletion() throws {
        var parser = ChatStreamParser(format: .completions)
        _ = try parser.accept(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"read_file","arguments":"{\"path\":"}}]},"finish_reason":null}]}"#)
        XCTAssertThrowsError(try parser.result())
        _ = try parser.accept(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"a\"}"}}]},"finish_reason":"tool_calls"}]}"#)
        XCTAssertEqual(try parser.result().calls.first?.arguments, #"{"path":"a"}"#)
        var responses = ChatStreamParser(format: .responses)
        _ = try responses.accept(#"{"type":"response.completed","response":{"status":"completed","output":[{"type":"reasoning","encrypted_content":"opaque"},{"type":"function_call","call_id":"c1","name":"read_file","arguments":"{}"}]}}"#)
        XCTAssertEqual(try responses.result().responseItems.count, 2)
    }

    /// Args: 없음.
    /// Returns: 없음. 마지막 output이 비어 있어도 완료 항목의 도구·reasoning을 보존한다.
    /// Raises: SSE 해석 오류.
    func testResponsesKeepsCompletedItemsWhenFinalOutputIsEmpty() throws {
        var parser = ChatStreamParser(format: .responses)
        _ = try parser.accept(#"{"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"r1","encrypted_content":"opaque"}}"#)
        _ = try parser.accept(#"{"type":"response.output_item.done","output_index":1,"item":{"type":"function_call","id":"f1","call_id":"c1","name":"search_context","arguments":"{}","status":"completed"}}"#)
        XCTAssertThrowsError(try parser.result())
        _ = try parser.accept(#"{"type":"response.completed","response":{"status":"completed","output":[]}}"#)
        XCTAssertEqual(try parser.result().calls.first?.name, "search_context")
        XCTAssertEqual(try parser.result().responseItems.count, 2)
        var text = ChatStreamParser(format: .responses)
        _ = try text.accept(#"{"type":"response.output_item.done","output_index":0,"item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"완료"}]}}"#)
        _ = try text.accept(#"{"type":"response.completed","response":{"status":"completed","output":[]}}"#)
        XCTAssertEqual(try text.result().text, "완료")
    }

    /// Args: 없음.
    /// Returns: 없음. 네트워크 스트림의 빈 줄 구분과 실제 본문 콜백을 확인한다.
    /// Raises: 모의 HTTP·스트림 오류.
    func testNetworkStreamAndToolHistory() async throws {
        StubURLProtocol.reset([.init(status: 200, body: """
            data: {"choices":[{"delta":{"content":"안녕"},"finish_reason":null}]}

            data: {"choices":[{"delta":{"content":"하세요"},"finish_reason":"stop"}]}


            """)])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let client = OpenAICompatClient(baseURL: URL(string: "https://example.invalid/v1")!, model: "test", session: URLSession(configuration: config))
        let reply = try await client.respond(system: "test", messages: [
            .init(role: "user", text: "질문"),
            .init(role: "assistant", text: "", calls: [.init(id: "c1", name: "read_file", arguments: "{}")]),
            .init(role: "tool", text: "결과", callID: "c1"),
        ], tools: []) { _ in }
        XCTAssertEqual(reply.text, "안녕하세요")
        let sent = StubURLProtocol.requests.first?.body["messages"] as? [[String: Any]]
        XCTAssertEqual(sent?.last?["tool_call_id"] as? String, "c1")
    }

    /// Args: 없음.
    /// Returns: 없음. 예약 승인 저장과 문서 출력의 스크립트 차단을 확인한다.
    /// Raises: 테스트 DB 오류.
    func testAutomationApprovalAndArtifactHTML() throws {
        let store = ChatStore(try .inMemory()), conversation = ChatConversation()
        let user = ConversationMessage(conversationID: conversation.id, role: "user", text: "반복 요청")
        var answer = ConversationMessage(conversationID: conversation.id, role: "assistant", text: "예약안")
        let proposal = ChatAutomationProposal(title: "보고서", prompt: "지난 하루를 요약", intervalHours: 24)
        answer.automation = proposal
        try store.startTurn(conversation: conversation, user: user, answer: answer)
        XCTAssertTrue(try store.automations().isEmpty)
        let job = ChatAutomation(proposal: proposal, conversation: conversation, now: 0)
        answer.approvedAutomationID = job.id
        try store.approve(job, message: answer)
        XCTAssertEqual(try store.automations().first?.nextRun, 86400)
        XCTAssertEqual(try store.messages(conversation.id).last?.approvedAutomationID, job.id)
        try store.deleteAutomation(job.id)
        XCTAssertTrue(try store.automations().isEmpty)
        XCTAssertNil(try store.messages(conversation.id).last?.approvedAutomationID)
        XCTAssertEqual(try store.conversations().first?.id, conversation.id)
        let html = ChatArtifactHTML.render(.init(title: "문서", format: "html", content: "<script>alert(1)</script><meta http-equiv='refresh' content='0;url=https://example.invalid'><h1>결과</h1>"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("http-equiv='refresh'"))
        XCTAssertTrue(html.contains("script-src 'none'"))
        let csv = ChatArtifactHTML.render(.init(title: "표", format: "csv", content: "항목,값\nA,<B>"))
        XCTAssertTrue(csv.contains("<pre>항목,값\nA,&lt;B&gt;</pre>"))
        let json = ChatArtifactHTML.render(.init(title: "데이터", format: "json", content: #"{"value":"<B>"}"#))
        XCTAssertTrue(json.contains(#"{"value":"&lt;B&gt;"}"#))
    }

    /// Args: 없음.
    /// Returns: Markdown 표와 일반 문장을 구별하고 셀 내용을 보존한다.
    /// Raises: 없음.
    func testMarkdownTable() {
        XCTAssertEqual(ChatMarkdownTable.rows(in: "| 논문 | 결과 |\n|---|---|\n| A | 성공 |"), [["논문", "결과"], ["A", "성공"]])
        XCTAssertNil(ChatMarkdownTable.rows(in: "논문 | 결과\nA | 성공"))
        XCTAssertNil(ChatMarkdownTable.rows(in: "| 논문 | 결과 |\n|---|---|\n| A |"))
    }

    /// Args: 없음.
    /// Returns: 없음. 여섯 스킬과 실제 하위 작업·도구 결과 전달을 확인한다.
    /// Raises: 실행기·DB 오류.
    func testSkillsAndDelegation() async throws {
        XCTAssertEqual(Set(try ChatSkill.load().map(\.id)), ["writing", "research", "planning", "learning", "content", "automation"])
        let model = ScriptedChatModel()
        let runner = ChatRunner(client: model, tools: ChatTools(db: try .inMemory(), scope: .init()))
        let result = try await runner.run(history: [.init(conversationID: "test", role: "user", text: "문서를 작성해줘")], skillID: "writing") { _ in }
        XCTAssertEqual(result.text, "완료")
        XCTAssertEqual(result.artifacts.first?.content, "# 결과")
        let calls = await model.requests
        XCTAssertTrue(calls.contains { $0.contains("하위 작업") })
    }
}

private actor ScriptedChatModel: ChatModelClient {
    var requests: [String] = []
    /// Args: system·messages·tools는 실행기의 요청, onText는 사용하지 않는 모의 콜백이다.
    /// Returns: 위임 → 실제 기록 검색 → 결과물 생성 순서의 모의 응답.
    /// Raises: 없음.
    func respond(system: String, messages: [ChatModelMessage], tools: [ToolSpec], onText: @escaping @Sendable (String) async -> Void) async throws -> ChatModelReply {
        requests.append(messages.first?.text ?? "")
        if messages.first?.text == "하위 작업" {
            if messages.last?.role == "tool" { return .init(text: "조회 결과 없음") }
            return .init(text: "", calls: [.init(id: "search", name: "search_context", arguments: #"{"query":"","from":"","to":""}"#)])
        }
        if messages.contains(where: { $0.calls.contains { $0.name == "create_artifact" } }) { return .init(text: "완료") }
        if messages.last?.role == "tool" { return .init(text: "", calls: [.init(id: "artifact", name: "create_artifact", arguments: ##"{"title":"결과","format":"markdown","content":"# 결과"}"##)]) }
        return .init(text: "", calls: [.init(id: "delegate", name: "delegate", arguments: #"{"tasks":[{"role":"context","task":"하위 작업"}]}"#)])
    }
}

import XCTest
@testable import WorkGraphCore

final class StubCredentials: CodexCredentialProviding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var rejected: [String] = []
    var failWith: CodexAuthError?

    func credentials() async throws -> CodexCredentials {
        if let failWith { throw failWith }
        return CodexCredentials(accessToken: "token_old", accountId: "acct_123")
    }

    func refreshAfterRejection(of accessToken: String) async throws -> CodexCredentials {
        lock.withLock { rejected.append(accessToken) }
        return CodexCredentials(accessToken: "token_new", accountId: "acct_123")
    }
}

final class CodexResponsesClientTests: XCTestCase {
    private let tool = ToolSpec(name: "record_activity", description: "기록", parameters: .object(["type": "object"]))

    private func makeClient(_ credentials: StubCredentials = StubCredentials()) -> CodexResponsesClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return CodexResponsesClient(auth: credentials, model: "gpt-5.4-mini", session: URLSession(configuration: config))
    }

    private func sse(_ events: [String]) -> String { events.map { "event: x\ndata: \($0)\n" }.joined(separator: "\n") + "\ndata: [DONE]\n" }

    private let completed = #"{"type":"response.completed","response":{"model":"gpt-5.4-mini-2026","usage":{"input_tokens":321,"output_tokens":45}}}"#

    func testSendsCodexRequestAndReadsFunctionCallArguments() async throws {
        StubURLProtocol.reset([.init(status: 200, body: sse([
            #"{"type":"response.output_item.added","item":{"id":"fc_1","type":"function_call","name":"record_activity","arguments":""}}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"fc_1","delta":"{\"segm"}"#,
            #"{"type":"response.output_item.done","item":{"id":"fc_1","type":"function_call","name":"record_activity","arguments":"{\"segments\":[]}"}}"#,
            completed,
        ]))])
        let result = try await makeClient().callFunction(system: "시스템 지시", user: "행 목록", tool: tool)
        XCTAssertEqual(String(data: result.arguments, encoding: .utf8), #"{"segments":[]}"#)
        XCTAssertEqual(result.promptTokens, 321)
        XCTAssertEqual(result.completionTokens, 45)
        XCTAssertEqual(result.model, "gpt-5.4-mini-2026")

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://chatgpt.com/backend-api/codex/responses")
        XCTAssertEqual(request.headers["Authorization"], "Bearer token_old")
        XCTAssertEqual(request.headers["chatgpt-account-id"], "acct_123")
        XCTAssertEqual(request.headers["Accept"], "text/event-stream")
        XCTAssertEqual(request.body["model"] as? String, "gpt-5.4-mini")
        XCTAssertEqual(request.body["instructions"] as? String, "시스템 지시")
        XCTAssertEqual(request.body["stream"] as? Bool, true)
        XCTAssertEqual(request.body["store"] as? Bool, false)
        let input = try XCTUnwrap(request.body["input"] as? [[String: Any]])
        XCTAssertEqual(input.first?["role"] as? String, "user")
        XCTAssertEqual(((input.first?["content"] as? [[String: Any]])?.first)?["text"] as? String, "행 목록")
        let tools = try XCTUnwrap(request.body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["name"] as? String, "record_activity")        // Responses API 는 function 을 중첩하지 않는다
        XCTAssertEqual(tools.first?["type"] as? String, "function")
        XCTAssertEqual((request.body["tool_choice"] as? [String: Any])?["name"] as? String, "record_activity")
    }

    func testFallsBackToArgumentDeltasAndToOutputText() async throws {
        StubURLProtocol.reset([.init(status: 200, body: sse([
            #"{"type":"response.function_call_arguments.delta","item_id":"fc_1","delta":"{\"segments\":"}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"fc_1","delta":"[1]}"}"#,
            completed,
        ]))])
        let fromDeltas = try await makeClient().callFunction(system: "s", user: "u", tool: tool)
        XCTAssertEqual(String(data: fromDeltas.arguments, encoding: .utf8), #"{"segments":[1]}"#)

        StubURLProtocol.reset([.init(status: 200, body: sse([
            #"{"type":"response.output_text.delta","delta":"결과: {\"segments\""}"#,
            #"{"type":"response.output_text.delta","delta":":[2]} 끝"}"#,
            completed,
        ]))])
        let fromText = try await makeClient().callFunction(system: "s", user: "u", tool: tool)
        XCTAssertEqual(String(data: fromText.arguments, encoding: .utf8), #"{"segments":[2]}"#)
    }

    func testRefreshesOnceAfter401AndRetries() async throws {
        StubURLProtocol.reset([
            .init(status: 401, body: #"{"error":{"message":"token expired"}}"#),
            .init(status: 200, body: sse([#"{"type":"response.output_item.done","item":{"type":"function_call","arguments":"{\"ok\":true}"}}"#, completed])),
        ])
        let credentials = StubCredentials()
        let result = try await makeClient(credentials).callFunction(system: "s", user: "u", tool: tool)
        XCTAssertEqual(String(data: result.arguments, encoding: .utf8), #"{"ok":true}"#)
        XCTAssertEqual(credentials.rejected, ["token_old"])
        XCTAssertEqual(StubURLProtocol.requests.map { $0.headers["Authorization"] }, ["Bearer token_old", "Bearer token_new"])
    }

    func testSecond401IsReportedInsteadOfLooping() async {
        StubURLProtocol.reset([.init(status: 401, body: "{}"), .init(status: 401, body: #"{"detail":"nope"}"#)])
        do { _ = try await makeClient().callFunction(system: "s", user: "u", tool: tool); XCTFail("에러가 나야 함") }
        catch let error as LLMError {
            guard case .http(401, _) = error else { return XCTFail("\(error)") }
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func testRetriesWithAutoToolChoiceWhenForcedChoiceIsRejected() async throws {
        StubURLProtocol.reset([
            .init(status: 400, body: #"{"detail":"Unsupported value for tool_choice"}"#),
            .init(status: 200, body: sse([#"{"type":"response.output_item.done","item":{"type":"function_call","arguments":"{\"ok\":1}"}}"#, completed])),
        ])
        _ = try await makeClient().callFunction(system: "s", user: "u", tool: tool)
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        XCTAssertEqual(StubURLProtocol.requests[1].body["tool_choice"] as? String, "auto")
    }

    func testListsOnlyVisibleModelsInServerPriorityOrder() async throws {
        StubURLProtocol.reset([.init(status: 200, body: #"""
        {"models":[{"slug":"gpt-5.6-luna","display_name":"GPT-5.6-Luna","default_reasoning_level":"medium","visibility":"list","priority":8},
                   {"slug":"gpt-reserve","display_name":"GPT-Reserve","visibility":"hide","priority":3},
                   {"slug":"gpt-6-astra","display_name":"GPT-6-Astra","default_reasoning_level":"low","visibility":"list","priority":1}]}
        """#)])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let models = try await CodexResponsesClient.listModels(auth: StubCredentials(), session: URLSession(configuration: config))
        XCTAssertEqual(models.map(\.slug), ["gpt-6-astra", "gpt-5.6-luna"])
        XCTAssertEqual(models.last?.displayName, "GPT-5.6-Luna")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertTrue(request.url.absoluteString.hasPrefix("https://chatgpt.com/backend-api/codex/models?client_version="))
        XCTAssertEqual(request.headers["Authorization"], "Bearer token_old")
    }

    func testReadsUsageWindows() async throws {
        StubURLProtocol.reset([.init(status: 200, body: #"""
        {"plan_type":"plus","rate_limit":{"allowed":true,
          "primary_window":{"used_percent":12,"limit_window_seconds":18000,"reset_after_seconds":600,"reset_at":1790000000},
          "secondary_window":{"used_percent":4,"limit_window_seconds":604800,"reset_after_seconds":9000,"reset_at":1790500000}},
         "credits":null}
        """#)])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let usage = try await CodexResponsesClient.fetchUsage(auth: StubCredentials(), session: URLSession(configuration: config))
        XCTAssertEqual(usage.planType, "plus")
        XCTAssertEqual(usage.primary, CodexUsage.Window(usedPercent: 12, windowSeconds: 18000, resetAt: 1_790_000_000))
        XCTAssertEqual(usage.primary?.label, "5시간")
        XCTAssertEqual(usage.secondary?.label, "7일")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(request.headers["ChatGPT-Account-Id"], "acct_123")
    }

    func testBackendFailureAndLoginProblemsAreReadable() async {
        StubURLProtocol.reset([.init(status: 200, body: sse([#"{"type":"response.failed","response":{"error":{"message":"model overloaded"}}}"#]))])
        do { _ = try await makeClient().callFunction(system: "s", user: "u", tool: tool); XCTFail("에러가 나야 함") }
        catch { XCTAssertEqual(error as? LLMError, .backend("model overloaded")) }

        let credentials = StubCredentials()
        credentials.failWith = .notLoggedIn
        do { _ = try await makeClient(credentials).callFunction(system: "s", user: "u", tool: tool); XCTFail("에러가 나야 함") }
        catch { XCTAssertEqual(error as? LLMError, .auth(CodexAuthError.notLoggedIn.description)) }
    }
}

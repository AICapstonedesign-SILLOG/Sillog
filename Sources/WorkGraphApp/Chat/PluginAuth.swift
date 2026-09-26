import AppKit
import CryptoKit
import Darwin
import Foundation
import Security
import WorkGraphCore

struct PluginToken: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Double?
}

enum PluginAuth {
    static let callback = "http://127.0.0.1:8765/callback"

    /// Args: id는 연결할 플러그인 ID이다.
    /// Returns: 이 빌드에 해당 서비스의 OAuth 앱 정보가 준비되어 있으면 true.
    /// Raises: Keychain 접근 오류.
    static func isAvailable(_ id: String) throws -> Bool {
        switch id {
        case "gmail", "drive": return try !configuration("google-client", environment: "WORKGRAPH_GOOGLE_CLIENT_ID").isEmpty
        case "github": return try !configuration("github-client", environment: "WORKGRAPH_GITHUB_CLIENT_ID").isEmpty
        case "notion":
            return try !configuration("notion-client", environment: "WORKGRAPH_NOTION_CLIENT_ID").isEmpty &&
                !configuration("notion-secret", environment: "WORKGRAPH_NOTION_CLIENT_SECRET").isEmpty
        default: return false
        }
    }

    /// Args: key는 이전 Keychain 설정 이름, environment는 배포 환경 변수 이름이다.
    /// Returns: 앱 제공자가 설정한 OAuth 앱 정보. 이전 빌드에서 저장한 값도 읽는다.
    /// Raises: Keychain 접근 오류.
    static func configuration(_ key: String, environment: String) throws -> String {
        if let value = ProcessInfo.processInfo.environment[environment], !value.isEmpty { return value }
        if let value = Bundle.main.object(forInfoDictionaryKey: environment) as? String, !value.isEmpty { return value }
        return try ChatSecrets.load("plugin-\(key)")
    }

    /// Args: id는 gmail·drive·github·notion 중 하나이다.
    /// Returns: Keychain에 연결된 계정이 있으면 true.
    /// Raises: Keychain 접근 오류.
    static func isConnected(_ id: String) throws -> Bool { try !ChatSecrets.load("plugin-\(id)").isEmpty }

    /// Args: id는 연결한 플러그인 이름이다.
    /// Returns: 유효한 OAuth 액세스 토큰.
    /// Raises: 미연결·갱신·Keychain·네트워크 오류.
    static func accessToken(_ id: String) async throws -> String {
        let saved = try ChatSecrets.load("plugin-\(id)")
        guard let data = saved.data(using: .utf8), var token = try? JSONDecoder().decode(PluginToken.self, from: data) else {
            throw ChatToolError.unavailable("채팅의 플러그인에서 \(id)을 연결하세요.")
        }
        if let expiresAt = token.expiresAt, expiresAt < Date().timeIntervalSince1970 + 60 {
            guard let refresh = token.refreshToken else { throw ChatToolError.unavailable("\(id) 플러그인을 다시 연결하세요.") }
            let body: [String: String]
            let url: URL
            if id == "gmail" || id == "drive" {
                url = URL(string: "https://oauth2.googleapis.com/token")!
                body = ["client_id": try configuration("google-client", environment: "WORKGRAPH_GOOGLE_CLIENT_ID"), "refresh_token": refresh, "grant_type": "refresh_token"]
            } else if id == "github" {
                url = URL(string: "https://github.com/login/oauth/access_token")!
                let secret = try configuration("github-secret", environment: "WORKGRAPH_GITHUB_CLIENT_SECRET")
                guard !secret.isEmpty else { throw ChatToolError.unavailable("GitHub 연결이 만료되었습니다. 플러그인에서 다시 연결하세요.") }
                body = ["client_id": try configuration("github-client", environment: "WORKGRAPH_GITHUB_CLIENT_ID"),
                        "client_secret": secret,
                        "refresh_token": refresh, "grant_type": "refresh_token"]
            } else {
                url = URL(string: "https://api.notion.com/v1/oauth/token")!
                body = ["grant_type": "refresh_token", "refresh_token": refresh]
            }
            var request = id == "notion" ? jsonRequest(url, body) : formRequest(url, body)
            if id == "notion" { request.setValue(try notionBasicAuth(), forHTTPHeaderField: "Authorization") }
            token = try await exchange(request, oldRefresh: refresh)
            try save(token, id: id)
        }
        return token.accessToken
    }

    /// Args: id는 연결 해제할 플러그인이다.
    /// Returns: 없음. 로컬 OAuth 토큰만 제거한다.
    /// Raises: Keychain 오류.
    static func disconnect(_ id: String) throws { try ChatSecrets.save("", account: "plugin-\(id)") }

    /// Args: ids는 사용자가 설치할 Google 플러그인 ID 목록, clientID는 데스크톱 OAuth 클라이언트 ID이다.
    /// Returns: 없음. 한 번의 브라우저 승인으로 선택한 플러그인의 토큰을 저장한다.
    /// Raises: OAuth 거절·콜백·토큰 교환 오류.
    static func connectGoogle(_ ids: Set<String>, clientID: String) async throws {
        let scopes = ids.sorted().map { $0 == "gmail" ? "https://www.googleapis.com/auth/gmail.readonly" : "https://www.googleapis.com/auth/drive.readonly" }
        let verifier = randomURLSafe(32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        let state = randomURLSafe(16)
        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = ["client_id": clientID, "redirect_uri": callback, "response_type": "code", "scope": scopes.joined(separator: " "),
                           "code_challenge": challenge, "code_challenge_method": "S256", "state": state,
                           "access_type": "offline", "prompt": "consent"].map { URLQueryItem(name: $0.key, value: $0.value) }
        let code = try await LoopbackOAuth.receive(auth: auth.url!, state: state)
        let request = formRequest(URL(string: "https://oauth2.googleapis.com/token")!,
                                  ["client_id": clientID, "code": code, "code_verifier": verifier,
                                   "redirect_uri": callback, "grant_type": "authorization_code"])
        let token = try await exchange(request)
        for id in ids { try save(token, id: id) }
    }

    /// Args: clientID·clientSecret은 사용자가 등록한 Notion 공개 통합 정보이다.
    /// Returns: 없음. 브라우저 승인을 완료한 토큰을 Keychain에 저장한다.
    /// Raises: OAuth 거절·콜백·토큰 교환 오류.
    static func connectNotion(clientID: String, clientSecret: String) async throws {
        let state = randomURLSafe(16)
        var auth = URLComponents(string: "https://api.notion.com/v1/oauth/authorize")!
        auth.queryItems = ["client_id": clientID, "redirect_uri": callback, "response_type": "code", "owner": "user", "state": state]
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        let code = try await LoopbackOAuth.receive(auth: auth.url!, state: state)
        var request = jsonRequest(URL(string: "https://api.notion.com/v1/oauth/token")!,
                                  ["grant_type": "authorization_code", "code": code, "redirect_uri": callback])
        request.setValue("Basic " + Data("\(clientID):\(clientSecret)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        try save(await exchange(request), id: "notion")
    }

    /// Args: clientID는 읽기 권한을 등록하고 디바이스 흐름을 켠 GitHub App의 ID, onCode는 승인 코드 표시 함수이다.
    /// Returns: 없음. 사용자가 브라우저에서 승인하면 토큰을 저장한다.
    /// Raises: 승인 거절·기한 초과·네트워크 오류.
    static func connectGitHub(clientID: String, onCode: @escaping @MainActor (String) -> Void) async throws {
        let deviceRequest = formRequest(URL(string: "https://github.com/login/device/code")!, ["client_id": clientID])
        let device = try await response(deviceRequest)
        guard let code = device["device_code"] as? String, let userCode = device["user_code"] as? String,
              let verification = device["verification_uri"] as? String, let url = URL(string: verification) else {
            throw ChatToolError.unavailable("GitHub 승인 코드를 받지 못했습니다.")
        }
        await onCode(userCode)
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
        var interval = max(5, device["interval"] as? Int ?? 5)
        let deadline = Date().addingTimeInterval(Double(device["expires_in"] as? Int ?? 900))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            let request = formRequest(URL(string: "https://github.com/login/oauth/access_token")!,
                                      ["client_id": clientID, "device_code": code, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
            let result = try await response(request)
            if let value = result["access_token"] as? String {
                try save(token(from: result, accessToken: value), id: "github")
                return
            }
            switch result["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            default: throw ChatToolError.unavailable(result["error_description"] as? String ?? "GitHub 승인이 완료되지 않았습니다.")
            }
        }
        throw ChatToolError.unavailable("GitHub 승인 시간이 지났습니다. 다시 연결하세요.")
    }

    /// Args: request는 공급자 토큰 요청, oldRefresh는 갱신 응답에 refresh_token이 없을 때 유지할 기존 토큰이다.
    /// Returns: 교환된 OAuth 토큰.
    /// Raises: HTTP·서비스 오류.
    private static func exchange(_ request: URLRequest, oldRefresh: String? = nil) async throws -> PluginToken {
        let result = try await response(request)
        guard let value = result["access_token"] as? String else {
            throw ChatToolError.unavailable(result["error_description"] as? String ?? "플러그인 인증에 실패했습니다.")
        }
        var token = token(from: result, accessToken: value)
        token.refreshToken = token.refreshToken ?? oldRefresh
        return token
    }

    /// Args: result는 공급자 토큰 응답, accessToken은 필수 액세스 토큰이다.
    /// Returns: 만료 정보가 포함된 저장용 토큰.
    /// Raises: 없음.
    private static func token(from result: [String: Any], accessToken: String) -> PluginToken {
        let seconds = result["expires_in"] as? Double ?? (result["expires_in"] as? Int).map(Double.init)
        return .init(accessToken: accessToken, refreshToken: result["refresh_token"] as? String,
                     expiresAt: seconds.map { Date().timeIntervalSince1970 + $0 })
    }

    /// Args: token은 OAuth 토큰, id는 서비스 이름이다.
    /// Returns: 없음. 토큰을 Keychain에 저장한다.
    /// Raises: 인코딩·Keychain 오류.
    private static func save(_ token: PluginToken, id: String) throws {
        let data = try JSONEncoder().encode(token)
        try ChatSecrets.save(String(decoding: data, as: UTF8.self), account: "plugin-\(id)")
    }

    /// Args: url·fields는 폼 방식 OAuth 요청 정보이다.
    /// Returns: JSON 응답을 받도록 설정한 POST 요청.
    /// Raises: 없음.
    private static func formRequest(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var parts = URLComponents(); parts.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((parts.percentEncodedQuery ?? "").utf8)
        return request
    }

    /// Args: url은 Notion OAuth 토큰 주소, fields는 JSON 본문 값이다.
    /// Returns: JSON 방식 토큰 교환 요청.
    /// Raises: 없음.
    private static func jsonRequest(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(fields)
        return request
    }

    /// Args: request는 고정된 OAuth 서비스 주소의 요청이다.
    /// Returns: 서비스의 JSON 객체.
    /// Raises: HTTP·네트워크·JSON 오류.
    private static func response(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw ChatToolError.unavailable(json["error_description"] as? String ?? "플러그인 인증 HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return json
    }

    /// Args: 없음.
    /// Returns: Notion 클라이언트 ID·비밀키의 HTTP Basic 헤더.
    /// Raises: Keychain 오류.
    private static func notionBasicAuth() throws -> String {
        let id = try configuration("notion-client", environment: "WORKGRAPH_NOTION_CLIENT_ID")
        let secret = try configuration("notion-secret", environment: "WORKGRAPH_NOTION_CLIENT_SECRET")
        return "Basic " + Data("\(id):\(secret)".utf8).base64EncodedString()
    }

    /// Args: count는 난수 바이트 수이다.
    /// Returns: URL-safe OAuth state 또는 PKCE verifier.
    /// Raises: 없음.
    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

private extension Data {
    /// Args: 없음.
    /// Returns: 패딩 없는 URL-safe Base64 문자열.
    /// Raises: 없음.
    func base64URLEncoded() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class LoopbackOAuth {
    /// Args: auth는 브라우저 승인 URL, state는 CSRF 방지 난수이다.
    /// Returns: 승인 후 로컬 콜백으로 받은 코드.
    /// Raises: 포트 사용 중·승인 거절·상태 불일치.
    static func receive(auth: URL, state: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let server = socket(AF_INET, SOCK_STREAM, 0)
            guard server >= 0 else { throw ChatToolError.unavailable("OAuth 콜백을 시작하지 못했습니다.") }
            defer { close(server) }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(8765).bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard bound == 0, listen(server, 1) == 0 else { throw ChatToolError.unavailable("OAuth 콜백 포트 8765를 열 수 없습니다.") }
            await MainActor.run { _ = NSWorkspace.shared.open(auth) }
            var ready = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
            guard poll(&ready, 1, 300_000) > 0 else { throw ChatToolError.unavailable("OAuth 승인 시간이 지났습니다. 다시 연결하세요.") }
            let connection = accept(server, nil, nil)
            guard connection >= 0 else { throw ChatToolError.unavailable("OAuth 콜백을 받지 못했습니다.") }
            defer { close(connection) }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let count = recv(connection, &buffer, buffer.count, 0)
            let line = String(decoding: buffer.prefix(max(0, count)), as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
            let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let values = URLComponents(string: "http://127.0.0.1\(path)")?.queryItems ?? []
            let receivedState = values.first { $0.name == "state" }?.value
            let code = values.first { $0.name == "code" }?.value
            let accepted = path.hasPrefix("/callback?") && receivedState == state && code != nil
            let html = accepted ? "<h2>WorkGraph 플러그인이 연결되었습니다. 이 창을 닫아도 됩니다.</h2>" : "<h2>승인이 완료되지 않았습니다. WorkGraph에서 다시 시도하세요.</h2>"
            let body = Data(html.utf8)
            let header = "HTTP/1.1 \(accepted ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            let reply = Data(header.utf8) + body
            _ = reply.withUnsafeBytes { send(connection, $0.baseAddress, reply.count, 0) }
            guard accepted, let code else { throw ChatToolError.unavailable("OAuth 승인 또는 상태 확인에 실패했습니다.") }
            await MainActor.run { NSApp.activate(ignoringOtherApps: true) }
            return code
        }.value
    }
}

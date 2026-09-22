import Foundation
import WorkGraphCollectors
import WorkGraphCore

/// 사용자 설정. UserDefaults 에 JSON 한 덩어리로 저장한다.
struct AppSettings: Codable, Equatable {
    /// "codex" = 앱 안에서 ChatGPT 로그인 후 직접 호출, "openai" = OpenAI 호환 서버(gpt-proxy, Ollama 등)
    var llmProvider = "codex"
    /// ChatGPT 로그인 방식에서 쓸 모델. 계정마다 가능한 모델이 달라 설정 화면에서 목록을 받아 고른다.
    var codexModel = CodexResponsesClient.defaultModel
    var llmBaseURL = "http://localhost:5010/v1"
    var llmModel = "gpt-5.4-mini"
    var llmAPIKey = ""
    var batchEnabled = true
    var captureText = true
    var captureScreenshots = true
    var watchDownloads = true
    var readChatLogs = true
    var retentionDays = 7
    /// 메뉴바 아이콘은 노치나 다른 아이콘에 가려질 수 있어서 Dock 아이콘을 기본으로 보여준다.
    var showDockIcon = true
    var excludedBundles: [String] = PrivacyFilter.defaultExcludedBundles.sorted()

    private static let key = "workgraph.settings.v1"

    init() {}

    /// 나중에 항목이 늘어도 예전에 저장한 설정이 통째로 초기화되지 않게, 없는 값은 기본값으로 채운다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        llmProvider = try c.decodeIfPresent(String.self, forKey: .llmProvider) ?? d.llmProvider
        codexModel = try c.decodeIfPresent(String.self, forKey: .codexModel) ?? d.codexModel
        llmBaseURL = try c.decodeIfPresent(String.self, forKey: .llmBaseURL) ?? d.llmBaseURL
        llmModel = try c.decodeIfPresent(String.self, forKey: .llmModel) ?? d.llmModel
        llmAPIKey = try c.decodeIfPresent(String.self, forKey: .llmAPIKey) ?? d.llmAPIKey
        batchEnabled = try c.decodeIfPresent(Bool.self, forKey: .batchEnabled) ?? d.batchEnabled
        captureText = try c.decodeIfPresent(Bool.self, forKey: .captureText) ?? d.captureText
        captureScreenshots = try c.decodeIfPresent(Bool.self, forKey: .captureScreenshots) ?? d.captureScreenshots
        watchDownloads = try c.decodeIfPresent(Bool.self, forKey: .watchDownloads) ?? d.watchDownloads
        readChatLogs = try c.decodeIfPresent(Bool.self, forKey: .readChatLogs) ?? d.readChatLogs
        retentionDays = try c.decodeIfPresent(Int.self, forKey: .retentionDays) ?? d.retentionDays
        showDockIcon = try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? d.showDockIcon
        excludedBundles = try c.decodeIfPresent([String].self, forKey: .excludedBundles) ?? d.excludedBundles
    }

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return saved
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    var collector: CollectorSettings {
        var settings = CollectorSettings()
        settings.captureText = captureText
        settings.captureScreenshots = captureScreenshots
        settings.watchDownloads = watchDownloads
        settings.readChatLogs = readChatLogs
        settings.retentionDays = retentionDays
        settings.excludedBundles = Set(excludedBundles)
        return settings
    }
}

import Foundation

/// 기록하지 않을 앱과 창을 정한다. 제외된 동안에도 "제외된 앱"이라는 빈 행은 남겨서
/// 앞 행의 체류시간이 그 시간까지 늘어나지 않게 한다.
public struct PrivacyFilter: Sendable {
    public static let defaultExcludedBundles: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal", "org.keepassxc.keepassxc", "com.apple.keychainaccess", "com.apple.Passwords",
        "com.apple.loginwindow", "com.apple.screencaptureui", "com.apple.ScreenSaver.Engine",
    ]

    /// 시크릿/프라이빗 창 제목 표식. "private" 단독은 오탐이 많아 넣지 않는다 ("Private API docs" 등).
    static let privateTitleHints = [
        "incognito", "inprivate", "private browsing", "private window", "private mode", "- private", "(private)",
        "시크릿", "개인정보 보호 브라우징", "프라이빗 브라우징", "개인 정보 보호 브라우징",
    ]

    public var excludedBundles: Set<String>

    public init(excludedBundles: Set<String> = PrivacyFilter.defaultExcludedBundles) {
        self.excludedBundles = excludedBundles
    }

    public func isExcluded(bundle: String) -> Bool {
        excludedBundles.contains(bundle) || bundle == Bundle.main.bundleIdentifier
    }

    /// 기본 제외 목록의 표시 이름 (설치되지 않은 앱도 이름은 보여주기 위해)
    public static let defaultNames: [String: String] = [
        "com.1password.1password": "1Password", "com.agilebits.onepassword7": "1Password 7", "com.bitwarden.desktop": "Bitwarden",
        "com.lastpass.LastPass": "LastPass", "com.dashlane.dashlanephonefinal": "Dashlane", "org.keepassxc.keepassxc": "KeePassXC",
        "com.apple.keychainaccess": "키체인 접근", "com.apple.Passwords": "암호", "com.apple.loginwindow": "로그인 창",
        "com.apple.screencaptureui": "스크린샷 도구", "com.apple.ScreenSaver.Engine": "화면 보호기",
    ]

    public func isPrivateWindow(title: String?) -> Bool {
        guard let lower = title?.lowercased(), !lower.isEmpty else { return false }
        return Self.privateTitleHints.contains { lower.contains($0) }
    }
}

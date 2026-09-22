import AppKit
import Foundation
import UserNotifications
import WorkGraphCore

/// 파일 정리 제안을 macOS 알림으로 보여 준다. 알림의 버튼으로 바로 옮기거나 무시할 수 있다.
/// .app 번들로 실행될 때만 동작한다 (swift run 으로 띄운 실행 파일에는 알림 센터가 없다).
final class SuggestionNotifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    enum Action { case move, ignore, open }

    static let category = "FILE_SUGGESTION"
    var onAction: ((Action, Int64) -> Void)?
    /// 알림이 시스템 설정에서 꺼져 있으면 true 로 알려 준다
    var onDenied: ((Bool) -> Void)?
    private let available: Bool
    private var authorized = false

    override init() {
        available = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
        super.init()
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let move = UNNotificationAction(identifier: "move", title: "옮기기", options: [])
        let ignore = UNNotificationAction(identifier: "ignore", title: "무시", options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [move, ignore], intentIdentifiers: [], options: [])])
    }

    /// 요청 없이 현재 상태만 읽는다 (앱 시작 때)
    func checkStatus() {
        guard available else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            self?.onDenied?(settings.authorizationStatus == .denied)
        }
    }

    func notify(_ suggestion: FileSuggestion, home: String) {
        guard available, let id = suggestion.id else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            self?.authorized = granted
            center.getNotificationSettings { [weak self] settings in
                AppLog.write("알림 권한: \(granted ? "허용" : "거부") 상태=\(settings.authorizationStatus.rawValue) 배너=\(settings.alertSetting.rawValue)\(error.map { " 오류=\($0.localizedDescription)" } ?? "")")
                self?.onDenied?(settings.authorizationStatus == .denied)
            }
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = suggestion.fileName
            content.body = "→ " + Self.short(suggestion.suggestedFolder, home: home)
            if let reason = suggestion.reason, !reason.isEmpty { content.subtitle = reason }
            content.categoryIdentifier = Self.category
            content.userInfo = ["suggestionId": id]
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "file-suggestion-\(id)", content: content, trigger: nil)) { error in
                if let error { AppLog.write("알림 보내기 실패: \(error.localizedDescription)") }
            }
        }
    }

    func remove(id: Int64) {
        guard available else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["file-suggestion-\(id)"])
    }

    /// 시스템 설정 > 알림 > WorkGraph
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.capstone.workgraph"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") { NSWorkspace.shared.open(url) }
    }

    static func short(_ path: String, home: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]                                   // 앱이 앞에 있어도 보여 준다
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["suggestionId"] as? Int64
                ?? (response.notification.request.content.userInfo["suggestionId"] as? NSNumber)?.int64Value else { return }
        let action: Action
        switch response.actionIdentifier {
        case "move": action = .move
        case "ignore": action = .ignore
        default: action = .open
        }
        onAction?(action, id)
    }
}

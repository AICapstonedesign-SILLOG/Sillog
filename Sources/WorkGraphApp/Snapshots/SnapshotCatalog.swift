import SwiftUI
import WorkGraphCollectors
import WorkGraphCore

/// 스냅샷으로 그릴 화면 목록. 이름은 Figma 화면 번호를 따른다 (Figma 에서 내보낸 같은 이름의 PNG 와 나란히 본다)
@MainActor
enum SnapshotCatalog {
    static var all: [Snapshot] { menus + windows }

    /// Figma 창(760) 에서 제목 줄(44)을 뺀 내용 영역
    static let window = CGSize(width: 1180, height: 716)

    static var menus: [Snapshot] {
        [
            shot("OUT-W2", MenuBarView()) { s in s.phase = .login },
            shot("OUT-W7", MenuBarView()) { s in
                s.phase = .ready; s.status = collector(paused: true)
                s.todayCount = 8; s.pendingCount = 2; s.lastBatchText = "14:05 정리 완료(새 업무 2개, 자료 5개)"
            },
            shot("OUT-W6", MenuBarView()) { s in
                s.phase = .ready; s.status = collector(accessibility: false)
                s.todayCount = 8; s.pendingCount = 2; s.lastBatchText = "14:05 정리 완료(새 업무 1개, 자료 3개)"
            },
            shot("OUT-06", MenuBarView()) { s in
                s.phase = .ready; s.status = collector()
                s.todayCount = 62; s.pendingCount = 6; s.notificationsDenied = true
                s.fileSuggestions = pendingFiles(2); s.taskList = recentTasks
            },
            // 리뷰 포커스 4: 큰 숫자와 긴 업무 이름
            shot("OUT-06-long", MenuBarView()) { s in
                s.phase = .ready; s.status = collector()
                s.todayCount = 1234; s.pendingCount = 0
                s.taskList = [TaskSummary(id: 9, key: "long", title: "아주 긴 업무 이름이 메뉴 폭을 넘어가면 한 줄로 잘려야 하는지 보는 업무",
                                          taskType: nil, activeSeconds: 60, lastActive: todayAt(9, 5), sessionCount: 1)]
            },
        ]
    }

    static var windows: [Snapshot] {
        [
            shot("OUT-01", MainWindow(), size: window) { s in loginStep(s) },
            shot("OUT-02", MainWindow(), size: window) { s in loginStep(s); s.deviceCode = sampleCode },
            shot("OUT-02-signed-in", MainWindow(), size: window) { s in
                loginStep(s); s.phase = .permissions
                s.codexStatus = .loggedIn(email: "sillog@example.com", plan: nil, expiresAt: nil)
            },
            shot("OUT-03", MainWindow(), size: window) { s in permissionStep(s, PermissionGrants(accessibility: false, screenRecording: false)) },
            shot("OUT-04", MainWindow(), size: window) { s in permissionStep(s, PermissionGrants(accessibility: true, screenRecording: false)) },
            shot("OUT-05", MainWindow(), size: window) { s in
                permissionStep(s, PermissionGrants(accessibility: true, screenRecording: true)); s.askedScreenRecording = true
            },
            shot("OUT-W1", MainWindow(), size: window) { s in s.phase = .login; s.loginBlocked = true },
            shot("OUT-W3", MainWindow(), size: window) { s in s.startupError = AppState.alreadyRunningMessage },
            shot("OUT-W4", MainWindow(), size: window) { s in s.bootstrapped = false },
            shot("OUT-W5", MainWindow(), size: window) { s in
                s.phase = .ready; s.status = collector(); s.batchRunning = true; s.pendingCount = 6
                s.fileSuggestions = pendingFiles(2); s.taskList = recentTasks; s.selectedTab = .tasks
            },
        ]
    }

    // MARK: 예시 상태

    private static func shot<V: View>(_ name: String, _ view: V, size: CGSize? = nil, _ configure: (AppState) -> Void) -> Snapshot {
        let state = AppState(preview: configure)
        return Snapshot(name: name, size: size, view: AnyView(view.environmentObject(state)))
    }

    /// 시트 뒤에는 업무 탭(그래프 탭은 웹 보기라 스냅샷에 안 그려진다)
    private static func loginStep(_ s: AppState) {
        s.phase = .login; s.onboardingStep = .login; s.selectedTab = .tasks
        s.taskList = recentTasks; s.fileSuggestions = pendingFiles(2); s.pendingCount = 6
    }

    private static func permissionStep(_ s: AppState, _ grants: PermissionGrants) {
        s.phase = .permissions; s.onboardingStep = .permissions; s.permissionGrants = grants; s.selectedTab = .tasks
        s.taskList = recentTasks; s.fileSuggestions = pendingFiles(2); s.pendingCount = 6
    }

    private static func collector(accessibility: Bool = true, screenRecording: Bool = true, paused: Bool = false) -> CollectorStatus {
        var status = CollectorStatus()
        status.running = true
        status.accessibility = accessibility
        status.screenRecording = screenRecording
        status.paused = paused
        return status
    }

    private static func todayAt(_ hour: Int, _ minute: Int) -> Double {
        (Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()).timeIntervalSince1970
    }

    private static var recentTasks: [TaskSummary] {
        [TaskSummary(id: 1, key: "flask", title: "Flask 웹앱 개발", taskType: nil, activeSeconds: 9600, lastActive: todayAt(14, 32), sessionCount: 3),
         TaskSummary(id: 2, key: "stats", title: "통계학 수업", taskType: nil, activeSeconds: 3000, lastActive: todayAt(12, 10), sessionCount: 1),
         TaskSummary(id: 3, key: "report", title: "분기 성과 보고서", taskType: nil, activeSeconds: 4500, lastActive: todayAt(11, 45), sessionCount: 1)]
    }

    private static func pendingFiles(_ count: Int) -> [FileSuggestion] {
        (0..<count).map {
            FileSuggestion(id: Int64($0 + 1), ts: 0, path: "/tmp/file\($0).pdf", fileName: "file\($0).pdf", originUrl: nil,
                           suggestedFolder: "/tmp", confidence: 0.9, reason: nil, source: "llm")
        }
    }

    private static var sampleCode: DeviceCode {
        DeviceCode(verificationURL: URL(string: "https://auth.openai.com/codex/device")!, userCode: "SILL-OG26",
                   deviceAuthId: "preview", interval: 5, expiresAt: Date().timeIntervalSince1970 + 900)
    }
}

import AppKit
import SwiftUI
import WorkGraphCollectors
import WorkGraphCore

/// 시작점: 글꼴을 먼저 등록하고 SwiftUI 앱을 띄운다
@main
enum AppEntry {
    static func main() {
        // 개발용: 창 없이 상태별 화면을 PNG 로 그리고 끝난다 (SnapshotRunner)
        if let directory = ProcessInfo.processInfo.environment["WORKGRAPH_SNAPSHOT"], !directory.isEmpty {
            MainActor.assumeIsolated { SnapshotRunner.run(into: directory) }
        }
        let fonts = BrandFonts.register()
        if fonts.count < 6 { AppLog.write("글꼴 \(fonts.count)/6개만 등록됨: \(fonts.sorted())") }
        WorkGraphApp.main()
    }
}

struct WorkGraphApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(state)
        } label: {
            MenuBarLabel(paused: state.status.paused).environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        Window("SILLOG", id: "main") {
            MainWindow().environmentObject(state)
        }
        .defaultSize(width: 1180, height: 760)
    }
}

enum Launch {
    /// 이 실행이 첫 실행인지. 앱이 뜰 때 한 번만 계산한다.
    static let isFirst: Bool = {
        let key = "workgraph.launchedBefore"
        let before = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        return !before || ProcessInfo.processInfo.environment["WORKGRAPH_SHOW_WINDOW"] == "1"
    }()

    /// 로그인 항목으로 자동 실행된 경우. 이때만 창 없이 조용히 시작한다.
    @MainActor static var asLoginItem = false
}

/// SwiftUI 의 창 열기 동작을 AppKit 쪽(Dock 클릭, 앱 다시 실행)에서도 쓸 수 있게 보관한다.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    var open: (() -> Void)?

    func openMain() {
        open?()
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 메뉴바 아이콘. 메뉴바가 붐비면 노치 뒤로 가려질 수 있으므로 앱을 찾는 주 경로는 Dock 아이콘이다.
struct MenuBarLabel: View {
    let paused: Bool
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: paused ? "pause.fill" : "point.3.connected.trianglepath.dotted")
            .task {
                WindowOpener.shared.open = { openWindow(id: "main") }
                await state.bootstrap()
                // 로그인 항목으로 조용히 뜬 경우가 아니면 창을 보여준다. 로그인 전이면 항상 온보딩을 띄운다.
                guard state.phase != .ready || Launch.isFirst || !Launch.asLoginItem else { return }
                WindowOpener.shared.openMain()
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 디자인(Figma)이 밝은 화면 전용이라 시스템이 다크 모드여도 앱은 밝게 그린다.
    /// 다크 모드를 따르면 유리 재질이 회색이 되고 진한 글씨가 탁해진다 (메뉴, 창, 웹 그래프 모두)
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        Launch.asLoginItem = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        NSApp.setActivationPolicy(AppSettings.load().showDockIcon ? .regular : .accessory)

        // WORKGRAPH_REQUEST_PERMISSIONS=1 로 띄우면 실행하자마자 두 권한을 요청해 시스템 설정 목록에 등록시킨다.
        if ProcessInfo.processInfo.environment["WORKGRAPH_REQUEST_PERMISSIONS"] == "1" {
            _ = Permissions.accessibility(prompt: true)
            Permissions.requestScreenRecording()
        }
        // 로그인 항목으로 떴는데 SwiftUI 가 창을 자동으로 열었다면 닫아 둔다 (백그라운드 서비스답게).
        if Launch.asLoginItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated {
                    guard !Launch.isFirst else { return }
                    NSApp.windows.filter { $0.canBecomeMain }.forEach { $0.close() }
                }
            }
        }
    }

    /// Dock 아이콘 클릭, Finder·Spotlight 에서 다시 실행 → 창을 연다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { WindowOpener.shared.openMain() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

import AppKit
import SwiftUI
import XCTest
@testable import WorkGraphApp

@MainActor
final class WindowGlassTests: XCTestCase {
    func testMainWindowLetsTheDesktopShowThroughTheGlass() {
        let state = AppState(preview: { s in s.phase = .ready; s.selectedTab = .tasks })
        let host = NSHostingView(rootView: AnyView(MainWindow().environmentObject(state)))
        host.frame = NSRect(x: 0, y: 0, width: 1180, height: 716)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        // 창이 불투명하면 유리를 덜 칠해도 뒤가 아니라 창 바탕이 보인다
        XCTAssertFalse(window.isOpaque, "유리 뒤로 바탕화면이 비치려면 창이 투명해야 한다")
        XCTAssertEqual(window.backgroundColor, .clear)
        // 유리 = 창 뒤를 흐리게(Brand.glassBlur) + 흰 막(Brand.glassWhite). 흰 막이 1 이면 뒤가 안 보이고, 흐림이 0 이면 뒤 글씨가 그대로 비친다
        XCTAssertGreaterThan(Brand.glassBlur, 0)
        XCTAssertLessThan(Brand.glassWhite, 1)
    }
}

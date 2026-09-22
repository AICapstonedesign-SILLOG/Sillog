import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if state.phase != .ready {
            Text(state.statusLine)
            Divider()
            Button("시작하기…") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("WorkGraph 종료") { NSApp.terminate(nil) }
        } else {
            readyMenu
        }
    }

    @ViewBuilder private var readyMenu: some View {
        Text(state.statusLine)
        Text("오늘 기록 \(state.todayCount)개, 정리 대기 \(state.pendingCount)개")
        Text(state.lastBatchText)
        if !state.status.accessibility || !state.status.screenRecording {
            Text("권한이 빠져 있어 일부만 수집 중입니다")
        }
        Divider()
        Button("그래프 열기") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(state.batchRunning ? "정리하는 중…" : "지금 정리") { Task { await state.runBatch(force: true) } }
            .disabled(state.batchRunning)
        Button(state.status.paused ? "수집 다시 시작" : "수집 일시정지") { state.togglePause() }
        Divider()
        Button("WorkGraph 종료") { NSApp.terminate(nil) }
    }
}

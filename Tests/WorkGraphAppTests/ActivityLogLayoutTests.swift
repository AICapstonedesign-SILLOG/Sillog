import AppKit
import SwiftUI
import XCTest
@testable import WorkGraphApp
import WorkGraphCore

/// 활동 로그 정리 기록: 정리가 많이 쌓여도 아래 LLM 교환 카드는 제자리에 있고 위 목록만 스크롤된다
@MainActor
final class ActivityLogLayoutTests: XCTestCase {
    private func show<V: View>(_ view: V, _ state: AppState) -> NSWindow {
        let host = NSHostingView(rootView: AnyView(view.environmentObject(state)))
        host.frame = NSRect(x: 0, y: 0, width: 1180, height: 716)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<6 {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return window
    }

    private func manyBatches(_ count: Int) -> [BatchRecord] {
        let stats = #"{"resources":2,"problems":0,"topics":1,"uncoveredRows":0,"laterItems":0,"offTaskRows":0,"tasksCreated":0,"tasksMerged":0,"sessions":0,"sessionsExtended":1,"unassignedRows":0}"#
        return (1...count).reversed().map { i in
            BatchRecord(id: Int64(i), startedAt: 1_790_000_000 + Double(i) * 300, rowCount: 6, status: "ok", model: "gpt-6-luna",
                        promptTokens: 3120, completionTokens: 840, stats: stats)
        }
    }

    func testBatchCardStaysOnScreenWhenTheListIsLong() {
        let state = AppState(preview: { s in s.phase = .ready; s.batches = self.manyBatches(120) })
        let window = show(ActivityLogView(section: .batches), state)
        let text = OnboardingOverlayTests.recognizedText(window.contentView!).filter { !$0.isWhitespace }
        XCTAssertTrue(text.contains("정리#120"), "정리 120번이 쌓여도 맨 위(최신) 정리의 카드가 창 안에 보여야 한다: \(text.suffix(300))")
    }

    func testBatchCardShowsAppliedResultInWords() {
        let state = AppState(preview: { s in s.phase = .ready; s.batches = self.manyBatches(3) })
        let window = show(ActivityLogView(section: .batches), state)
        let text = OnboardingOverlayTests.recognizedText(window.contentView!).filter { !$0.isWhitespace }
        XCTAssertTrue(text.contains("세션1개,새업무0개,자료2개"), "반영 결과는 JSON 이 아니라 Figma 처럼 말로: \(text.suffix(300))")
        XCTAssertFalse(text.contains("sessionsExtended"))
    }
}

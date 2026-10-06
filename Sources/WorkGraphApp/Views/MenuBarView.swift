import AppKit
import SwiftUI

/// 메뉴 막대 드롭다운 (Figma OUT-06, OUT-W2, W6, W7). `.window` 스타일 MenuBarExtra 안에서 그려진다.
struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    private var ready: Bool { state.phase == .ready }
    private var permissionMissing: Bool { !state.status.accessibility || !state.status.screenRecording }

    var body: some View {
        VStack(spacing: 0) {
            header
            if ready { readyContent } else { notReadyContent }
            footerButtons
        }
        .padding(.horizontal, 22)
        .frame(width: 344)
        .background(.white.opacity(0.94))
    }

    // MARK: 머리

    private var header: some View {
        HStack {
            if let mark = Brand.wordmark {
                Image(nsImage: mark).resizable().scaledToFit().frame(height: 21).accessibilityLabel("SILLOG")
            } else {
                Text("SILLOG").font(Brand.suit(18, .semibold)).foregroundStyle(Brand.ink)
            }
            Spacer()
            if ready {
                HStack(spacing: 7) {
                    if !state.status.paused { Rectangle().fill(permissionMissing ? Brand.gray : Brand.ink).frame(width: 6, height: 6) }
                    Text(state.statusLine == "수집 중" ? "기록 중" : state.statusLine)
                        .font(Brand.suit(10)).foregroundStyle(Brand.gray)
                }
            }
        }
        .frame(height: 60)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.hairline).frame(height: 1) }
    }

    // MARK: 로그인 전

    private var notReadyContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(Brand.gray)
                Text(state.startupError != nil ? state.statusLine : "시작하려면 ChatGPT 로그인이 필요해요")
                    .font(Brand.suit(12)).foregroundStyle(Brand.text)
                Spacer(minLength: 0)
            }
            .frame(height: 55)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.hairline).frame(height: 1) }
            primaryButton("시작하기…") { openMain() }
                .padding(.vertical, 18)
        }
    }

    // MARK: 로그인 후

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("오늘 기록 \(state.todayCount)개, 정리 대기 \(state.pendingCount)개")
                    .font(Brand.suit(12, .medium)).foregroundStyle(Brand.text)
                Text(state.lastBatchText).font(Brand.suit(11)).foregroundStyle(Brand.gray)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)

            if permissionMissing {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 14)).foregroundStyle(Brand.gray)
                    Text("권한이 빠져 있어 일부만 수집 중이에요").font(Brand.suit(12)).foregroundStyle(Brand.text)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Rectangle().fill(Brand.hairline).frame(height: 1) }
            }

            if state.pendingFileSuggestions > 0 {
                Button {
                    state.selectedTab = .files
                    openMain()
                } label: {
                    HStack {
                        Text("파일 정리 제안").font(Brand.suit(11)).foregroundStyle(Brand.text)
                        Spacer()
                        Text("\(state.pendingFileSuggestions)").font(Brand.jost(15)).foregroundStyle(Brand.text)
                        Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Brand.gray)
                    }
                    .frame(height: 45).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(Brand.hairline).frame(height: 1) }
            }

            if !state.taskList.isEmpty { recentWork }
            Spacer().frame(height: 14)
        }
    }

    private var recentWork: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("RECENT WORK").padding(.top, 18)
            Text("최근 업무 다시 열기").font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 4)
            ForEach(state.taskList.prefix(3)) { task in
                Button { state.prepareResume(taskId: task.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title).font(Brand.suit(12)).foregroundStyle(Brand.text).lineLimit(1)
                            Text(Self.timeText(task.lastActive)).font(Brand.suit(9)).foregroundStyle(Brand.gray)
                        }
                        Spacer()
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 12)).foregroundStyle(Brand.tabText)
                    }
                    .padding(.vertical, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
        .overlay(alignment: .top) { Rectangle().fill(Brand.hairline).frame(height: 1) }
    }

    // MARK: 바닥 버튼

    private var footerButtons: some View {
        VStack(spacing: 10) {
            if ready {
                primaryButton("그래프 열기") { openMain() }
                HStack(spacing: 8) {
                    secondaryButton(state.batchRunning ? "정리하는 중…" : "지금 정리") { Task { await state.runBatch(force: true) } }
                        .disabled(state.batchRunning)
                    secondaryButton(state.status.paused ? "수집 다시 시작" : "수집 일시정지") { state.togglePause() }
                }
            }
            Rectangle().fill(Brand.hairline).frame(height: 1).padding(.top, 8)
            Button { NSApp.terminate(nil) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 12))
                    Text("Sillog 종료").font(Brand.suit(11))
                }
                .foregroundStyle(Brand.tabText)
                .frame(maxWidth: .infinity).frame(height: 29).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 14)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Brand.suit(12, .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 6).fill(Brand.ink))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Brand.suit(12)).foregroundStyle(Brand.text)
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func timeText(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let time = AppState.clock.string(from: date)
        if Calendar.current.isDateInToday(date) { return "오늘 \(time)" }
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)월 \(c.day ?? 0)일 \(time)"
    }
}

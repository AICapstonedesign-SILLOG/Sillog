import AppKit
import SwiftUI
import WorkGraphCore

/// 메뉴 막대 드롭다운. 상태(MenuBarModel.mode)에 따라 Figma 네 화면 중 하나를 그린다.
///   OUT-W2 준비 전, OUT-W7 일시정지, OUT-W6 권한 경고: 버튼 메뉴 (폭 336, 흰 바탕)
///   OUT-06 정상: 큰 숫자 메뉴 (폭 344, 흰색 94%)
/// `.window` 스타일 MenuBarExtra 안에서 그려진다.
struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    private var mode: MenuBarMode {
        MenuBarModel.mode(phase: state.phase, startupFailed: state.startupError != nil, paused: state.status.paused,
                          running: state.status.running, accessibility: state.status.accessibility,
                          screenRecording: state.status.screenRecording)
    }

    private var status: String? {
        MenuBarModel.statusText(mode: mode, running: state.status.running, idle: state.status.idle)
    }

    var body: some View {
        if mode == .normal {
            MenuBarDashboard(status: status, openMain: openMain)
        } else {
            MenuBarButtons(mode: mode, status: status, openMain: openMain)
        }
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 머리: 왼쪽 SILLOG 로고, 오른쪽 상태 글씨, 아래 구분선
private struct MenuBarHeader: View {
    let height: CGFloat
    let logoHeight: CGFloat
    let status: String?
    let statusFont: Font
    let line: Color
    /// OUT-06 은 "■" 를 진한 네모로 따로 그린다 (W6 은 글씨 색 그대로)
    var squareColor: Color? = nil

    var body: some View {
        HStack {
            if let mark = Brand.wordmark {
                Image(nsImage: mark).resizable().scaledToFit().frame(height: logoHeight).accessibilityLabel("SILLOG")
            } else {
                Text("SILLOG").font(Brand.suit(18, .semibold)).foregroundStyle(Brand.ink)
            }
            Spacer()
            if let status, let squareColor, status.hasPrefix("■ ") {
                HStack(spacing: 7) {
                    Rectangle().fill(squareColor).frame(width: 6, height: 6)
                    Text(status.dropFirst(2)).font(statusFont).foregroundStyle(Brand.gray)
                }
            } else if let status {
                Text(status).font(statusFont).foregroundStyle(Brand.gray)
            }
        }
        .frame(height: height)
        .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }
}

// MARK: OUT-W2 · OUT-W6 · OUT-W7

/// 요약 한두 줄과 큰 버튼 (흰 바탕, 폭 336, 안쪽 여백 24)
private struct MenuBarButtons: View {
    @EnvironmentObject private var state: AppState
    let mode: MenuBarMode
    let status: String?
    let openMain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarHeader(height: 64, logoHeight: 22, status: status, statusFont: Brand.suit(11), line: Brand.line)
            if mode == .notReady {
                notice(icon: "info.circle", MenuBarModel.notReadyMessage(phase: state.phase, startupFailed: state.startupError != nil))
                    .padding(.top, 18).padding(.bottom, 22)
                divider
                MenuPrimaryButton(title: "시작하기…", action: openMain)
                    .padding(.top, 18).padding(.bottom, 16)
            } else {
                summary
                divider
                VStack(spacing: 10) {
                    MenuPrimaryButton(title: "그래프 열기") {
                        state.selectedTab = .graph
                        openMain()
                    }
                    HStack(spacing: 8) {
                        MenuSecondaryButton(title: state.batchRunning ? "정리하는 중…" : "지금 정리") {
                            Task { await state.runBatch(force: true) }
                        }
                        .disabled(state.batchRunning)
                        MenuSecondaryButton(title: state.status.paused ? "수집 다시 시작" : "수집 일시정지") { state.togglePause() }
                    }
                }
                .padding(.vertical, 16)
            }
            divider
            Button { NSApp.terminate(nil) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 13))
                    Text("Sillog 종료").font(Brand.suit(13))
                }
                .foregroundStyle(Brand.ink)
                .frame(maxWidth: .infinity).frame(height: 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 16).padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .frame(width: 336)
        .background(.white)
    }

    /// W6·W7: 오늘 숫자, 마지막 정리, (W6) 권한 경고
    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("오늘 기록 \(state.todayCount)개, 정리 대기 \(state.pendingCount)개")
                .font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink)
            Text(state.lastBatchText).font(Brand.suit(12)).foregroundStyle(Brand.gray).lineLimit(2)
                .padding(.top, 8)
            if mode == .permissionMissing {
                notice(icon: "exclamationmark.circle", "권한이 빠져 있어 일부만 수집 중이에요").padding(.top, 20)
            }
        }
        .padding(.top, 18).padding(.bottom, 17)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notice(icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Brand.ink)
            Text(text).font(Brand.suit(13)).foregroundStyle(Brand.ink)
        }
    }

    private var divider: some View { Rectangle().fill(Brand.line).frame(height: 1) }
}

/// 주색 큰 버튼 (288×42, 모서리 8, SUIT 500 14)
private struct MenuPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Brand.suit(14, .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 8).fill(Brand.ink))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 흰 바탕 테두리 버튼 (140×42, 모서리 8, SUIT 500 13)
private struct MenuSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.line))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: OUT-06

/// 큰 숫자 두 개, 알림·파일 제안 줄, 최근 업무 3개, [지금 정리], 일시정지·종료 (흰색 94%, 폭 344, 안쪽 여백 23)
private struct MenuBarDashboard: View {
    @EnvironmentObject private var state: AppState
    let status: String?
    let openMain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarHeader(height: 60, logoHeight: 21, status: status, statusFont: Brand.suit(10), line: Brand.hairline, squareColor: Brand.ink)
            stats
            if state.notificationsDenied { notificationRow }
            if state.pendingFileSuggestions > 0 { fileRow }
            if !state.taskList.isEmpty { recentWork }
            bottom
        }
        .padding(.horizontal, 23)
        .frame(width: 344)
        .background(.white.opacity(0.94))
    }

    /// TODAY·WAITING: 눈썹 글씨 17, 숫자 76 (Jost 200 54), 설명 15. 사이에 세로선
    private var stats: some View {
        HStack(alignment: .top, spacing: 0) {
            number("TODAY", state.todayCount, "오늘 기록").frame(width: 149, alignment: .leading)
            Rectangle().fill(Brand.hairline).frame(width: 1, height: 107)
            number("WAITING", state.pendingCount, "정리 대기").padding(.leading, 23)
            Spacer(minLength: 0)
        }
        .padding(.top, 21)
        .frame(height: 153, alignment: .top)
        .overlay(alignment: .bottom) { hairline }
    }

    private func number(_ eyebrow: String, _ value: Int, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(eyebrow).frame(height: 17, alignment: .leading)
            Text(MenuBarModel.twoDigits(value))
                .font(Brand.jostLight(54)).foregroundStyle(Brand.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(height: 76, alignment: .leading)
            Text(caption).font(Brand.suit(10)).foregroundStyle(Brand.gray).frame(height: 15, alignment: .leading)
        }
    }

    /// 알림 권한이 꺼져 있으면: 누르면 시스템 설정의 알림
    private var notificationRow: some View {
        Button { SuggestionNotifier.openSystemSettings() } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 14)).foregroundStyle(Brand.ink)
                Text("파일 제안 알림 권한이 꺼져 있어요").font(Brand.suit(10)).foregroundStyle(Brand.tabText)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Brand.tabText)
            }
            .frame(height: 45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { hairline }
    }

    /// 파일 정리 제안이 있으면: 누르면 파일 탭
    private var fileRow: some View {
        Button {
            state.selectedTab = .files
            openMain()
        } label: {
            HStack(spacing: 0) {
                Text("파일 정리 제안").font(Brand.suit(11)).foregroundStyle(Brand.text)
                Spacer()
                Text("\(state.pendingFileSuggestions)").font(Brand.jost(15)).foregroundStyle(Brand.text)
                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Brand.tabText).padding(.leading, 18)
            }
            .padding(.trailing, 25)
            .frame(height: 55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { hairline }
    }

    /// 최근 업무 3개. 누르면 다시 열기 (prepareResume 이 창을 연다)
    private var recentWork: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("RECENT WORK").frame(height: 17, alignment: .leading)
            Text("최근 업무 다시 열기").font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 5)
            VStack(alignment: .leading, spacing: 20) {
                ForEach(state.taskList.prefix(3)) { task in
                    Button { state.prepareResume(taskId: task.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(task.title).font(Brand.suit(12)).foregroundStyle(Brand.text).lineLimit(1)
                                    .frame(height: 18, alignment: .leading)
                                Text(Self.timeText(task.lastActive)).font(Brand.suit(9)).foregroundStyle(Brand.gray)
                                    .frame(height: 14, alignment: .leading)
                                    .padding(.top, 23)
                            }
                            Spacer(minLength: 12)
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 12)).foregroundStyle(Brand.ink)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 20)
        }
        .padding(.top, 20).padding(.bottom, 19)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// [지금 정리] 와 일시정지·종료. 최근 업무가 있을 때만 위에 선을 긋는다 (다른 줄은 아래에 선이 있다)
    private var bottom: some View {
        VStack(spacing: 0) {
            Button { Task { await state.runBatch(force: true) } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .medium))
                    Text(state.batchRunning ? "정리하는 중…" : "지금 정리").font(Brand.suit(12, .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 6).fill(Brand.ink))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.batchRunning)
            HStack(spacing: 0) {
                footerButton("pause", "일시정지") { state.togglePause() }
                footerButton("rectangle.portrait.and.arrow.right", "종료") { NSApp.terminate(nil) }
            }
            .frame(height: 35)
            .padding(.top, 11)
        }
        .padding(.top, 16).padding(.bottom, 12)
        .overlay(alignment: .top) { if !state.taskList.isEmpty { hairline } }
    }

    private func footerButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(Brand.suit(10))
            }
            .foregroundStyle(Brand.tabText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hairline: some View { Rectangle().fill(Brand.hairline).frame(height: 1) }

    static func timeText(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let time = AppState.clock.string(from: date)
        if Calendar.current.isDateInToday(date) { return "오늘 \(time)" }
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)월 \(c.day ?? 0)일 \(time)"
    }
}

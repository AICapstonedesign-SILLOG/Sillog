import SwiftUI
import WorkGraphCore

/// 유리 탭 막대: 흰색 72% 위에 배경 흐림, 선택한 탭은 흰색 78% 알약
/// 창 맨 왼쪽 세로 막대: 그래프, 채팅, 설정 아이콘과 맨 아래 지금 정리 (VIEW 목록 왼쪽에 붙는다)
private struct NavRail: View {
    @EnvironmentObject private var state: AppState
    private func icon(_ tab: MainWindow.Tab) -> String {
        switch tab { case .graph: "point.3.connected.trianglepath.dotted"; case .chat: "bubble.left"; case .settings: "gearshape" }
    }
    var body: some View {
        VStack(spacing: 6) {
            ForEach(MainWindow.Tab.allCases) { tab in
                let on = state.selectedTab == tab
                Button { state.selectedTab = tab } label: {
                    Image(systemName: icon(tab)).font(.system(size: 15, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Brand.ink : Brand.tabText)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color(hex: 0xF7F5F2) : .clear))   // 고른 탭 알약, 흰색보다 한 단계 어둡게
                    .hoverHighlight(cornerRadius: 10, active: !on)
                    .overlay(alignment: .topTrailing) {
                        if tab == .settings, state.pendingFileSuggestions > 0 { Circle().fill(Brand.sky).frame(width: 7, height: 7).offset(x: -3, y: 4) }   // 아이콘만이라 숫자 대신 점
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .railLabel(tab.rawValue)
            }
            if state.selectedTab == .chat {   // 예약, 스킬, 플러그인은 채팅 탭에서만
            Rectangle().fill(Brand.hairline).frame(width: 20, height: 1).padding(.vertical, 6)
            ForEach([("clock", "예약", "schedules"), ("sparkles", "스킬", "skills"), ("powerplug", "플러그인", "plugins")], id: \.2) { icon, name, sheet in
                Button { state.selectedTab = .chat; state.chatSheet = sheet } label: {
                    RailGlowIcon(name: icon)                                 // 아이콘 선을 따라 하늘빛이 천천히 흐른다
                        .frame(width: 36, height: 36)
                        .hoverHighlight(cornerRadius: 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).railLabel(name).accessibilityLabel(name)
            }
            }
            Spacer(minLength: 0)
            AccountDot()
        }
        .padding(.top, 10).padding(.bottom, 12).padding(.horizontal, 6)
        .frame(width: 48)
        .frame(maxHeight: .infinity)
        .background(Color(hex: 0xEFECE9))                    // 창 머리와 같은 톤, 흰색보다 한 단계 낮춤
        .overlay(alignment: .trailing) { Rectangle().fill(Brand.hairline).frame(width: 1) }
    }
}

/// 아이콘 줄 맨 아래 계정 동그라미: 로그인한 이메일 앞 두 글자. 누르면 설정
private struct AccountDot: View {
    @EnvironmentObject private var state: AppState
    private var email: String? { if case .loggedIn(let email, _, _) = state.codexStatus { return email }; return nil }
    var body: some View {
        let initials = String((email ?? "?").prefix(2)).uppercased()
        Button { state.settingsSection = .ai; state.selectedTab = .settings } label: {   // 계정 연결은 AI 구역
            Text(initials).font(Brand.suit(11, .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Circle().fill(Brand.ink))
                .frame(width: 36, height: 36).contentShape(Circle())
        }
        .buttonStyle(.plain).railLabel(email ?? "계정").accessibilityLabel("계정 \(email ?? "")")
    }
}

/// 아이콘 줄 이름표: 커서를 대면 오른쪽에 작은 이름표가 바로 뜬다 (기본 도움말은 늦게 떠서)
private struct RailLabel: ViewModifier {
    let text: String
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .onHover { hover = $0 }
            .overlay(alignment: .leading) {
                if hover {
                    Text(text).font(Brand.suit(11, .medium)).foregroundStyle(.white).fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Brand.ink.opacity(0.88)))
                        .offset(x: 44).allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}
private extension View { func railLabel(_ text: String) -> some View { modifier(RailLabel(text: text)) } }

/// 아이콘 선 자체에 옅은 하늘빛이 비스듬히 지나간다 (그래프 AI 검색 밑줄과 같은 색). 바탕 아이콘은 다른 아이콘과 같은 회색
private struct RailGlowIcon: View {
    let name: String
    @State private var phase: CGFloat = -0.65   // 빛 띠 가운데가 늘 아이콘 위를 지나도록
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let glyph = Image(systemName: name).font(.system(size: 15))
        glyph.foregroundStyle(Color(hex: 0x5E97C8))                             // 늘 하늘빛 (회색 대신)
            .shadow(color: Color(hex: 0x9CCBF0).opacity(0.9), radius: 3)       // 항상 은은히 번짐
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: Color(hex: 0xBFE2FB), location: 0.4),
                                       .init(color: .white, location: 0.5), .init(color: Color(hex: 0xBFE2FB), location: 0.6),
                                       .init(color: .clear, location: 1)],
                               startPoint: UnitPoint(x: phase, y: phase), endPoint: UnitPoint(x: phase + 1, y: phase + 1))
                    .mask(glyph)                                                 // 그 위로 밝은 띠가 오간다
            }
            .onAppear {
                guard !reduce else { return }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { phase = 0.65 }
            }
    }
}

/// 창 머리 오른쪽 끝: 지금 정리 (회전 아이콘 + 대기 수), 정리 중이면 작은 회전 표시
private struct TitleRefresh: View {
    @EnvironmentObject private var state: AppState
    @State private var spin = false
    /// 기록 중(수집이 돌고, 멈춤이나 자리 비움이 아닐 때)이면 아이콘이 천천히 돈다
    private var recording: Bool { state.status.running && !state.status.paused && !state.status.idle }
    var body: some View {
        Button { Task { await state.runBatch(force: true) } } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                    .rotationEffect(.degrees(spin ? -360 : 0))
                    .animation(spin ? .linear(duration: state.batchRunning ? 0.9 : 2.4).repeatForever(autoreverses: false) : .default, value: spin)
                if state.pendingCount > 0 { Text("\(state.pendingCount)").font(Brand.jost(11)) }
            }
            .foregroundStyle(Brand.tabText).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.batchRunning)
        .help(state.batchRunning ? "정리하는 중…" : recording ? "기록 중. 누르면 지금 정리합니다" : "지금 정리: 아직 정리되지 않은 활동을 바로 그래프에 반영합니다")
        .padding(.trailing, 14)                                   // 아래 '업무 28개, 항목 242개' 오른쪽 끝과 맞춘다
        .onAppear { spin = recording || state.batchRunning }
        .onChange(of: recording || state.batchRunning) { _, on in spin = on }
    }
}

/// 설정 탭과 설정의 파일 구역 옆 대기 중인 정리 제안 수 (Figma OUT-01 탭 막대: Jost 10, 하늘색 테두리)
struct FileBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)").font(Brand.jost(11)).foregroundStyle(Color(hex: 0x5E97C8))   // 상자 없이 하늘색 숫자만
    }
}

/// 창 바탕을 유리로: 흰색을 직접 칠하지 않은 사이드바와 탭 막대 뒤로 바탕화면이 흐리게 비친다(마누스 시제품과 같은 구조).
/// 창을 투명하게 하고 창 뒤를 흐린 뒤(WindowBlur) 흰 막을 얹는다. macOS 기본 유리는 흐림·흰 막을 정할 수 없어 하얗게 막혀 보인다
private struct WindowGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        let glass = content
            .background(Group {
                if WindowBlur.available { Color.white.opacity(Brand.glassWhite) } else { BehindWindowGlass() }
            }.ignoresSafeArea())
            .background(ClearWindow())
        if #available(macOS 15.0, *) { glass.containerBackground(.clear, for: .window) } else { glass }
    }
}

/// 이 뷰가 들어간 창을 투명하게 하고 창 뒤를 흐린다 (불투명한 창은 유리를 칠해도 뒤가 아니라 창 바탕이 보인다)
private struct ClearWindow: NSViewRepresentable {
    final class View: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            WindowBlur.apply(Brand.glassBlur, to: window)
            DispatchQueue.main.async { [weak window] in            // 창이 화면에 올라간 뒤 한 번 더 (창 번호가 그때 정해지는 경우)
                if let window { WindowBlur.apply(Brand.glassBlur, to: window) }
            }
        }
    }
    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ nsView: View, context: Context) {}
}

/// 창 뒤 흐림 반경을 정하는 macOS 비공개 함수 (iTerm2 의 '흐림' 설정이 쓰는 것).
/// 없는 macOS 에서는 available 이 false 이고, 창 바탕은 기본 유리(BehindWindowGlass)로 그린다
enum WindowBlur {
    private typealias SetRadius = @convention(c) (UInt32, UInt32, UInt32) -> Int32
    private typealias Connection = @convention(c) () -> UInt32
    private static let functions: (set: SetRadius, connection: Connection)? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let set = dlsym(handle, "CGSSetWindowBackgroundBlurRadius"),
              let connection = dlsym(handle, "CGSDefaultConnectionForThread") else { return nil }
        return (unsafeBitCast(set, to: SetRadius.self), unsafeBitCast(connection, to: Connection.self))
    }()

    static var available: Bool { functions != nil }

    /// 창 뒤를 radius 만큼 흐린다. 창 번호가 아직 없거나 함수가 없으면 false
    @discardableResult
    static func apply(_ radius: Int, to window: NSWindow) -> Bool {
        guard let functions, window.windowNumber > 0 else { return false }
        return functions.set(functions.connection(), UInt32(window.windowNumber), UInt32(radius)) == 0
    }
}

/// macOS 15부터 창 제목 글자를 숨기고 가운데 워드마크만 보이게 한다
private struct HideWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) { content.toolbar(removing: .title) } else { content }
    }
}

/// 업무 패널: sc2k 판정 항목처럼 창 오른쪽 끝에 세로 탭만 보이고, 탭에 커서를 대면 밀려 나온다.
/// 패널 밖으로 나가면 0.3초 뒤 닫히고(밀려 나오는 동안 커서가 탭을 벗어나도 안 닫히게), 탭을 누르면 열린 채 고정된다
struct TasksDock: View {
    static let width: CGFloat = 820                               // 업무 목록 276 + 상세. 창 최소 폭 900 안에 탭(30)까지 들어간다
    static let peek: CGFloat = 277                                // 1단계: 커서를 대면 업무 목록만, 누르면 상세까지 펼친다
    @State private var hover = false
    @State private var expanded = false
    @State private var pinned: Bool
    @State private var closing: Task<Void, Never>?

    /// pinned: 열린 채로 시작 (스냅샷용)
    init(pinned: Bool = false) { _pinned = State(initialValue: pinned) }

    private var open: Bool { hover || pinned }
    private var shown: CGFloat { expanded || pinned ? Self.width : Self.peek }

    var body: some View {
        HStack(spacing: 0) {
            Button { pinned.toggle() } label: {
                Capsule().fill(Brand.ink.opacity(open ? 0.35 : 0.18))   // 업무 손잡이: 화면 끝 가는 막대
                    .frame(width: 4, height: 56)
                    .frame(width: 16, height: 120)                     // 닿는 영역은 넉넉히
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover(perform: hovered)
            .help(pinned ? "누르면 고정을 풀어요" : "누르면 열린 채로 고정해요")
            .accessibilityLabel("업무 패널")
            TasksView()
                .frame(width: Self.width)
                .frame(width: shown, alignment: .leading)
                .clipped()
                .simultaneousGesture(TapGesture().onEnded { expanded = true })   // 2단계: 목록에서 업무를 누르면 상세까지
                .background {                                     // 흰 바탕: 업무 목록의 유리 뒤로 그래프가 비치지 않게. 그림자는 바탕에만(글자마다 번지지 않게)
                    Rectangle().fill(.white).shadow(color: .black.opacity(open ? 0.06 : 0), radius: 12, x: -8)
                }
                .overlay(alignment: .leading) { Rectangle().fill(Brand.line).frame(width: 1) }
                .overlay(alignment: .topTrailing) {                // 닫기: 고정도 풀고 바로 접는다 (Esc 도 같다)
                    Button { close() } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.tabText)
                            .frame(width: 26, height: 26).background(Circle().fill(Color.black.opacity(0.05))).contentShape(Circle())
                    }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction).help("업무 패널 닫기 (Esc)")
                    .padding(10)
                }
                .onHover(perform: hovered)
        }
        .offset(x: open ? 0 : shown)
        .animation(.easeOut(duration: 0.22), value: open)
        .animation(.easeOut(duration: 0.22), value: shown)
        .onChange(of: open) { _, isOpen in if !isOpen { expanded = false } }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private func close() { closing?.cancel(); pinned = false; hover = false; expanded = false }

    private func hovered(_ inside: Bool) {
        closing?.cancel()
        if inside { hover = true; return }
        closing = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled { hover = false }
        }
    }
}

struct MainWindow: View {
    enum Tab: String, CaseIterable, Identifiable {
        case graph = "그래프", chat = "채팅", settings = "설정"     // 업무는 오른쪽 패널(TasksDock), 파일·보관함·활동 로그는 설정 안 구역
        var id: String { rawValue }
    }

    @EnvironmentObject private var state: AppState
    /// WORKGRAPH_TAB=chat|settings 로 시작 탭을 고를 수 있다 (개발·스크린샷용).
    static let initialTab: Tab = {
        switch ProcessInfo.processInfo.environment["WORKGRAPH_TAB"] {
        case "settings": return .settings
        case "chat": return .chat
        default: return .graph                                   // 권한·로그인 안내는 온보딩이 맡는다
        }
    }()

    private var ready: Bool { state.startupError == nil && state.bootstrapped && state.phase == .ready }
    /// 기기 코드 로그인이 꺼진 계정: 탭 대신 OUT-W1 카드
    private var loginBlocked: Bool { state.loginBlocked && state.phase == .login }
    /// 시작 실패·불러오는 중·로그인 오류가 아니면 탭이 보이고, 온보딩은 그 위에 시트로 뜬다
    private var showsTabs: Bool { state.startupError == nil && state.bootstrapped && !loginBlocked }
    /// 온보딩 시트가 떠 있으면 시트 뒤 탭은 눌리지도(Return 같은 키보드 단축키 포함) 읽히지도 않는다
    private var sheetShown: Bool { showsTabs && state.onboardingStep != nil }

    var body: some View {
        HStack(spacing: 0) {
            if showsTabs { NavRail().zIndex(1) }   // 이름표가 옆 화면 위로 나오게
            Group {
                if let error = state.startupError {
                    BrandStartupErrorView(message: error)
                } else if !state.bootstrapped {
                    BrandLoadingView()
                } else if loginBlocked {
                    LoginBlockedView()
                } else {
                    switch state.selectedTab {
                    case .graph: GraphWebView(version: state.graphVersion).ignoresSafeArea(edges: .bottom)   // 웹 페이지의 빈 곳으로 창 바탕 유리가 보인다
                    case .chat: if let chat = state.chat {
                        ChatView(chat: chat, projects: chat.projects, library: chat.library, modelName: state.settings.chatModelName, openSettings: { state.selectedTab = .settings })
                    }
                    case .settings: SettingsView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { if ready { TasksDock() } }
        }
        .disabled(sheetShown)
        .accessibilityHidden(sheetShown)
        .overlay {
            if showsTabs, let step = state.onboardingStep { OnboardingOverlay(step: step) }
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(item: $state.resumeRequest) { request in ResumeSheet(request: request).environmentObject(state) }
        .toolbar {
            if showsTabs {
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.flexible)
                    ToolbarItem { TitleRefresh() }.sharedBackgroundVisibility(.hidden)   // 지금 정리: 창 머리 오른쪽 위
                } else {
                    ToolbarItem { TitleRefresh() }
                }
            }
        }
        .toolbarBackground(Color(hex: 0xEFECE9), for: .windowToolbar)
        .modifier(HideWindowTitle())
        .modifier(WindowGlassBackground())
        .task { await state.bootstrap() }
        .onChange(of: state.phase) { old, phase in
            // 온보딩을 막 끝냈을 때만 그래프 탭으로. 앱 시작 시의 login → ready 전환은 탭을 건드리지 않는다.
            if phase == .ready { state.refresh() }
            if phase == .ready, old == .permissions { state.selectedTab = .graph }
        }
        .onAppear { state.refresh() }
    }
}

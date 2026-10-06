import SwiftUI
import WorkGraphCore

/// 유리 탭 막대: 흰색 72% 위에 배경 흐림, 선택한 탭은 흰색 78% 알약
private struct BrandTabBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MainWindow.Tab.allCases) { tab in
                let on = state.selectedTab == tab
                Button { state.selectedTab = tab } label: {
                    HStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(Brand.suit(12, on ? .semibold : .regular))
                            .foregroundStyle(on ? Brand.ink : Brand.tabText)
                        if tab == .files, state.pendingFileSuggestions > 0 { FileBadge(count: state.pendingFileSuggestions) }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 35)
                    .glassPill(on)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 12)
            if state.batchRunning {
                HStack(spacing: 8) {                          // OUT-W5: 정리하는 동안 오른쪽 위에 회전 표시
                    ProgressView().controlSize(.mini)
                    Text("정리하는 중…").font(Brand.suit(12)).foregroundStyle(Brand.sub)
                }
            } else {
                Button { Task { await state.runBatch(force: true) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                        Text("지금 정리").font(Brand.suit(11))
                        if state.pendingCount > 0 {
                            Text("\(state.pendingCount)").font(Brand.jost(12)).foregroundStyle(Brand.gray)
                        }
                    }
                    .foregroundStyle(Brand.tabText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("아직 정리되지 않은 활동을 지금 바로 그래프에 반영합니다")
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 19)
        .frame(height: 54)
        .brandGlass()
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.hairline).frame(height: 1) }
    }
}

/// 파일 탭 옆 대기 중인 정리 제안 수 (Figma OUT-01 탭 막대: Jost 10, 하늘색 테두리)
private struct FileBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)").font(Brand.jost(10)).foregroundStyle(Brand.tabText)
            .padding(.horizontal, 5).frame(height: 17)
            .background(RoundedRectangle(cornerRadius: 4).fill(Brand.sky.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.sky))
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

struct MainWindow: View {
    enum Tab: String, CaseIterable, Identifiable {
        case graph = "그래프", tasks = "업무", files = "파일", library = "보관함", activity = "활동 로그", chat = "채팅", settings = "설정"
        var id: String { rawValue }
    }

    @EnvironmentObject private var state: AppState
    /// WORKGRAPH_TAB=activity|settings 로 시작 탭을 고를 수 있다 (개발·스크린샷용).
    static let initialTab: Tab = {
        switch ProcessInfo.processInfo.environment["WORKGRAPH_TAB"] {
        case "activity": return .activity
        case "files": return .files
        case "library": return .library
        case "tasks": return .tasks
        case "settings": return .settings
        case "graph": return .graph
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
        VStack(spacing: 0) {
            if showsTabs { BrandTabBar() }
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
                    case .tasks: TasksView()
                    case .files: FilesView()
                    case .library: if let chat = state.chat { LibraryView(library: chat.library, projects: chat.projects) }
                    case .activity: ActivityLogView()
                    case .chat: if let chat = state.chat {
                        ChatView(chat: chat, projects: chat.projects, library: chat.library, modelName: state.settings.chatModelName, openSettings: { state.selectedTab = .settings })
                    }
                    case .settings: SettingsView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .disabled(sheetShown)
        .accessibilityHidden(sheetShown)
        .overlay {
            if showsTabs, let step = state.onboardingStep { OnboardingOverlay(step: step) }
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(item: $state.resumeRequest) { request in ResumeSheet(request: request).environmentObject(state) }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let mark = Brand.wordmark {
                    Image(nsImage: mark).resizable().scaledToFit().frame(height: 16).accessibilityLabel("SILLOG")
                } else {
                    Text("SILLOG").font(Brand.suit(14, .semibold)).foregroundStyle(Brand.ink)
                }
            }
            if ready {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 7) {
                        Rectangle().fill(Brand.ink).frame(width: 6, height: 6)
                        Text(state.statusLine == "수집 중" ? "기록 중" : state.statusLine)
                            .font(Brand.suit(10))
                            .foregroundStyle(Brand.gray)
                    }
                }
            }
        }
        .toolbarBackground(Color.white, for: .windowToolbar)
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

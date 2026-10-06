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
                    Text(tab.rawValue)
                        .font(Brand.suit(12, on ? .semibold : .regular))
                        .foregroundStyle(on ? Brand.ink : Brand.tabText)
                        .padding(.horizontal, 14)
                        .frame(height: 35)
                        .glassPill(on)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 12)
            Button { Task { await state.runBatch(force: true) } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                    Text(state.batchRunning ? "정리하는 중…" : "지금 정리").font(Brand.suit(11))
                    if state.pendingCount > 0 {
                        Text("\(state.pendingCount)").font(Brand.jost(12)).foregroundStyle(Brand.gray)
                    }
                }
                .foregroundStyle(Brand.tabText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.batchRunning)
            .help("아직 정리되지 않은 활동을 지금 바로 그래프에 반영합니다")
        }
        .padding(.leading, 13)
        .padding(.trailing, 19)
        .frame(height: 54)
        .background(.white.opacity(0.3))
        .background(BehindWindowGlass())
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.hairline).frame(height: 1) }
    }
}

/// 창 바탕을 반투명 유리로: 흰색을 직접 칠하지 않은 사이드바와 탭 막대 뒤로 바탕화면이 비친다(마누스 시제품과 같은 구조)
private struct WindowGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) { content.containerBackground(.thinMaterial, for: .window) } else { content.background(BehindWindowGlass()) }
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

    var body: some View {
        VStack(spacing: 0) {
            if ready { BrandTabBar() }                         // 온보딩 중에는 탭을 숨긴다
            Group {
                if let error = state.startupError {
                    BrandStartupErrorView(message: error)
                } else if !state.bootstrapped {
                    BrandLoadingView()
                } else if state.phase != .ready {
                    OnboardingView()
                } else {
                    switch state.selectedTab {
                    case .graph: GraphWebView(version: state.graphVersion).background(BehindWindowGlass()).ignoresSafeArea(edges: .bottom)
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

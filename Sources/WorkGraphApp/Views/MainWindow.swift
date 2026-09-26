import SwiftUI
import WorkGraphCore

struct MainWindow: View {
    enum Tab: String, CaseIterable, Identifiable {
        case graph = "그래프", tasks = "업무", files = "파일", activity = "활동 로그", chat = "채팅", settings = "설정"
        var id: String { rawValue }
    }

    @EnvironmentObject private var state: AppState
    /// WORKGRAPH_TAB=activity|settings 로 시작 탭을 고를 수 있다 (개발·스크린샷용).
    static let initialTab: Tab = {
        switch ProcessInfo.processInfo.environment["WORKGRAPH_TAB"] {
        case "activity": return .activity
        case "files": return .files
        case "tasks": return .tasks
        case "settings": return .settings
        case "graph": return .graph
        case "chat": return .chat
        default: return .graph                                   // 권한·로그인 안내는 온보딩이 맡는다
        }
    }()
    var body: some View {
        Group {
            if let error = state.startupError {
                ContentUnavailableView("시작하지 못했습니다", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if !state.bootstrapped {
                ProgressView()
            } else if state.phase != .ready {
                OnboardingView()
            } else {
                switch state.selectedTab {
                case .graph: GraphWebView(version: state.graphVersion).ignoresSafeArea(edges: .bottom)
                case .tasks: TasksView()
                case .files: FilesView()
                case .activity: ActivityLogView()
                case .chat: if let chat = state.chat {
                    ChatView(chat: chat, modelName: state.settings.chatModelName, openSettings: { state.selectedTab = .settings })
                }
                case .settings: SettingsView()
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(item: $state.resumeRequest) { request in ResumeSheet(request: request).environmentObject(state) }
        .toolbar {
            if state.phase == .ready {                      // 온보딩 중에는 탭과 버튼을 숨긴다
                ToolbarItem(placement: .principal) {
                    Picker("화면", selection: $state.selectedTab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(state.batchRunning ? "정리하는 중…" : "지금 정리") { Task { await state.runBatch(force: true) } }
                        .disabled(state.batchRunning)
                        .help("아직 정리되지 않은 활동을 지금 바로 그래프에 반영합니다")
                }
            }
        }
        .task { await state.bootstrap() }
        .onChange(of: state.phase) { old, phase in
            // 온보딩을 막 끝냈을 때만 그래프 탭으로. 앱 시작 시의 login → ready 전환은 탭을 건드리지 않는다.
            if phase == .ready { state.refresh() }
            if phase == .ready, old == .permissions { state.selectedTab = .graph }
        }
        .onAppear { state.refresh() }
    }
}

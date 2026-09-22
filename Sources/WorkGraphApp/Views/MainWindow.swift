import SwiftUI
import WorkGraphCore

struct MainWindow: View {
    enum Tab: String, CaseIterable, Identifiable {
        case graph = "그래프", activity = "활동 로그", settings = "설정"
        var id: String { rawValue }
    }

    @EnvironmentObject private var state: AppState
    /// WORKGRAPH_TAB=activity|settings 로 시작 탭을 고를 수 있다 (개발·스크린샷용).
    static let initialTab: Tab = {
        switch ProcessInfo.processInfo.environment["WORKGRAPH_TAB"] {
        case "activity": return .activity
        case "settings": return .settings
        case "graph": return .graph
        default: return .graph                                   // 권한·로그인 안내는 온보딩이 맡는다
        }
    }()
    @State private var tab: Tab = MainWindow.initialTab

    var body: some View {
        Group {
            if let error = state.startupError {
                ContentUnavailableView("시작하지 못했습니다", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if !state.bootstrapped {
                ProgressView()
            } else if state.phase != .ready {
                OnboardingView()
            } else {
                switch tab {
                case .graph: GraphWebView(version: state.graphVersion).ignoresSafeArea(edges: .bottom)
                case .activity: ActivityLogView()
                case .settings: SettingsView()
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .toolbar {
            if state.phase == .ready {                      // 온보딩 중에는 탭과 버튼을 숨긴다
                ToolbarItem(placement: .principal) {
                    Picker("화면", selection: $tab) {
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
            if phase == .ready, old == .permissions { tab = .graph }
        }
        .onAppear { state.refresh() }
    }
}

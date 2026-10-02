import SwiftUI
import WorkGraphCore

/// 업무 탭: 업무 목록 → 세션 목록 → 다시 열기
struct TasksView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedTask: Int64?
    @State private var sessions: [SessionSummary] = []

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedTask) {
                    ForEach(state.taskList) { task in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title).lineLimit(1)
                            if let projects = state.chat?.projects { ProjectAssignmentLabel(projects: projects, itemID: "task:\(task.id)") }
                            Text("\(Self.duration(task.activeSeconds)) · 세션 \(task.sessionCount)개 · \(Self.day.string(from: Date(timeIntervalSince1970: task.lastActive)))")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(task.id)
                        .contextMenu {
                            if let projects = state.chat?.projects {
                                ProjectMoveMenu(projects: projects, itemID: "task:\(task.id)")
                            }
                        }
                    }
                }
                if !state.offTaskToday.isEmpty {
                    Divider()
                    // 업무 외(집중 이탈): 업무·세션·자료 없이 시간만. 어떤 목표에도 기여하지 않았다고 판단된 행들
                    let total = state.offTaskToday.reduce(0) { $0 + $1.seconds }
                    let top = state.offTaskToday.prefix(3).map { "\($0.app) \(Self.duration($0.seconds))" }.joined(separator: ", ")
                    Text("업무 외 오늘 \(Self.duration(total)) · \(top)")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)

            Group {
                if let task = state.taskList.first(where: { $0.id == selectedTask }) {
                    sessionList(task)
                } else {
                    ContentUnavailableView("업무를 고르세요", systemImage: "list.bullet.rectangle", description: Text("세션마다 그때 열었던 파일·페이지·앱을 다시 열 수 있습니다."))
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { state.refreshTasks(); reload() }
        .onChange(of: selectedTask) { _, _ in reload() }
        .onChange(of: state.graphVersion) { _, _ in state.refreshTasks(); reload() }
    }

    private func sessionList(_ task: TaskSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.title3.weight(.semibold))
                    Text([task.taskType, Self.duration(task.activeSeconds)].compactMap { $0 }.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("업무 다시 열기") { state.prepareResume(taskId: task.id) }.buttonStyle(.borderedProminent)
            }
            .padding(16)
            Divider()
            List(sessions) { session in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.day.string(from: Date(timeIntervalSince1970: session.start)) + (session.end > session.start ? " – " + Self.clock.string(from: Date(timeIntervalSince1970: session.end)) : ""))
                        Text(Self.duration(max(0, session.end - session.start))).font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(width: 130, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        if session.summaries.isEmpty {
                            Text(session.title).lineLimit(2)
                        } else {
                            ForEach(Array(session.summaries.prefix(4).enumerated()), id: \.offset) { _, line in
                                Text("· " + line).lineLimit(2)
                            }
                            if session.summaries.count > 4 { Text("외 \(session.summaries.count - 4)개").font(.callout).foregroundStyle(.secondary) }
                        }
                        Text((session.apps.joined(separator: ", ") + (session.resourceCount > 0 ? " · 자료 \(session.resourceCount)개" : "")).trimmingCharacters(in: .whitespaces))
                            .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("다시 열기") { state.prepareResume(sessionId: session.id) }.controlSize(.small)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func reload() { sessions = selectedTask.map { state.sessions(ofTask: $0) } ?? [] }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)시간 \(minutes % 60)분" : "\(max(minutes, seconds > 0 ? 1 : 0))분"
    }
}

/// 열 것을 확인하는 시트
struct ResumeSheet: View {
    @EnvironmentObject private var state: AppState
    @State private var request: ResumeRequest
    /// 처음 켜져 있던 것. 체크를 바꿔도 칸이 옮겨 다니지 않게 고정한다
    private let initiallySelected: Set<String>

    init(request: ResumeRequest) {
        _request = State(initialValue: request)
        initiallySelected = Set(request.plan.items.filter(\.selected).map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("다시 열기").font(.headline)
            Text(request.plan.title).lineLimit(2)
            if request.plan.items.isEmpty {
                Text("다시 열 수 있는 파일이나 페이지가 남아 있지 않습니다.").foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                List {
                    Section("마지막에 하던 것") {
                        ForEach($request.plan.items) { $item in
                            if initiallySelected.contains(item.id) { row($item) }
                        }
                    }
                    if request.plan.items.contains(where: { !initiallySelected.contains($0.id) }) {
                        Section("그때 함께 열었던 것") {
                            ForEach($request.plan.items) { $item in
                                if !initiallySelected.contains(item.id) { row($item) }
                            }
                        }
                    }
                }
                .frame(minHeight: 220, maxHeight: 400)
            }
            HStack {
                Spacer()
                Button("취소") { state.resumeRequest = nil }.keyboardShortcut(.cancelAction)
                Button("열기 (\(request.plan.selectedItems.count)개)") { state.runResume(request.plan) }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(request.plan.selectedItems.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func row(_ item: Binding<ResumePlan.Item>) -> some View {
        Toggle(isOn: item.selected) {
            HStack(spacing: 8) {
                Image(systemName: icon(item.wrappedValue.kind)).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.wrappedValue.title).lineLimit(1)
                    Text(detail(item.wrappedValue)).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }

    private func icon(_ kind: ResumePlan.Kind) -> String {
        switch kind {
        case .folder: return "folder"
        case .file: return "doc"
        case .url: return "globe"
        case .app: return "app"
        }
    }

    private func detail(_ item: ResumePlan.Item) -> String {
        let home = NSHomeDirectory()
        let target = item.target.hasPrefix(home) ? "~" + item.target.dropFirst(home.count) : item.target
        let app = item.appBundle.flatMap { bundle in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
        }
        if item.kind == .app { return "앱 열기" }
        return app.map { "\($0) · \(target)" } ?? target
    }
}

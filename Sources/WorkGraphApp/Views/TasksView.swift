import SwiftUI
import WorkGraphCore

/// 업무 탭: 왼쪽 업무 트리(분야 폴더 안에 업무), 오른쪽 업무 상세(세션 목록과 다시 열기). Figma 참고 TK-01, TK-02, TK-W1
struct TasksView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedTask: Int64?
    @State private var collapsed: Set<String> = []          // 접은 분야 폴더
    @State private var sessions: [SessionSummary] = []

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter
    }()
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 276)
            Rectangle().fill(Brand.hairline).frame(width: 1)
            Group {
                if state.taskList.isEmpty {
                    emptyState
                } else if let task = state.taskList.first(where: { $0.id == selectedTask }) {
                    detail(task)
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white)
        }
        .onAppear { state.refreshTasks(); reload() }
        .onChange(of: selectedTask) { _, _ in reload() }
        .onChange(of: state.graphVersion) { _, _ in state.refreshTasks(); reload() }
    }

    // MARK: 왼쪽 목록 (분야 폴더 안에 업무, 파일 트리처럼)

    struct TaskFolder: Identifiable, Equatable {
        let name: String
        let tasks: [TaskSummary]
        var id: String { name }
        var seconds: Double { tasks.reduce(0) { $0 + $1.activeSeconds } }
    }

    static let noField = "분야 없음"

    /// 분야별 폴더: 최근에 일한 분야가 위, '분야 없음' 은 늘 맨 아래. 폴더 안은 받은 순서(최근 활동 순) 그대로
    static func folders(_ tasks: [TaskSummary]) -> [TaskFolder] {
        var order: [String] = [], groups: [String: [TaskSummary]] = [:]
        for task in tasks {
            let name = task.theme ?? noField
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(task)
        }
        let latest = { (name: String) in groups[name]?.map(\.lastActive).max() ?? 0 }
        return order.sorted { a, b in
            if (a == noField) != (b == noField) { return b == noField }
            return latest(a) > latest(b)
        }
        .map { TaskFolder(name: $0, tasks: groups[$0] ?? []) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("YOUR WORK")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("업무").font(Brand.suit(23, .semibold)).tracking(-0.8).foregroundStyle(Brand.ink)
                    Text("\(state.taskList.count)").font(.custom("Jost-Light", size: 19)).foregroundStyle(Brand.gray)
                }
                .padding(.top, 8)
                Text("흩어진 기록을 하나의 흐름으로").font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.top, 8)
            }
            .padding(.horizontal, 24).padding(.top, 27).padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.taskList.isEmpty {
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Self.folders(state.taskList)) { folder in
                            folderRow(folder)
                            if !collapsed.contains(folder.name) {
                                ForEach(folder.tasks) { task in taskRow(task) }
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
            Rectangle().fill(Brand.hairline).frame(height: 1)
            HStack(spacing: 7) {
                Rectangle().fill(Brand.ink).frame(width: 4, height: 4)
                Text("이 Mac에 저장된 업무 기록").font(Brand.suit(9)).foregroundStyle(Brand.gray)
            }
            .padding(.horizontal, 24).frame(height: 37)
        }
        .brandGlass()
        .overlay(alignment: .trailing) { Rectangle().fill(Brand.hairline).frame(width: 1) }
    }

    /// 폴더 줄: 펼침 화살표, 폴더, 분야 이름, 업무 수. 누르면 접고 펼친다
    private func folderRow(_ folder: TaskFolder) -> some View {
        let open = !collapsed.contains(folder.name)
        return Button {
            if open { collapsed.insert(folder.name) } else { collapsed.remove(folder.name) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Brand.gray)
                    .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 10)
                Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Brand.tabText).frame(width: 16)
                Text(folder.name).font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink).lineLimit(1)
                Spacer(minLength: 6)
                Text("\(folder.tasks.count)").font(.custom("Jost-Light", size: 13)).foregroundStyle(Brand.gray)
            }
            .padding(.horizontal, 8).frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(folder.name) 분야, 업무 \(folder.tasks.count)개, \(open ? "펼침" : "접힘")")
        .padding(.top, 6)
    }

    /// 업무 줄: 폴더 안으로 들여 문서처럼. 제목과 작업 시간, 아래에 작은 종류 (세션 수·마지막 활동은 오른쪽 상세에)
    private func taskRow(_ task: TaskSummary) -> some View {
        let on = task.id == selectedTask
        return Button { selectedTask = task.id } label: {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(on ? Brand.ink : Brand.gray)
                    .frame(width: 16).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(task.title).font(Brand.suit(12)).foregroundStyle(Brand.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Self.duration(task.activeSeconds)).font(Brand.suit(10)).foregroundStyle(Brand.tabText).fixedSize()
                    }
                    if let type = task.taskType { Text(type).font(Brand.suit(9)).foregroundStyle(Brand.gray) }
                    if let projects = state.chat?.projects { ProjectAssignmentLabel(projects: projects, itemID: "task:\(task.id)") }
                }
            }
            .padding(.leading, 25).padding(.trailing, 10).padding(.vertical, 8)          // 폴더 아이콘 아래로 들여쓰기
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.64)) : nil)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(on ? Brand.hairline : .clear))
            .overlay(alignment: .leading) { if on { Rectangle().fill(Brand.ink).frame(width: 2).padding(.vertical, 8) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let projects = state.chat?.projects { ProjectMoveMenu(projects: projects, itemID: "task:\(task.id)") }
        }
    }

    // MARK: 오른쪽 상세

    /// TK-W5: 업무가 하나도 없을 때
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("아직 업무가 없어요").font(Brand.suit(20, .bold)).foregroundStyle(Brand.ink)
            Text("활동이 쌓여 정리되면 업무가 여기에 모여요. 지금 바로 정리할 수도 있어요.").font(Brand.suit(14)).foregroundStyle(Brand.gray)
            Button("지금 정리") { Task { await state.runBatch(force: true) } }
                .buttonStyle(BrandButtonStyle(kind: .primary))
                .disabled(state.batchRunning).opacity(state.batchRunning ? 0.4 : 1)
                .padding(.top, 16)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.3.stack.3d").font(.system(size: 30, weight: .light)).foregroundStyle(Brand.sub)
            Text("업무를 골라 주세요").font(Brand.suit(20, .bold)).foregroundStyle(Brand.ink).padding(.top, 8)
            Text("세션마다 그때 열었던 파일, 페이지, 앱을 다시 열 수 있어요.").font(Brand.suit(14)).foregroundStyle(Brand.gray)
        }
    }

    private func detail(_ task: TaskSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Eyebrow("WORK CONTEXT")
                        if let type = task.taskType { BrandBadge(type) }
                    }
                    Text(task.title).font(Brand.suit(28, .semibold)).tracking(-1.26).foregroundStyle(Brand.ink).lineLimit(1).padding(.top, 14)
                }
                Spacer(minLength: 16)
                Button { state.prepareResume(taskId: task.id) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 12))
                        Text("다시 열기")
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(BrandButtonStyle(kind: .primary))
            }
            .padding(.horizontal, 33).padding(.vertical, 30)
            .frame(height: 155)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }

            if !state.offTaskToday.isEmpty {
                // 업무 외(집중 이탈): 업무, 세션, 자료 없이 시간만
                let total = state.offTaskToday.reduce(0) { $0 + $1.seconds }
                let top = state.offTaskToday.prefix(3).map { "\($0.app) \(Self.duration($0.seconds))" }.joined(separator: ", ")
                Text("업무 외 오늘 \(Self.duration(total)), \(top)")
                    .font(Brand.suit(11)).foregroundStyle(Brand.gray).lineLimit(1)
                    .padding(.horizontal, 33).frame(height: 44, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    stats(task)
                    HStack(alignment: .firstTextBaseline) {
                        HStack(spacing: 6) {
                            Text("작업 세션").font(Brand.suit(14)).foregroundStyle(Brand.ink)
                            Text("\(sessions.count)").font(Brand.jost(12)).foregroundStyle(Brand.gray)
                        }
                        Spacer()
                        Text("최근 활동 순").font(Brand.suit(10)).foregroundStyle(Brand.gray)
                    }
                    .padding(.vertical, 23)
                    if sessions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.3.stack.3d").font(.system(size: 26, weight: .light)).foregroundStyle(Brand.gray)
                            Text("아직 기록된 세션이 없어요").font(Brand.suit(17, .medium)).foregroundStyle(Brand.ink).padding(.top, 6)
                            Text("이 업무의 활동이 기록되면 시간과 사용한 자료를 함께 보여 드려요.").font(Brand.suit(12)).foregroundStyle(Brand.gray)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            sessionRow(session, first: index == 0, last: index == sessions.count - 1)
                        }
                    }
                }
                .padding(.horizontal, 33).padding(.bottom, 24)
            }
        }
    }

    private func stats(_ task: TaskSummary) -> some View {
        let minutes = Int(task.activeSeconds / 60)
        return HStack(alignment: .top, spacing: 0) {
            statCell("TIME SPENT", note: "누적 작업 시간", leading: false) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if minutes >= 60 {
                        bigNumber("\(minutes / 60)"); unit("시간")
                        bigNumber("\(minutes % 60)").padding(.leading, 6); unit("분")
                    } else {
                        bigNumber("\(minutes)"); unit("분")
                    }
                }
            }
            statCell("SESSIONS", note: "이어진 작업 세션", leading: true) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    bigNumber(String(format: "%02d", task.sessionCount)); unit("개")
                }
            }
            statCell("LAST ACTIVITY", note: "내 업무 기록", leading: true) {
                Text(task.sessionCount == 0 ? "활동 없음" : Self.lastActive(task.lastActive))
                    .font(Brand.suit(17)).foregroundStyle(Brand.ink).frame(height: 60)
            }
        }
        .padding(.top, 28).padding(.bottom, 28)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    private func bigNumber(_ text: String) -> some View {
        Text(text).font(.custom("Jost-ExtraLight", size: 48)).foregroundStyle(Brand.ink)
    }
    private func unit(_ text: String) -> some View {
        Text(text).font(Brand.suit(11)).foregroundStyle(Brand.gray)
    }

    private func statCell<Content: View>(_ eyebrow: String, note: String, leading: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(eyebrow)
            content().frame(height: 60, alignment: .leading)
            Text(note).font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 0)
        }
        .padding(.leading, leading ? 29 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { if leading { Rectangle().fill(Brand.line).frame(width: 1) } }
    }

    private func sessionRow(_ session: SessionSummary, first: Bool, last: Bool) -> some View {
        let start = Date(timeIntervalSince1970: session.start)
        let range = Self.clock.string(from: start) + (session.end > session.start ? " — " + Self.clock.string(from: Date(timeIntervalSince1970: session.end)) : "")
        let meta = [session.apps.joined(separator: ", "), session.resourceCount > 0 ? "자료 \(session.resourceCount)개" : ""].filter { !$0.isEmpty }
        return HStack(alignment: .top, spacing: 18) {
            ZStack(alignment: .top) {
                if !last { Rectangle().fill(Brand.line).frame(width: 1).padding(.top, 7) }
                RoundedRectangle(cornerRadius: 1).fill(first ? Brand.ink : .white)
                    .overlay(RoundedRectangle(cornerRadius: 1).strokeBorder(first ? Brand.ink : Color(hex: 0xBDB5AE)))
                    .frame(width: 7, height: 7).padding(.top, 7)
            }
            .frame(width: 9)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Text(Self.dayLabel(start)).font(Brand.suit(11, .medium)).foregroundStyle(Brand.tabText)
                    Text(range).font(Brand.jost(12)).tracking(0.18).foregroundStyle(Brand.gray)
                    Spacer()
                    Text(Self.duration(max(0, session.end - session.start))).font(Brand.suit(12)).foregroundStyle(Brand.tabText)
                }
                if session.summaries.isEmpty {
                    Text(session.title).font(Brand.suit(13)).foregroundStyle(Brand.tabText).lineLimit(2).padding(.top, 11)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(session.summaries.prefix(4).enumerated()), id: \.offset) { _, line in
                            Text(line).font(Brand.suit(13)).foregroundStyle(Brand.tabText).lineLimit(2)
                        }
                        if session.summaries.count > 4 { Text("외 \(session.summaries.count - 4)개").font(Brand.suit(10)).foregroundStyle(Brand.gray) }
                    }
                    .padding(.top, 11)
                }
                HStack {
                    Text(meta.joined(separator: "   |   ")).font(Brand.suit(10)).foregroundStyle(Brand.gray).lineLimit(1)
                    Spacer()
                    Button { state.prepareResume(sessionId: session.id) } label: {
                        HStack(spacing: 6) {
                            Text("다시 열기").font(Brand.suit(11))
                            Image(systemName: "arrow.up.right").font(.system(size: 10))
                        }
                        .foregroundStyle(Brand.tabText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)
            }
            .padding(.bottom, 26)
        }
    }

    private func reload() { sessions = selectedTask.map { state.sessions(ofTask: $0) } ?? [] }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)시간 \(minutes % 60)분" : "\(max(minutes, seconds > 0 ? 1 : 0))분"
    }

    private static func dayLabel(_ date: Date) -> String {
        (Calendar.current.isDateInToday(date) ? "오늘, " : "") + day.string(from: date)
    }

    private static func lastActive(_ stamp: Double) -> String {
        let date = Date(timeIntervalSince1970: stamp)
        return (Calendar.current.isDateInToday(date) ? "오늘" : day.string(from: date)) + " " + clock.string(from: date)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("RESUME")
                    Text("다시 열기").font(Brand.suit(22, .bold)).foregroundStyle(Brand.ink).padding(.top, 8)
                    Text(request.plan.title).font(Brand.suit(12)).foregroundStyle(Brand.gray).lineLimit(2).padding(.top, 10)
                }
                Spacer()
                Button { state.resumeRequest = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(Brand.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32).padding(.top, 26).padding(.bottom, 20)
            Rectangle().fill(Brand.line).frame(height: 1)
            if request.plan.items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "square.3.stack.3d").font(.system(size: 26, weight: .light)).foregroundStyle(Brand.sub)
                    Text("다시 열 수 있는 파일이나 페이지가 남아 있지 않아요.").font(Brand.suit(13)).foregroundStyle(Brand.gray)
                }
                .frame(maxWidth: .infinity, minHeight: 195)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        group("마지막에 하던 것", selected: true)
                        if request.plan.items.contains(where: { !initiallySelected.contains($0.id) }) {
                            group("그때 함께 열었던 것", selected: false)
                        }
                    }
                    .padding(.horizontal, 32).padding(.vertical, 6)
                }
                .frame(minHeight: 220, maxHeight: 375)
            }
            Rectangle().fill(Brand.line).frame(height: 1)
            HStack(spacing: 8) {
                Spacer()
                Button("취소") { state.resumeRequest = nil }.keyboardShortcut(.cancelAction)
                    .buttonStyle(BrandButtonStyle(kind: .secondary))
                Button("열기 (\(request.plan.selectedItems.count)개)") { state.runResume(request.plan) }
                    .keyboardShortcut(.defaultAction).buttonStyle(BrandButtonStyle(kind: .primary))
                    .disabled(request.plan.selectedItems.isEmpty)
                    .opacity(request.plan.selectedItems.isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 24).frame(height: 63)
            .background(Color(hex: 0xF6F5F4))
        }
        .frame(width: 600)
        .background(.white)
    }

    private func group(_ title: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.gray).padding(.top, 14).padding(.bottom, 8)
            ForEach($request.plan.items) { $item in
                if initiallySelected.contains(item.id) == selected { row($item) }
            }
        }
    }

    private func row(_ item: Binding<ResumePlan.Item>) -> some View {
        let on = item.wrappedValue.selected
        return Button { item.selected.wrappedValue.toggle() } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 3).fill(on ? Brand.ink : .white)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(on ? Brand.ink : Brand.line))
                    .overlay { if on { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white) } }
                    .frame(width: 14, height: 14)
                Image(systemName: icon(item.wrappedValue.kind)).font(.system(size: 12)).foregroundStyle(Brand.gray).frame(width: 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.wrappedValue.title).font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink).lineLimit(1)
                    Text(detail(item.wrappedValue)).font(Brand.suit(11)).foregroundStyle(Brand.gray).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        return app.map { "\($0), \(target)" } ?? target
    }
}

/// TK-W4 업무 불러오는 중. AppState에 상태가 생기면 쓴다
private struct TasksLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("업무를 불러오고 있어요").font(Brand.suit(14)).foregroundStyle(Brand.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// TK-W6 업무를 불러오지 못할 때. AppState에 상태가 생기면 쓴다
private struct TasksErrorView: View {
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Text("업무를 불러오지 못했어요").font(Brand.suit(20, .bold)).foregroundStyle(Brand.ink)
            Text("기록을 읽는 중에 문제가 생겼어요. 잠시 뒤 다시 시도해 주세요.").font(Brand.suit(14)).foregroundStyle(Brand.gray)
            Button("다시 시도", action: retry).buttonStyle(BrandButtonStyle(kind: .secondary)).padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

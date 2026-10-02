import SwiftUI
import WorkGraphCore

struct ProjectMoveMenu: View {
    @ObservedObject var projects: ProjectState
    var itemID: String
    private var currentProjectID: String? { projects.items.first(where: { $0.id == itemID })?.projectID }

    var body: some View {
        Menu("프로젝트로 옮기기") {
            ForEach(projects.projects) { project in
                Button(project.title) { projects.move(itemID, to: project.id) }
                    .disabled(project.id == currentProjectID)
            }
            Divider()
            Button(itemID.hasPrefix("task:") ? "프로젝트에서 빼기" : "일반 채팅으로 옮기기") {
                projects.move(itemID, to: nil)
            }.disabled(currentProjectID == nil)
        }
    }
}

struct ProjectAssignmentLabel: View {
    @ObservedObject var projects: ProjectState
    var itemID: String

    var body: some View {
        if let id = projects.items.first(where: { $0.id == itemID })?.projectID,
           let project = projects.projects.first(where: { $0.id == id }) {
            Label(project.title, systemImage: "folder").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct ProjectOverview<Composer: View>: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var projects: ProjectState
    @ObservedObject var chat: ChatState
    var project: ChatProject
    var onConversation: (ChatConversation) -> Void
    var composer: Composer
    @State private var tab = "채팅"
    @State private var sourceKind = ""
    @State private var newestFirst = true
    @State private var hoveredConversation: String?
    @State private var name = ""
    @State private var showRename = false
    @State private var showDelete = false
    @State private var showSettings = false

    private var conversations: [ChatConversation] { chat.conversations.filter { $0.projectID == project.id } }
    private var tasks: [ProjectItem] { projects.items.filter { $0.projectID == project.id && $0.isTask } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 14) {
                    Image(systemName: "folder").font(.system(size: 28, weight: .regular))
                    Text(project.title).font(.system(size: 26, weight: .medium)).lineLimit(2)
                    Spacer(minLength: 12)
                    Menu {
                        Button("프로젝트 설정") { showSettings = true }.disabled(chat.running)
                        Button("이름 바꾸기") { name = project.title; showRename = true }
                        Divider()
                        Button("프로젝트 삭제", role: .destructive) { showDelete = true }.disabled(chat.running)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 16))
                            .frame(width: 36, height: 36)
                            .background(Color.primary.opacity(0.035), in: Circle())
                            .overlay(Circle().stroke(Color.primary.opacity(0.1)))
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help("프로젝트 메뉴").accessibilityLabel("프로젝트 메뉴")
                }
                composer
                HStack(spacing: 8) {
                    ForEach(["채팅", "소스"], id: \.self) { value in
                        Button { tab = value } label: {
                            Text(value).font(.system(size: 14, weight: tab == value ? .medium : .regular))
                                .foregroundStyle(tab == value ? Color.primary : Color.secondary)
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(tab == value ? Color.primary.opacity(0.06) : .clear, in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(tab == value ? .isSelected : [])
                    }
                    Spacer()
                    if tab == "소스" {
                        Menu(newestFirst ? "최신순" : "오래된순") {
                            Button("최신순") { newestFirst = true }
                            Button("오래된순") { newestFirst = false }
                        }.menuStyle(.borderlessButton).fixedSize()
                        Menu(sourceKindTitle) {
                            Button("전체") { sourceKind = "" }
                            Button("업로드") { sourceKind = "upload" }
                            Button("생성한 파일") { sourceKind = "generated" }
                            Button("저장한 답변") { sourceKind = "note" }
                            Button("폴더 연결") { sourceKind = "folder" }
                        }.menuStyle(.borderlessButton).fixedSize().padding(.leading, 12)
                    }
                }.padding(.top, 4)
                if tab == "채팅" { conversationList }
                else { ProjectSourcesView(library: chat.library, projects: projects, project: project, kind: $sourceKind, newestFirst: $newestFirst) }
                if let error = projects.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                if let error = chat.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            }.frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 40).padding(.top, 54).padding(.bottom, 40)
                .frame(maxWidth: .infinity)
        }.background(Color(nsColor: .textBackgroundColor))
        .sheet(isPresented: $showSettings) { ProjectEditor(projects: projects, project: project) { _ in } }
        .alert("프로젝트 이름 바꾸기", isPresented: $showRename) {
            TextField("프로젝트 이름", text: $name)
            Button("취소", role: .cancel) {}
            Button("저장") { projects.rename(project, title: name) }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("프로젝트를 삭제할까요?", isPresented: $showDelete) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) { projects.delete(project) }
        } message: { Text("업무·대화·파일은 남으며, 프로젝트로 묶인 상태만 해제됩니다.") }
    }

    private var sourceKindTitle: String {
        switch sourceKind {
        case "upload": return "업로드"
        case "generated": return "생성한 파일"
        case "note": return "저장한 답변"
        case "folder": return "폴더 연결"
        default: return "전체"
        }
    }

    private var conversationList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if conversations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("첫 채팅을 시작해보세요").font(.system(size: 16, weight: .medium))
                    Text("위 입력창에서 질문하면 이 프로젝트에 새 채팅이 만들어집니다.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }.padding(.vertical, 32).padding(.horizontal, 16)
            }
            ForEach(conversations) { conversation in
                HStack(spacing: 12) {
                    Button { onConversation(conversation) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(conversation.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                            let preview = chat.conversationPreviews[conversation.id, default: ""]
                            if !preview.isEmpty {
                                Text(preview.replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 17)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Text(Date(timeIntervalSince1970: conversation.updatedAt), format: .dateTime.month().day())
                        .font(.system(size: 12)).foregroundStyle(.tertiary)
                    Menu {
                        ProjectMoveMenu(projects: projects, itemID: "conversation:\(conversation.id)")
                            .disabled(chat.activeMessage?.conversationID == conversation.id)
                    } label: { Image(systemName: "ellipsis").frame(width: 24, height: 28) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .opacity(hoveredConversation == conversation.id ? 1 : 0)
                        .accessibilityLabel("\(conversation.title) 채팅 메뉴")
                }.padding(.horizontal, 16)
                    .background(hoveredConversation == conversation.id ? Color.primary.opacity(0.025) : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .onHover { hoveredConversation = $0 ? conversation.id : nil }
                    .contextMenu {
                        ProjectMoveMenu(projects: projects, itemID: "conversation:\(conversation.id)")
                            .disabled(chat.activeMessage?.conversationID == conversation.id)
                    }
                Divider().opacity(0.45).padding(.horizontal, 16)
            }
            if !tasks.isEmpty {
                DisclosureGroup {
                    ForEach(tasks) { item in
                        HStack(spacing: 12) {
                            Label(item.title, systemImage: "checklist").font(.system(size: 13))
                            Spacer()
                            if let id = Int64(item.id.dropFirst(5)) {
                                Button("다시 열기") { state.prepareResume(taskId: id) }.buttonStyle(.plain).font(.system(size: 12))
                            }
                            Menu { ProjectMoveMenu(projects: projects, itemID: item.id) } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        }.padding(.vertical, 9)
                    }
                } label: { Text("연결된 업무 \(tasks.count)").font(.system(size: 13)).foregroundStyle(.secondary) }
                    .padding(.horizontal, 16).padding(.top, 28)
            }
        }
    }
}

struct ProjectEditor: View {
    @ObservedObject var projects: ProjectState
    let project: ChatProject?
    var onSave: (ChatProject) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var goal: String
    @State private var instructions: String
    @State private var memoryMode: ProjectMemoryMode
    @State private var paths: [String] = []
    @State private var showDetails: Bool
    @State private var showMemory = false

    init(projects: ProjectState, project: ChatProject? = nil, onSave: @escaping (ChatProject) -> Void) {
        self.projects = projects; self.project = project; self.onSave = onSave
        _title = State(initialValue: project?.title ?? ""); _goal = State(initialValue: project?.goal ?? "")
        _instructions = State(initialValue: project?.instructions ?? ""); _memoryMode = State(initialValue: project?.memoryMode ?? .allRecords)
        _showDetails = State(initialValue: project != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(project == nil ? "프로젝트 만들기" : "프로젝트 설정").font(.system(size: 24, weight: .medium))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15)).frame(width: 28, height: 28) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("닫기")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("프로젝트 이름").font(.system(size: 14, weight: .medium))
                        HStack(spacing: 12) {
                            Image(systemName: "folder").font(.system(size: 20))
                            TextField("프로젝트 이름을 입력하세요", text: $title).textFieldStyle(.plain).font(.system(size: 15))
                        }.padding(14).background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12)))
                    }
                    if project == nil {
                        folderSelection
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lightbulb").font(.system(size: 22)).padding(.top, 2)
                            Text("채팅, 파일, 공통 지침을 한곳에 모아두세요. 프로젝트의 모든 채팅에서 함께 활용할 수 있습니다.")
                                .font(.system(size: 13)).lineSpacing(3)
                        }.foregroundStyle(.secondary).padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        Button { showDetails.toggle() } label: {
                            HStack { Text("목표와 지침 (선택)"); Spacer(); Image(systemName: showDetails ? "chevron.up" : "chevron.down") }
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                    if showDetails { details }
                }.padding(.trailing, 2)
            }.frame(height: project != nil ? 360 : showDetails ? 440 : 350).scrollIndicators(.hidden)
            if let error = projects.error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Button { showMemory.toggle() } label: {
                    HStack(spacing: 8) {
                        Text(memoryMode == .allRecords ? "기본 메모리" : "프로젝트 전용 메모리")
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).popover(isPresented: $showMemory) { memoryOptions }
                Spacer()
                Button(project == nil ? "프로젝트 만들기" : "저장") { save() }
                    .buttonStyle(.plain).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(nsColor: .textBackgroundColor)).padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.primary.opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.25 : 0.9), in: Capsule())
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 540).background(Color(nsColor: .textBackgroundColor))
    }

    private var folderSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("소스 폴더").font(.system(size: 14, weight: .medium))
            VStack(spacing: 12) {
                ForEach(paths, id: \.self) { path in
                    HStack {
                        Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder").lineLimit(1)
                        Spacer()
                        Button { paths.removeAll { $0 == path } } label: { Image(systemName: "xmark").font(.system(size: 11)) }.buttonStyle(.plain)
                    }.font(.system(size: 13)).help(path)
                }
                if paths.isEmpty { Text("이 컴퓨터에서 폴더 추가").font(.system(size: 14)).foregroundStyle(.secondary) }
                Button { chooseFolders() } label: {
                    Label("추가", systemImage: "folder.badge.plus").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 7).background(Color.primary.opacity(0.04), in: Capsule())
                }.buttonStyle(.plain)
            }.padding(18).frame(maxWidth: .infinity, minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.09)))
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("목표").font(.system(size: 14, weight: .medium))
            TextField("이 프로젝트에서 이루려는 목표", text: $goal, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(2...3).padding(12)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            Text("공통 지침").font(.system(size: 14, weight: .medium)).padding(.top, 8)
            Text("답변 방식이나 작업 규칙을 적어주세요. 모든 프로젝트 채팅에 적용됩니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            TextEditor(text: $instructions).font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(8).frame(height: 120).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var memoryOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            memoryOption(.allRecords, title: "기본 메모리", description: "이 프로젝트와 일반 채팅, 다른 프로젝트의 기록을 함께 참고합니다. 프로젝트 전용 기록은 제외됩니다.")
            memoryOption(.projectOnly, title: "프로젝트 전용 메모리", description: "이 프로젝트의 기록만 참고합니다. 다른 채팅에서도 이 프로젝트의 기록을 읽을 수 없습니다.")
        }.padding(12).frame(width: 350)
    }

    private func memoryOption(_ mode: ProjectMemoryMode, title: String, description: String) -> some View {
        Button { memoryMode = mode; showMemory = false } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 14, weight: .medium))
                    Text(description).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark").opacity(memoryMode == mode ? 1 : 0)
            }.padding(12).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        paths = Array(Set(paths + panel.urls.map(\.path))).sorted()
    }

    private func save() {
        if let project {
            if projects.update(project, title: title, goal: goal, instructions: instructions, memoryMode: memoryMode) { dismiss() }
        } else if let created = projects.create(title: title, goal: goal, instructions: instructions, memoryMode: memoryMode, paths: paths) {
            onSave(created); dismiss()
        }
    }
}

struct ProjectProposalsSheet: View {
    @ObservedObject var projects: ProjectState
    @ObservedObject var chat: ChatState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("프로젝트 제안").font(.system(size: 22, weight: .medium))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("닫기")
            }
            Text("관련 있는 업무와 채팅을 함께 묶어 제안합니다. 수락한 항목만 프로젝트에 들어갑니다.")
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(3)
            if let error = projects.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            if chat.running { Text("채팅 응답이 끝나면 제안을 수락할 수 있습니다.").font(.callout).foregroundStyle(.secondary) }
            if projects.proposals.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: projects.checking ? "sparkles" : "folder.badge.plus")
                        .font(.system(size: 34, weight: .light)).foregroundStyle(.tertiary)
                    Text(projects.checking ? "함께 묶을 항목을 찾고 있어요" : "새로운 제안이 없어요")
                        .font(.system(size: 16, weight: .medium))
                    Text("같은 목표를 다루는 업무와 채팅이 쌓이면 알려드릴게요.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(projects.proposals) { proposal in
                            ProjectProposalCard(projects: projects, proposal: proposal, canAccept: !chat.running)
                        }
                    }
                }
            }
            HStack {
                if projects.checking {
                    ProgressView().controlSize(.small)
                    Text("새 항목 확인 중").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(projects.checking ? "확인 중단" : "새 항목 확인") {
                    if projects.checking { projects.stop() } else { projects.check() }
                }.buttonStyle(.plain).font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
        }.padding(24).frame(width: 560, height: projects.proposals.isEmpty ? 360 : 540)
            .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ProjectProposalCard: View {
    @ObservedObject var projects: ProjectState
    var proposal: ProjectProposal
    var canAccept: Bool
    @State private var title: String

    init(projects: ProjectState, proposal: ProjectProposal, canAccept: Bool) {
        self.projects = projects; self.proposal = proposal; self.canAccept = canAccept
        _title = State(initialValue: proposal.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let projectID = proposal.projectID {
                Text(projects.projects.first(where: { $0.id == projectID })?.title ?? proposal.title).font(.system(size: 15, weight: .medium))
            } else { TextField("프로젝트 이름", text: $title).textFieldStyle(.plain).font(.system(size: 15, weight: .medium)) }
            Text(proposal.goal).font(.system(size: 13)).foregroundStyle(.secondary)
            Text(proposal.reason).font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(proposal.items) { item in Label(item.title, systemImage: item.isTask ? "checklist" : "bubble.left").font(.system(size: 12)) }
            HStack {
                Button("제안 무시") { projects.dismiss(proposal) }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button(proposal.projectID == nil ? "프로젝트 만들기" : "프로젝트에 추가") { projects.accept(proposal, title: title) }
                    .buttonStyle(.plain).padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .disabled(!canAccept || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.font(.system(size: 12, weight: .medium)).padding(.top, 4)
        }.padding(18).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.1)))
    }
}

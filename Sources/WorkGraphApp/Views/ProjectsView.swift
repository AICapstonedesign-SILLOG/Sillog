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
            Label(project.title, systemImage: "folder").font(Brand.suit(10)).foregroundStyle(Brand.gray).lineLimit(1)
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
                    Image(systemName: "folder").font(.system(size: 24, weight: .regular)).foregroundStyle(Brand.ink)
                    Text(project.title).font(Brand.suit(27, .semibold)).tracking(-1.08).foregroundStyle(Brand.ink).lineLimit(2)
                    Spacer(minLength: 12)
                    Menu {
                        Button("프로젝트 설정") { showSettings = true }.disabled(chat.running)
                        Button("이름 바꾸기") { name = project.title; showRename = true }
                        Divider()
                        Button("프로젝트 삭제", role: .destructive) { showDelete = true }.disabled(chat.running)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(Brand.tabText)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help("프로젝트 메뉴").accessibilityLabel("프로젝트 메뉴")
                }
                composer
                HStack(spacing: 8) {
                    ForEach(["채팅", "소스"], id: \.self) { value in
                        Button { tab = value } label: {
                            Text(value).font(Brand.suit(12, tab == value ? .semibold : .regular))
                                .foregroundStyle(tab == value ? Brand.ink : Brand.tabText)
                                .padding(.horizontal, 14).frame(height: 35)
                                .glassPill(tab == value)
                        }.buttonStyle(.plain).accessibilityAddTraits(tab == value ? .isSelected : [])
                    }
                    Spacer()
                    if tab == "소스" {
                        Menu(newestFirst ? "최신순" : "오래된순") {
                            Button("최신순") { newestFirst = true }
                            Button("오래된순") { newestFirst = false }
                        }.menuStyle(.borderlessButton).fixedSize().font(Brand.suit(11)).foregroundStyle(Brand.gray)
                        Menu(sourceKindTitle) {
                            Button("전체") { sourceKind = "" }
                            Button("업로드") { sourceKind = "upload" }
                            Button("생성한 파일") { sourceKind = "generated" }
                            Button("저장한 답변") { sourceKind = "note" }
                            Button("폴더 연결") { sourceKind = "folder" }
                        }.menuStyle(.borderlessButton).fixedSize().font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.leading, 12)
                    }
                }.padding(.top, 4)
                if tab == "채팅" { conversationList }
                else { ProjectSourcesView(library: chat.library, projects: projects, project: project, kind: $sourceKind, newestFirst: $newestFirst) }
                if let error = projects.error { Text(error).font(Brand.suit(12)).foregroundStyle(.red).textSelection(.enabled) }
                if let error = chat.error { Text(error).font(Brand.suit(12)).foregroundStyle(.red).textSelection(.enabled) }
            }.frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 34).padding(.top, 40).padding(.bottom, 40)
                .frame(maxWidth: .infinity)
        }.background(.white)
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
                    Text("첫 채팅을 시작해보세요").font(Brand.suit(14, .medium)).foregroundStyle(Brand.ink)
                    Text("위 입력창에서 질문하면 이 프로젝트에 새 채팅이 만들어집니다.")
                        .font(Brand.suit(12)).foregroundStyle(Brand.gray)
                }.padding(.vertical, 32).padding(.horizontal, 16)
            }
            ForEach(conversations) { conversation in
                HStack(spacing: 12) {
                    Button { onConversation(conversation) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(conversation.title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.tabText).lineLimit(1)
                            let preview = chat.conversationPreviews[conversation.id, default: ""]
                            if !preview.isEmpty {
                                Text(preview.replacingOccurrences(of: "\n", with: " "))
                                    .font(Brand.suit(11)).foregroundStyle(Brand.gray).lineLimit(1)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 17)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Text(Date(timeIntervalSince1970: conversation.updatedAt), format: .dateTime.month().day())
                        .font(Brand.jost(11)).foregroundStyle(Brand.gray)
                    Menu {
                        ProjectMoveMenu(projects: projects, itemID: "conversation:\(conversation.id)")
                            .disabled(chat.activeMessage?.conversationID == conversation.id)
                    } label: { Image(systemName: "ellipsis").foregroundStyle(Brand.gray).frame(width: 24, height: 28) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .opacity(hoveredConversation == conversation.id ? 1 : 0)
                        .accessibilityLabel("\(conversation.title) 채팅 메뉴")
                }.padding(.horizontal, 16)
                    .background(hoveredConversation == conversation.id ? Color(hex: 0xF6F5F4) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .onHover { hoveredConversation = $0 ? conversation.id : nil }
                    .contextMenu {
                        ProjectMoveMenu(projects: projects, itemID: "conversation:\(conversation.id)")
                            .disabled(chat.activeMessage?.conversationID == conversation.id)
                    }
                Rectangle().fill(Brand.line).frame(height: 1)
            }
            if !tasks.isEmpty {
                DisclosureGroup {
                    ForEach(tasks) { item in
                        HStack(spacing: 12) {
                            Label(item.title, systemImage: "checklist").font(Brand.suit(12)).foregroundStyle(Brand.tabText)
                            Spacer()
                            if let id = Int64(item.id.dropFirst(5)) {
                                Button("다시 열기") { state.prepareResume(taskId: id) }.buttonStyle(.plain).font(Brand.suit(11, .medium)).foregroundStyle(Brand.tabText)
                            }
                            Menu { ProjectMoveMenu(projects: projects, itemID: item.id) } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        }.padding(.vertical, 9)
                    }
                } label: { Text("연결된 업무 \(tasks.count)").font(Brand.suit(12)).foregroundStyle(Brand.gray) }
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

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibrarySheetHeader(eyebrow: "PROJECT", title: project == nil ? "프로젝트 만들기" : "프로젝트 설정") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("프로젝트 이름").font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                        HStack(spacing: 10) {
                            Image(systemName: "folder").font(.system(size: 15)).foregroundStyle(Brand.gray)
                            TextField("프로젝트 이름을 입력하세요", text: $title).textFieldStyle(.plain).font(Brand.suit(12)).foregroundStyle(Brand.text)
                        }.brandField()
                    }
                    if project == nil {
                        folderSelection
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle").font(.system(size: 14)).padding(.top, 1)
                            Text("채팅, 파일, 공통 지침을 한곳에 모아두세요. 프로젝트의 모든 채팅에서 함께 활용할 수 있습니다.")
                                .font(Brand.suit(12)).lineSpacing(3)
                        }.foregroundStyle(Brand.gray)
                        Button { showDetails.toggle() } label: {
                            HStack { Text("목표와 지침 (선택)"); Spacer(); Image(systemName: showDetails ? "chevron.up" : "chevron.down") }
                                .font(Brand.suit(12)).foregroundStyle(Brand.gray)
                        }.buttonStyle(.plain)
                    }
                    if showDetails { details }
                }.padding(.horizontal, 27).padding(.vertical, 24)
            }.frame(height: project != nil ? 340 : showDetails ? 420 : 330).scrollIndicators(.hidden).background(.white)
            if let error = projects.error { Text(error).foregroundStyle(.red).font(Brand.suit(12)).padding(.horizontal, 27).padding(.bottom, 8).background(.white) }
            HStack(spacing: 8) {
                Button { showMemory.toggle() } label: {
                    HStack(spacing: 6) {
                        Text(memoryMode == .allRecords ? "기본 메모리" : "프로젝트 전용 메모리")
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                }.buttonStyle(BrandButtonStyle()).popover(isPresented: $showMemory) { memoryOptions }
                Spacer()
                Button(project == nil ? "프로젝트 만들기" : "저장") { save() }
                    .buttonStyle(BrandButtonStyle(kind: .primary)).opacity(canSave ? 1 : 0.38).disabled(!canSave)
            }.padding(.horizontal, 24).frame(height: 63)
                .brandGlass()
                .overlay(alignment: .top) { Rectangle().fill(Brand.hairline).frame(height: 1) }
        }.frame(width: 560).background(.white)
    }

    private var folderSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("소스 폴더").font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
            VStack(spacing: 10) {
                ForEach(paths, id: \.self) { path in
                    HStack {
                        Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder").lineLimit(1)
                        Spacer()
                        Button { paths.removeAll { $0 == path } } label: { Image(systemName: "xmark").font(.system(size: 11)) }.buttonStyle(.plain)
                    }.font(Brand.suit(12)).foregroundStyle(Brand.tabText).help(path)
                }
                if paths.isEmpty { Text("이 컴퓨터에서 폴더 추가").font(Brand.suit(12)).foregroundStyle(Brand.gray) }
                Button { chooseFolders() } label: {
                    Label("추가", systemImage: "folder.badge.plus")
                }.buttonStyle(BrandButtonStyle())
            }.padding(16).frame(maxWidth: .infinity, minHeight: 100)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("목표").font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
            TextField("이 프로젝트에서 이루려는 목표", text: $goal, axis: .vertical)
                .textFieldStyle(.plain).font(Brand.suit(12)).foregroundStyle(Brand.text).lineLimit(2...3).padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Brand.line))
            Text("공통 지침").font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink).padding(.top, 8)
            Text("답변 방식이나 작업 규칙을 적어주세요. 모든 프로젝트 채팅에 적용됩니다.")
                .font(Brand.suit(10)).foregroundStyle(Brand.gray)
            TextEditor(text: $instructions).font(Brand.suit(12)).foregroundStyle(Brand.text).scrollContentBackground(.hidden)
                .padding(6).frame(height: 120)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Brand.line))
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
                    Text(title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                    Text(description).font(Brand.suit(10)).foregroundStyle(Brand.gray).fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 0) {
            LibrarySheetHeader(eyebrow: "PROJECT PROPOSALS", title: "프로젝트 제안",
                               detail: "관련 있는 업무와 채팅을 함께 묶어 제안합니다. 수락한 항목만 프로젝트에 들어갑니다.") { dismiss() }
            VStack(alignment: .leading, spacing: 12) {
                if let error = projects.error { Text(error).font(Brand.suit(12)).foregroundStyle(.red).textSelection(.enabled) }
                if chat.running { Text("채팅 응답이 끝나면 제안을 수락할 수 있습니다.").font(Brand.suit(12)).foregroundStyle(Brand.gray) }
                if projects.proposals.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: projects.checking ? "sparkles" : "folder.badge.plus")
                            .font(.system(size: 28, weight: .light)).foregroundStyle(Brand.sub)
                        Text(projects.checking ? "함께 묶을 항목을 찾고 있어요" : "새로운 제안이 없어요")
                            .font(Brand.suit(14, .medium)).foregroundStyle(Brand.ink)
                        Text("같은 목표를 다루는 업무와 채팅이 쌓이면 알려드릴게요.")
                            .font(Brand.suit(12)).foregroundStyle(Brand.gray)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(projects.proposals) { proposal in
                                ProjectProposalCard(projects: projects, proposal: proposal, canAccept: !chat.running)
                            }
                        }
                    }
                }
            }.padding(.horizontal, 27).padding(.vertical, 20).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
            HStack(spacing: 8) {
                if projects.checking {
                    ProgressView().controlSize(.small)
                    Text("새 항목 확인 중").font(Brand.suit(10)).foregroundStyle(Brand.gray)
                }
                Spacer()
                Button(projects.checking ? "확인 중단" : "새 항목 확인") {
                    if projects.checking { projects.stop() } else { projects.check() }
                }.buttonStyle(BrandButtonStyle())
            }.padding(.horizontal, 24).frame(height: 63)
                .brandGlass()
                .overlay(alignment: .top) { Rectangle().fill(Brand.hairline).frame(height: 1) }
        }.frame(width: 600, height: projects.proposals.isEmpty ? 400 : 560)
            .background(.white)
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
        VStack(alignment: .leading, spacing: 10) {
            if let projectID = proposal.projectID {
                Text(projects.projects.first(where: { $0.id == projectID })?.title ?? proposal.title).font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink)
            } else { TextField("프로젝트 이름", text: $title).textFieldStyle(.plain).font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink) }
            Text(proposal.goal).font(Brand.suit(12)).foregroundStyle(Brand.tabText)
            Text(proposal.reason).font(Brand.suit(10)).foregroundStyle(Brand.gray)
            ForEach(proposal.items) { item in
                Label(item.title, systemImage: item.isTask ? "checklist" : "bubble.left").font(Brand.suit(11)).foregroundStyle(Brand.tabText)
            }
            HStack {
                Button("제안 무시") { projects.dismiss(proposal) }.buttonStyle(.plain).foregroundStyle(Brand.gray)
                Spacer()
                Button(proposal.projectID == nil ? "프로젝트 만들기" : "프로젝트에 추가") { projects.accept(proposal, title: title) }
                    .buttonStyle(BrandButtonStyle(kind: .primary))
                    .disabled(!canAccept || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.font(Brand.suit(11, .medium)).padding(.top, 4)
        }.padding(16)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xF6F5F4)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.line))
    }
}

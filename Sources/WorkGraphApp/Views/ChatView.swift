import SwiftUI
import WorkGraphCore

struct ChatView: View {
    @ObservedObject var chat: ChatState
    @ObservedObject var projects: ProjectState
    @ObservedObject var library: LibraryState
    var modelName = ""
    var openSettings: () -> Void = {}
    @State private var artifact: ChatArtifact?
    @State private var source: ChatSource?
    @State private var pendingAutomation: ConversationMessage?
    @State private var showSchedules = false
    @State private var showPlugins = false
    @State private var showSources = false
    @State private var showProjectProposals = false
    @State private var showNewProject = false
    @State private var showLibraryPicker = false
    @State private var shareLibrarySelection = false
    @State private var savingResponse: ConversationMessage?
    @State private var sourceTitle = ""
    @State private var selectedProjectID: String?
    @State private var expandedProjects: Set<String> = []
    @State private var sidebarVisible = true
    @State private var inputHeight: CGFloat = 56
    @State private var hoveredConversation: String?
    @State private var hoveredProject: String?
    @State private var editingConversation: ChatConversation?
    @State private var deletingConversation: ChatConversation?
    @State private var conversationName = ""
    @State private var showRename = false
    @State private var showDelete = false
    @State private var selectedQuestionID: String?
    @State private var hoveredQuestionID: String?

    private var layout: some View {
        Group {
            if sidebarVisible {
                HSplitView {
                    sidebar.frame(minWidth: 200, idealWidth: 240, maxWidth: 260)
                    mainContent.frame(minWidth: 500)
                }
            } else {
                mainContent
            }
        }
    }

    private var sheets: some View {
        layout
        .sheet(item: $artifact) { ArtifactPreview(artifact: $0) }
        .sheet(item: $source) { ChatSourceSheet(source: $0) }
        .sheet(item: $pendingAutomation) { message in automationApproval(message) }
        .sheet(isPresented: $showSchedules) { ChatSchedulesView(chat: chat) }
    }

    private var projectSheets: some View {
        sheets
        .sheet(isPresented: $showProjectProposals) { ProjectProposalsSheet(projects: projects, chat: chat) }
        .sheet(isPresented: $showNewProject) { ProjectEditor(projects: projects) { openProject($0) } }
        .sheet(isPresented: $showLibraryPicker) { LibraryPicker(library: library) { chat.attachLibraryItem($0, projectWide: shareLibrarySelection) } }
        .alert("프로젝트 자료로 저장", isPresented: Binding(get: { savingResponse != nil }, set: { if !$0 { savingResponse = nil } })) {
            TextField("자료 이름", text: $sourceTitle)
            Button("취소", role: .cancel) { savingResponse = nil }
            Button("저장") {
                if let savingResponse, let projectID = chat.current.projectID { library.saveResponse(savingResponse, title: sourceTitle, projectID: projectID) }
                savingResponse = nil
            }.disabled(sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { Text("이 답변을 프로젝트의 모든 대화에서 재사용할 수 있는 자료로 보관합니다.") }
    }

    var body: some View {
        projectSheets
        .alert("이름 바꾸기", isPresented: $showRename) {
            TextField("대화 이름", text: $conversationName)
            Button("취소", role: .cancel) {}
            Button("저장") {
                if let item = editingConversation { chat.rename(item, title: conversationName) }
            }.disabled(conversationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("대화를 삭제할까요?", isPresented: $showDelete) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                if let item = deletingConversation { chat.delete(item) }
            }
        } message: {
            Text("‘\(deletingConversation?.title ?? "")’의 메시지와 결과물이 삭제되며 복구할 수 없습니다. 원본 자료와 등록된 예약 작업은 유지됩니다.")
        }
        .environment(\.openURL, OpenURLAction { url in
            ["https", "http"].contains(url.scheme ?? "") ? .systemAction : .discarded
        })
        .onChange(of: chat.current.scope) { old, new in if old != new { chat.saveScope() } }
        .onChange(of: chat.current.skillID) { old, new in if old != new { chat.saveScope() } }
        .onChange(of: projects.projects) { _, values in
            if let selectedProjectID, !values.contains(where: { $0.id == selectedProjectID }) { self.selectedProjectID = nil }
        }
    }

    private var mainContent: some View {
        Group {
            if showPlugins {
                PluginCatalogView(onClose: { showPlugins = false }) { id, example in
                    chat.newConversation()
                    selectedProjectID = nil
                    if id == "github" { chat.current.scope.useGitHub = true }
                    else { chat.current.scope.plugins.append(id) }
                    chat.saveScope()
                    chat.draft = example
                    showPlugins = false
                }
            } else if let project = projects.projects.first(where: { $0.id == selectedProjectID }) {
                ProjectOverview(projects: projects, chat: chat, project: project,
                                onConversation: { chat.select($0); selectedProjectID = nil },
                                composer: composer).id(project.id)
            } else {
                chatContent
            }
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            header
            if let active = chat.activeMessage, active.conversationID != chat.current.id {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("다른 대화에서 작업 중").font(.callout)
                    Button("이동") {
                        if let item = chat.conversations.first(where: { $0.id == active.conversationID }) { chat.select(item) }
                    }.buttonStyle(.link)
                }.padding(10)
            }
            if chat.messages.isEmpty {
                Spacer(minLength: 24)
                VStack(spacing: 12) {
                    Text("무엇을 함께 해볼까요?").font(.system(size: 30, weight: .semibold))
                    Text("내 기록과 자료를 바탕으로, 질문부터 결과물까지.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }.padding(.bottom, 30)
                composer
                skillButtons.padding(.top, 20)
                Spacer(minLength: 32)
            } else {
                conversation
                composer.padding(.top, 12).padding(.bottom, 14)
            }
            if let error = chat.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(12)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .textBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { chat.newConversation(); showPlugins = false; selectedProjectID = nil } label: {
                HStack { Image(systemName: "square.and.pencil"); Text("새 대화"); Spacer() }
                    .font(.system(size: 13, weight: .medium)).padding(11)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { showPlugins = true } label: {
                HStack { Label("플러그인", systemImage: "square.grid.2x2"); Spacer() }
                    .font(.system(size: 13)).padding(10).contentShape(Rectangle())
                    .background(showPlugins ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("프로젝트").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Button { showNewProject = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("프로젝트 직접 만들기")
                        Button { showProjectProposals = true } label: {
                            Label("제안 \(projects.proposals.count)", systemImage: "sparkles").font(.system(size: 11))
                        }.buttonStyle(.plain).help("프로젝트 제안 확인")
                    }.padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 8)
                    if projects.checking { HStack { ProgressView().controlSize(.small); Text("프로젝트 확인 중…").font(.caption) }.padding(.horizontal, 10) }
                    ForEach(projects.projects) { project in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Button {
                                    if expandedProjects.contains(project.id) { expandedProjects.remove(project.id) }
                                    else { expandedProjects.insert(project.id) }
                                } label: {
                                    Image(systemName: expandedProjects.contains(project.id) ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9)).frame(width: 16, height: 28)
                                }.buttonStyle(.plain).accessibilityLabel("\(project.title) 대화 \(expandedProjects.contains(project.id) ? "접기" : "펼치기")")
                                Button { openProject(project) } label: {
                                    Label(project.title, systemImage: "folder").font(.system(size: 13)).lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                                }.buttonStyle(.plain)
                            }.padding(.horizontal, 7)
                                .background(selectedProjectID == project.id || hoveredProject == project.id ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                .onHover { hoveredProject = $0 ? project.id : nil }
                            if expandedProjects.contains(project.id) {
                                ForEach(chat.conversations.filter { $0.projectID == project.id }) { conversation in conversationRow(conversation).padding(.leading, 26) }
                            }
                        }
                    }
                    if projects.projects.isEmpty { Text("직접 만들거나 자동 제안을 수락하세요.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10) }
                    if projects.error != nil { Button("프로젝트 확인 오류 보기") { showProjectProposals = true }.font(.caption).foregroundStyle(.red) }
                    Text("일반 채팅").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 20).padding(.bottom, 6)
                    LazyVStack(spacing: 3) {
                        ForEach(chat.conversations.filter { $0.projectID == nil }) { item in conversationRow(item) }
                    }
                }
            }
            Button { showSchedules = true } label: {
                HStack { Label("예약 작업", systemImage: "clock"); Spacer(); Text("\(chat.automations.count)").foregroundStyle(.secondary) }
                    .font(.system(size: 13)).padding(10).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.padding(12).padding(.top, 8).background(Color(nsColor: .controlBackgroundColor))
    }

    private func conversationRow(_ item: ChatConversation) -> some View {
        HStack(spacing: 0) {
            Button { chat.select(item); showPlugins = false; selectedProjectID = nil } label: {
                Text(item.title).font(.system(size: 13)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 11).padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(.plain).help(item.title)
            Menu { conversationActions(item) } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .opacity(chat.current.id == item.id || hoveredConversation == item.id ? 1 : 0)
                .help("대화 메뉴").accessibilityLabel("\(item.title) 대화 메뉴")
        }.padding(.trailing, 5)
            .background((selectedProjectID == nil && !showPlugins && chat.current.id == item.id) || hoveredConversation == item.id ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .onHover { hoveredConversation = $0 ? item.id : nil }.contextMenu { conversationActions(item) }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Button { sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }.help("대화 목록 표시 전환")
            VStack(alignment: .leading, spacing: 3) {
                Text(chat.messages.isEmpty ? "새 대화" : chat.current.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if let project = projects.projects.first(where: { $0.id == chat.current.projectID }) {
                    Button { openProject(project) } label: {
                        Label(project.title, systemImage: "folder").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.help("프로젝트의 채팅과 소스 보기")
                }
                if !modelName.isEmpty {
                    Button(action: openSettings) {
                        HStack(spacing: 4) { Text(modelName); Image(systemName: "chevron.down").font(.system(size: 8)) }
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.help("채팅 모델 설정")
                }
            }
            Spacer()
            if !sidebarVisible {
                Button { chat.newConversation() } label: { Image(systemName: "square.and.pencil") }.help("새 대화")
            }
        }.buttonStyle(.plain).padding(.horizontal, 24).frame(height: 66)
    }

    /// Args: item은 메뉴를 연 대화이다.
    /// Returns: 이름 변경·삭제 메뉴. 생성 중에는 삭제를 비활성화한다.
    /// Raises: 없음.
    @ViewBuilder private func conversationActions(_ item: ChatConversation) -> some View {
        Button { editingConversation = item; conversationName = item.title; showRename = true } label: {
            Label("이름 바꾸기", systemImage: "pencil")
        }
        Divider()
        ProjectMoveMenu(projects: projects, itemID: "conversation:\(item.id)")
            .disabled(chat.activeMessage?.conversationID == item.id)
        Divider()
        Button(role: .destructive) { deletingConversation = item; showDelete = true } label: {
            Label("삭제", systemImage: "trash")
        }.disabled(chat.activeMessage?.conversationID == item.id)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                if chat.messages.contains(where: { $0.role == "user" }) {
                    GeometryReader { geometry in
                        let turns = conversationTurns
                        let step = min(28, max(10, (geometry.size.height - 36) / CGFloat(turns.count)))
                        let activeID = selectedQuestionID ?? turns.last?.id
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                                Button {
                                    selectedQuestionID = turn.id
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        proxy.scrollTo(turn.id, anchor: .top)
                                    }
                                } label: {
                                    Capsule()
                                        .fill(activeID == turn.id ? Color.primary : Color.secondary.opacity(0.45))
                                        .frame(width: hoveredQuestionID == turn.id ? 29 : activeID == turn.id ? 24 : 13,
                                               height: hoveredQuestionID == turn.id || activeID == turn.id ? 3 : 2)
                                        .frame(width: 44, height: step)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .offset(y: 18 + CGFloat(index) * step)
                                .onHover { hovering in
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        if hovering { hoveredQuestionID = turn.id }
                                        else if hoveredQuestionID == turn.id { hoveredQuestionID = nil }
                                    }
                                }
                                .accessibilityLabel("질문 \(index + 1): \(turn.question.text)")
                            }
                            if let index = turns.firstIndex(where: { $0.id == hoveredQuestionID }) {
                                turnPreview(turns[index])
                                    .offset(x: 48, y: min(max(18 + CGFloat(index) * step - 24, 8),
                                                          max(8, geometry.size.height - 160)))
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                                    .allowsHitTesting(false)
                            }
                        }
                        .animation(.easeOut(duration: 0.18), value: hoveredQuestionID)
                    }
                    .frame(width: 44)
                    .zIndex(1)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        ForEach(chat.messages) { message in
                            messageView(message)
                                .id(message.id)
                                .background {
                                    if message.role == "user" {
                                        GeometryReader { geometry in
                                            Color.clear.preference(key: QuestionPositionKey.self,
                                                value: [message.id: geometry.frame(in: .named("chatTranscript")).minY])
                                        }
                                    }
                                }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.frame(maxWidth: 740).frame(maxWidth: .infinity).padding(.horizontal, 32).padding(.vertical, 20)
                }
                .coordinateSpace(name: "chatTranscript")
                .defaultScrollAnchor(.bottom)
                .onPreferenceChange(QuestionPositionKey.self) { positions in
                    let ordered = positions.sorted { $0.value < $1.value }
                    selectedQuestionID = ordered.last(where: { $0.value <= 100 })?.key ?? ordered.first?.key
                }
                .onChange(of: chat.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: chat.current.id) { _, _ in
                    selectedQuestionID = nil
                    hoveredQuestionID = nil
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .overlay(alignment: .bottomTrailing) {
                    if chat.running {
                        Button { proxy.scrollTo("bottom", anchor: .bottom) } label: {
                            Image(systemName: "arrow.down").padding(9).background(.regularMaterial, in: Circle())
                        }.buttonStyle(.plain).help("최근 응답으로").padding(16)
                    }
                }
            }
        }
    }

    /// Args: 없음.
    /// Returns: 각 사용자 질문과 그 뒤에 이어진 모델 답변을 묶은 탐색 항목.
    /// Raises: 없음.
    private var conversationTurns: [ConversationTurn] {
        var turns: [ConversationTurn] = []
        for message in chat.messages {
            if message.role == "user" {
                turns.append(ConversationTurn(question: message))
            } else if message.role == "assistant", !turns.isEmpty {
                turns[turns.count - 1].answer = message
            }
        }
        return turns
    }

    /// Args: turn은 미리 볼 질문과 답변이다.
    /// Returns: 탐색 눈금에 마우스를 올렸을 때 표시할 미리보기 카드.
    /// Raises: 없음.
    private func turnPreview(_ turn: ConversationTurn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.question.text).font(.system(size: 12, weight: .medium)).lineLimit(2)
            Divider()
            if let answer = turn.answer, !answer.text.isEmpty {
                Text(answer.text).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
            } else {
                Text(turn.answer?.status == "running" ? "답변 작성 중…" : "답변 없음")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 300, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }

    private var isProjectHome: Bool { selectedProjectID != nil && !showPlugins }

    private func openProject(_ project: ChatProject) {
        if selectedProjectID != project.id || chat.current.projectID != project.id || !chat.messages.isEmpty {
            chat.newConversation(projectID: project.id)
        }
        selectedProjectID = project.id; expandedProjects.insert(project.id); showPlugins = false
    }

    private func sendDraft() {
        chat.send()
        if chat.activeMessage?.conversationID == chat.current.id { selectedProjectID = nil }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            let attachments = library.sources(conversationID: chat.current.id, projectID: isProjectHome ? nil : chat.current.projectID)
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachments) { item in
                            Button { showSources = true } label: {
                                Label(item.title, systemImage: "doc.text").lineLimit(1).font(.caption)
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(Color.primary.opacity(0.05), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if library.busy {
                HStack { ProgressView().controlSize(.small); Text("소스를 추가하고 있어요").font(.caption).foregroundStyle(.secondary) }
            }
            if !chat.current.scope.paths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chat.current.scope.paths, id: \.self) { path in
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(1)
                                Button { chat.current.scope.paths.removeAll { $0 == path } } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                                    .disabled(chat.activeMessage?.conversationID == chat.current.id).help("연결 해제")
                            }.font(.caption).padding(.horizontal, 9).padding(.vertical, 6)
                                .background(Color.primary.opacity(0.05), in: Capsule()).help(path)
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                if isProjectHome { attachmentMenu }
                ZStack(alignment: .topLeading) {
                    if chat.draft.isEmpty {
                        let project = projects.projects.first(where: { $0.id == selectedProjectID })
                        Text(isProjectHome ? "\(project?.title ?? "프로젝트")의 새 채팅" : "무엇이든 물어보세요")
                            .font(.system(size: 15)).foregroundStyle(.tertiary).lineLimit(1)
                            .padding(.top, 8).padding(.leading, 3).allowsHitTesting(false)
                    }
                    ChatInput(text: $chat.draft, height: $inputHeight, minimumHeight: isProjectHome ? 34 : 56, onSend: sendDraft)
                        .frame(height: inputHeight)
                }
                if isProjectHome {
                    if !modelName.isEmpty {
                        Button(action: openSettings) {
                            HStack(spacing: 5) { Text(modelName).lineLimit(1); Image(systemName: "chevron.down").font(.system(size: 9)) }
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }.buttonStyle(.plain).frame(maxWidth: 135).help("채팅 모델 설정")
                    }
                    sendButton
                }
            }
            if !isProjectHome {
                HStack(spacing: 14) {
                    attachmentMenu
                    Button { showSources.toggle() } label: {
                        HStack(spacing: 5) { Image(systemName: "slider.horizontal.3"); Text("자료") }.font(.system(size: 12))
                    }
                    Menu {
                        Button("자동 선택") { chat.current.skillID = "general" }
                        ForEach(chat.skills) { skill in Button(skill.title) { chat.current.skillID = skill.id } }
                    } label: {
                        Text(chat.skills.first(where: { $0.id == chat.current.skillID })?.title ?? "자동 선택").font(.system(size: 12))
                    }.menuStyle(.borderlessButton).fixedSize()
                    Spacer()
                    sendButton
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }.padding(isProjectHome ? 12 : 16)
            .padding(.horizontal, isProjectHome ? 6 : 0)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: isProjectHome ? 30 : 22))
            .overlay(RoundedRectangle(cornerRadius: isProjectHome ? 30 : 22).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.035), radius: 8, y: 2)
            .frame(maxWidth: isProjectHome ? .infinity : 780).padding(.horizontal, isProjectHome ? 0 : 28)
            .popover(isPresented: $showSources) { sourceOptions }
    }

    private var attachmentMenu: some View {
        Menu {
            Button("파일 업로드 · 이 채팅에서만") { chat.uploadFiles() }
            Button("보관함에서 선택 · 이 채팅에서만") { shareLibrarySelection = false; showLibraryPicker = true }
            if chat.current.projectID != nil {
                Button("파일 업로드 · 프로젝트 전체") { chat.uploadFiles(projectWide: true) }
                Button("보관함에서 선택 · 프로젝트 전체") { shareLibrarySelection = true; showLibraryPicker = true }
            }
            Divider()
            Button("원본 파일·폴더 연결") { chat.connectFiles() }
            Button("참고할 자료 설정") { showSources = true }
        } label: { Image(systemName: "plus").font(.system(size: 19)).frame(width: 24, height: 28) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("자료 추가").accessibilityLabel("자료 추가")
            .disabled(library.busy || chat.activeMessage?.conversationID == chat.current.id)
    }

    private var sendButton: some View {
        Button {
            if chat.running { chat.cancel() } else { sendDraft() }
        } label: {
            Image(systemName: chat.running ? "stop.fill" : "arrow.up")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(nsColor: .textBackgroundColor))
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(chat.running || !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.9 : 0.2), in: Circle())
        }.buttonStyle(.plain).disabled(!chat.running && chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(chat.running ? "응답 중단" : "전송 (Enter)").accessibilityLabel(chat.running ? "응답 중단" : "전송")
    }

    private var sourceOptions: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 13) {
            Text("답변에 사용할 자료").font(.headline)
            if let project = projects.projects.first(where: { $0.id == chat.current.projectID }) {
                Text(project.memoryMode.title).font(.callout).foregroundStyle(.secondary)
                Button("프로젝트의 채팅과 소스 보기") { showSources = false; openProject(project) }
            }
            Toggle("내 활동 기록", isOn: $chat.current.scope.useActivity)
            Toggle("웹 검색 허용", isOn: $chat.current.scope.useWeb)
            Divider()
            Text("플러그인").font(.system(size: 13, weight: .medium))
            Toggle("Gmail", isOn: pluginBinding("gmail"))
            Toggle("Google Drive", isOn: pluginBinding("drive"))
            Toggle("GitHub", isOn: githubBinding())
            Toggle("Notion", isOn: pluginBinding("notion"))
            Divider()
            HStack {
                Text("보관 자료").font(.system(size: 13, weight: .medium))
                Spacer()
                Menu("추가") {
                    Button("파일 업로드 · 이 대화에서만") { showSources = false; chat.uploadFiles() }
                    Button("보관함에서 선택 · 이 대화에서만") { shareLibrarySelection = false; showSources = false; showLibraryPicker = true }
                    if chat.current.projectID != nil {
                        Button("파일 업로드 · 프로젝트 전체") { showSources = false; chat.uploadFiles(projectWide: true) }
                        Button("보관함에서 선택 · 프로젝트 전체") { shareLibrarySelection = true; showSources = false; showLibraryPicker = true }
                    }
                }.disabled(library.busy)
            }
            let sharedIDs = Set(library.sources(projectID: chat.current.projectID).map(\.id))
            ForEach(library.sources(conversationID: chat.current.id, projectID: chat.current.projectID)) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.caption).lineLimit(2)
                        Text(sharedIDs.contains(item.id) ? "프로젝트 전체" : "이 대화에서만").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !sharedIDs.contains(item.id) {
                        Menu {
                            if let projectID = chat.current.projectID { Button("프로젝트 전체에서 사용") { library.attach(item, projectID: projectID) } }
                            Button("이 대화에서 연결 해제") { library.detach(item, conversationID: chat.current.id) }
                        } label: { Image(systemName: "ellipsis") }
                    } else if let projectID = chat.current.projectID {
                        Button("연결 해제") { library.detach(item, projectID: projectID) }.font(.caption)
                    }
                }
            }
            if library.busy { ProgressView().controlSize(.small) }
            if let error = library.error { Text(error).font(.caption).foregroundStyle(.red) }
            Divider()
            HStack { Text("원본 파일·폴더 연결").font(.system(size: 13, weight: .medium)); Spacer(); Button("추가") { showSources = false; chat.connectFiles() } }
            if chat.current.scope.paths.isEmpty {
                Text("연결된 자료가 없습니다.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(chat.current.scope.paths, id: \.self) { path in
                    HStack(spacing: 8) {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(path).font(.caption).lineLimit(2).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button { chat.current.scope.paths.removeAll { $0 == path } } label: { Image(systemName: "xmark") }
                            .help("연결 해제").accessibilityLabel("\(path) 연결 해제")
                    }
                }
            }
            Divider()
            Text("질문·공통 지침·관련 과거 기록과 보관 자료 일부가 모델에 전달됩니다. 추가 원문은 모델이 조회할 때 전송됩니다. 원본 연결은 파일을 복사하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            Text("웹 검색은 Codex 또는 OpenAI API를 사용합니다. 플러그인 조회 대상은 선택한 서비스에 전송됩니다.")
                .font(.caption).foregroundStyle(.secondary)
            Button("플러그인 둘러보기") { showSources = false; showPlugins = true }.buttonStyle(.link)
        }.padding(20)
        }.frame(width: 380, height: 600).disabled(chat.activeMessage?.conversationID == chat.current.id)
    }

    /// Args: id는 대화에서 켜거나 끌 플러그인이다.
    /// Returns: 대화별 플러그인 선택 바인딩.
    /// Raises: 없음.
    private func pluginBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { chat.current.scope.plugins.contains(id) }, set: { enabled in
            if enabled {
                guard (try? PluginAuth.isConnected(id)) == true else { showSources = false; showPlugins = true; return }
                if !chat.current.scope.plugins.contains(id) { chat.current.scope.plugins.append(id) }
            }
            else { chat.current.scope.plugins.removeAll { $0 == id } }
        })
    }

    /// Args: 없음.
    /// Returns: GitHub 연결 상태를 확인한 뒤 변경하는 대화별 자료 바인딩.
    /// Raises: 없음. 미연결 상태에서는 플러그인 목록을 연다.
    private func githubBinding() -> Binding<Bool> {
        Binding(get: { chat.current.scope.useGitHub }, set: { enabled in
            if enabled && (try? PluginAuth.isConnected("github")) != true {
                showSources = false; showPlugins = true; return
            }
            chat.current.scope.useGitHub = enabled
        })
    }

    private var skillButtons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            ForEach(chat.skills) { skill in
                Button { chat.current.skillID = chat.current.skillID == skill.id ? "general" : skill.id } label: {
                    HStack(spacing: 8) { Image(systemName: skill.icon).foregroundStyle(.secondary); Text(skill.title) }
                        .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(chat.current.skillID == skill.id ? Color.primary.opacity(0.06) : .clear, in: Capsule())
                        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        .contentShape(Capsule())
                }.buttonStyle(.plain).help(skill.summary)
            }
        }.frame(maxWidth: 600).padding(.horizontal, 36)
    }

    /// Args: message는 저장된 요청 또는 응답이다.
    /// Returns: 사용자 말풍선 또는 출처·실행 상태를 포함한 답변.
    /// Raises: 없음.
    @ViewBuilder private func messageView(_ message: ConversationMessage) -> some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 80)
                Text(message.text).font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
                    .padding(.horizontal, 18).padding(.vertical, 13)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if message.status == "running" || !message.steps.isEmpty {
                    DisclosureGroup {
                        ForEach(Array(message.steps.enumerated()), id: \.offset) { _, step in
                            Text(step).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if message.status == "running" { ProgressView().controlSize(.small) }
                            Text(message.steps.last ?? "답변을 준비하고 있습니다").font(.system(size: 12))
                        }
                    }.foregroundStyle(.secondary)
                }
                if message.status == "failed" {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("응답을 완료하지 못했습니다", systemImage: "exclamationmark.circle").font(.system(size: 13, weight: .medium))
                        Text(message.text.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                } else if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ChatMessageText(text: message.text, sources: message.sources) { source = $0 }
                }
                ForEach(message.artifacts) { item in
                    Button { artifact = item } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").font(.system(size: 23)).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.system(size: 14, weight: .medium))
                                Text("\(item.format.uppercased()) · 미리보기 및 저장").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                        }.padding(16).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                if !message.sources.isEmpty {
                    DisclosureGroup("참고 자료 \(message.sources.count)개") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(message.sources) { item in
                                Button { source = item } label: {
                                    Label(item.title, systemImage: "doc.text.magnifyingglass").lineLimit(2).multilineTextAlignment(.leading)
                                }.buttonStyle(.plain)
                            }
                        }.padding(.top, 8)
                    }.font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if let proposal = message.automation {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(proposal.title).font(.system(size: 14, weight: .medium))
                            Text("\(proposal.intervalHours)시간마다 · 앱 실행 중").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(message.approvedAutomationID == nil ? "예약안 확인" : "등록됨") { pendingAutomation = message }
                            .disabled(message.approvedAutomationID != nil || message.status != "complete")
                    }.padding(14).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
                if message.status != "running" {
                    HStack(spacing: 14) {
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) } label: {
                            Image(systemName: "doc.on.doc")
                        }.help("답변 복사")
                        if chat.current.projectID != nil, message.status == "complete", !message.text.isEmpty {
                            Button("프로젝트 자료로 저장") { savingResponse = message; sourceTitle = "\(chat.current.title) · 저장한 답변" }
                        }
                        if ["cancelled", "interrupted"].contains(message.status) { Text("중단됨").font(.caption) }
                        if message.status == "failed" {
                            Button("요청 다시 입력") {
                                if let index = chat.messages.firstIndex(where: { $0.id == message.id }),
                                   let request = chat.messages[..<index].last(where: { $0.role == "user" }) { chat.draft = request.text }
                            }.font(.caption)
                        }
                    }.buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Args: message는 승인할 예약안을 포함한 답변이다.
    /// Returns: 요청 내용·권한 범위를 확인하는 승인 화면.
    /// Raises: 없음.
    private func automationApproval(_ message: ConversationMessage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("예약 작업 등록").font(.title2.bold())
            if let proposal = message.automation {
                Text(proposal.title).font(.headline)
                Text(proposal.prompt).textSelection(.enabled)
                Text("\(proposal.intervalHours)시간마다 현재 자료 범위로 실행합니다. LLM 및 외부 API 사용량이 발생할 수 있습니다.")
                Text("활동 기록: \(chat.current.scope.useActivity ? "사용" : "미사용") · 웹 검색: \(chat.current.scope.useWeb ? "허용" : "미허용") · 플러그인: \((chat.current.scope.plugins + (chat.current.scope.useGitHub ? ["GitHub"] : [])).joined(separator: ", "))")
                Text(chat.current.scope.paths.joined(separator: "\n")).font(.caption).textSelection(.enabled)
                ForEach(library.sources(conversationID: chat.current.id, projectID: chat.current.projectID)) { Text("보관 자료 · \($0.title)").font(.caption) }
                Text("원본 파일 변경·명령 실행·메시지 발송은 하지 않습니다. 앱 종료·절전 중에는 실행되지 않습니다.").foregroundStyle(.secondary)
            }
            HStack { Spacer(); Button("취소") { pendingAutomation = nil }; Button("등록") { chat.approve(message); pendingAutomation = nil }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 540)
    }
}

private struct ConversationTurn: Identifiable {
    var question: ConversationMessage
    var answer: ConversationMessage?
    var id: String { question.id }
}

private struct QuestionPositionKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    /// Args: value는 누적된 질문 위치, nextValue는 다음 메시지의 위치이다.
    /// Returns: 없음. 질문별 위치를 누적한다.
    /// Raises: 없음.
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct ChatSourceSheet: View {
    let source: ChatSource
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(source.title).font(.headline)
            Text(source.location).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            ScrollView { Text(source.excerpt).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                if let url = URL(string: source.location), ["https", "http"].contains(url.scheme ?? "") { Link("원문 열기", destination: url) }
                else if source.location.hasPrefix("/") { Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: source.location)]) } }
                Spacer(); Button("닫기") { dismiss() }
            }
        }.padding(24).frame(width: 740, height: 540)
    }
}

private struct ChatSchedulesView: View {
    @ObservedObject var chat: ChatState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var deletingJob: ChatAutomation?
    @State private var confirmDelete = false

    private var selected: ChatAutomation? { chat.automations.first { $0.id == selectedID } ?? chat.automations.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("예약 작업").font(.title2.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("닫기")
            }
            Text("앱 실행 중에만 동작합니다. 기한이 지난 작업은 한 번 실행하며, 실패한 작업을 즉시 재시도하지 않습니다.")
                .font(.callout).foregroundStyle(.secondary)
            if chat.automations.isEmpty {
                Spacer()
                VStack(spacing: 9) {
                    Image(systemName: "clock").font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text("등록한 예약이 없습니다").font(.headline)
                    Text("채팅에서 반복할 작업과 실행 간격을 요청하세요.")
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                HStack(spacing: 0) {
                    List(chat.automations) { job in
                        HStack(spacing: 8) {
                            Button { selectedID = job.id } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(job.title).font(.headline).lineLimit(1)
                                    Text("\(job.intervalHours)시간마다 · \(job.lastStatus)")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button { chat.toggle(job) } label: {
                                Image(systemName: job.enabled ? "pause.fill" : "play.fill")
                            }
                            .help(job.enabled ? "일시 중지" : "다시 시작")
                            .accessibilityLabel(job.enabled ? "일시 중지" : "다시 시작")
                            Button { deletingJob = job; confirmDelete = true } label: {
                                Image(systemName: "trash")
                            }
                            .help("예약 삭제").accessibilityLabel("예약 삭제")
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(selected?.id == job.id ? Color.accentColor.opacity(0.1) : Color.clear)
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 330)
                    Divider()
                    if let job = selected {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(job.title).font(.title3.bold())
                                Text(job.enabled ? "실행 대기" : "일시 중지됨").foregroundStyle(.secondary)
                                Text("요청 내용").font(.headline)
                                Text(job.prompt).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                Divider()
                                LabeledContent("실행 간격", value: "\(job.intervalHours)시간마다")
                                LabeledContent("자료 범위", value: job.scope.useActivity ? "활동 기록 포함" : "활동 기록 제외")
                                LabeledContent("웹 검색", value: job.scope.useWeb ? "사용" : "사용 안 함")
                                LabeledContent("플러그인", value: (job.scope.plugins + (job.scope.useGitHub ? ["GitHub"] : [])).joined(separator: ", "))
                                if !job.scope.paths.isEmpty {
                                    Text("연결된 파일·폴더").font(.headline)
                                    ForEach(job.scope.paths, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                                }
                                ForEach(chat.library.items.filter { job.scope.libraryIDs.contains($0.id) }) { Text("보관 자료 · \($0.title)").font(.caption) }
                                LabeledContent("최근 상태", value: job.lastStatus)
                                if job.enabled { LabeledContent("다음 실행", value: Date(timeIntervalSince1970: job.nextRun).formatted()) }
                                if let id = job.lastConversationID, let conversation = chat.conversations.first(where: { $0.id == id }) {
                                    Button("최근 실행 보기") { chat.select(conversation); dismiss() }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                        }
                    }
                }
            }
        }
        .padding(24).frame(width: 760, height: 460)
        .alert("예약 작업 삭제", isPresented: $confirmDelete) {
            Button("취소", role: .cancel) { deletingJob = nil }
            Button("삭제", role: .destructive) {
                if let deletingJob {
                    chat.deleteAutomation(deletingJob)
                    if selectedID == deletingJob.id { selectedID = nil }
                }
                deletingJob = nil
            }
        } message: { Text("예약을 삭제합니다. 이미 생성된 대화는 그대로 남습니다.") }
    }
}

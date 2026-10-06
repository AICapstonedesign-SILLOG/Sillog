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
                    Text("다른 대화에서 작업 중").font(Brand.suit(11)).foregroundStyle(Brand.tabText)
                    Button("이동") {
                        if let item = chat.conversations.first(where: { $0.id == active.conversationID }) { chat.select(item) }
                    }.buttonStyle(BrandButtonStyle())
                    Spacer()
                }.padding(.horizontal, 28).padding(.vertical, 8)
                    .background(ChatPalette.soft)
                    .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
            }
            if chat.messages.isEmpty {
                emptyState
            } else {
                conversation
            }
            if let error = chat.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(Brand.suit(11)).foregroundStyle(Brand.ink).textSelection(.enabled)
                    .padding(.horizontal, 28).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(ChatPalette.soft)
                    .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
            }
            composer
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
    }

    /// Args: 없음.
    /// Returns: 새 대화의 시작 화면. 제안 문구를 누르면 입력칸에 채운다.
    /// Raises: 없음.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let mark = Brand.wordmark {
                Image(nsImage: mark).resizable().scaledToFit().frame(height: 19).padding(.leading, 8)
            }
            Text("쌓아 온 기록으로,\n다음 일을 시작해요.")
                .font(Brand.suit(25)).tracking(-1).lineSpacing(0).foregroundStyle(Brand.ink)
                .padding(.top, 20)
            Text("업무를 찾고, 정리하고, 결과물로 이어 보세요.")
                .font(Brand.suit(12)).foregroundStyle(Brand.gray).padding(.top, 24).padding(.bottom, 14)
            ForEach(["Flask 개발 기록을 포트폴리오로 정리하기", "매주 업무 기록 정리하기"], id: \.self) { example in
                Button { chat.draft = example } label: {
                    HStack {
                        Text(example).font(Brand.suit(11)).foregroundStyle(Brand.text)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Brand.text)
                    }.frame(height: 42).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
            }
        }.frame(width: 400).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("THINK WITH YOUR WORK")
                HStack {
                    Text("채팅").font(Brand.suit(23, .semibold)).tracking(-0.805).foregroundStyle(Brand.ink)
                    Spacer()
                    ChatTag(text: "일부")
                }.padding(.top, 8)
                Button { chat.newConversation(); showPlugins = false; selectedProjectID = nil } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 12))
                        Text("새 대화").font(Brand.suit(12, .medium))
                    }.foregroundStyle(Brand.tabText).frame(maxWidth: .infinity).frame(height: 38)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.33)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.top, 14)
            }.padding(.horizontal, 24).padding(.top, 27).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("CONVERSATIONS").padding(.horizontal, 12).padding(.top, 11).padding(.bottom, 14)
                    LazyVStack(spacing: 5) {
                        ForEach(chat.conversations.filter { $0.projectID == nil }) { item in conversationRow(item) }
                    }
                    HStack {
                        Eyebrow("PROJECTS")
                        Spacer()
                        Button { showNewProject = true } label: { Image(systemName: "plus").font(.system(size: 11)) }.buttonStyle(.plain).help("프로젝트 직접 만들기")
                        Button { showProjectProposals = true } label: {
                            Label("제안 \(projects.proposals.count)", systemImage: "sparkles").font(Brand.suit(10))
                        }.buttonStyle(.plain).help("프로젝트 제안 확인")
                    }.foregroundStyle(Brand.gray).padding(.horizontal, 12).padding(.top, 24).padding(.bottom, 10)
                    if projects.checking { HStack { ProgressView().controlSize(.small); Text("프로젝트 확인 중…").font(Brand.suit(10)).foregroundStyle(Brand.gray) }.padding(.horizontal, 12) }
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
                                    Label(project.title, systemImage: "folder").font(Brand.suit(11)).lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                                }.buttonStyle(.plain)
                            }.padding(.horizontal, 7).foregroundStyle(selectedProjectID == project.id ? Brand.ink : Brand.tabText)
                                .background(selectedProjectID == project.id || hoveredProject == project.id ? Color.white.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 5))
                                .onHover { hoveredProject = $0 ? project.id : nil }
                            if expandedProjects.contains(project.id) {
                                ForEach(chat.conversations.filter { $0.projectID == project.id }) { conversation in conversationRow(conversation).padding(.leading, 26) }
                            }
                        }
                    }
                    if projects.projects.isEmpty { Text("직접 만들거나 자동 제안을 수락하세요.").font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.horizontal, 12) }
                    if projects.error != nil { Button("프로젝트 확인 오류 보기") { showProjectProposals = true }.font(Brand.suit(10)).foregroundStyle(Brand.ink) }
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
            Button { showSchedules = true } label: {
                HStack {
                    Text("예약 작업")
                    Spacer()
                    Text("\(chat.automations.count)").font(Brand.jost(11)).foregroundStyle(Brand.gray)
                    Image(systemName: "chevron.right").font(.system(size: 10))
                }.font(Brand.suit(11)).foregroundStyle(Brand.tabText).padding(.horizontal, 19).frame(height: 51).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(Brand.hairline).frame(height: 1) }
        }.frame(maxHeight: .infinity, alignment: .top)
            .brandGlass()
    }

    private func conversationRow(_ item: ChatConversation) -> some View {
        let selected = selectedProjectID == nil && !showPlugins && chat.current.id == item.id
        return HStack(spacing: 0) {
            Button { chat.select(item); showPlugins = false; selectedProjectID = nil } label: {
                Text(item.title).font(Brand.suit(11)).lineLimit(1).foregroundStyle(selected ? Brand.ink : Brand.tabText)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).frame(height: 45).contentShape(Rectangle())
            }.buttonStyle(.plain).help(item.title)
            Menu { conversationActions(item) } label: { Image(systemName: "ellipsis").foregroundStyle(Brand.gray).frame(width: 28, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .opacity(chat.current.id == item.id || hoveredConversation == item.id ? 1 : 0)
                .help("대화 메뉴").accessibilityLabel("\(item.title) 대화 메뉴")
        }.padding(.trailing, 5)
            .background(selected || hoveredConversation == item.id ? Color.white.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .onHover { hoveredConversation = $0 ? item.id : nil }.contextMenu { conversationActions(item) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("CHAT")
                Text(chat.messages.isEmpty ? "새 대화" : chat.current.title).font(Brand.suit(16)).foregroundStyle(Brand.ink).lineLimit(1).padding(.top, 7)
                if let project = projects.projects.first(where: { $0.id == chat.current.projectID }) {
                    Button { openProject(project) } label: {
                        Label(project.title, systemImage: "folder").font(Brand.suit(10)).foregroundStyle(Brand.gray)
                    }.help("프로젝트의 채팅과 소스 보기")
                }
                if !modelName.isEmpty {
                    ChatModelMenu(name: modelName, fontSize: 10, openSettings: openSettings)
                }
            }
            Spacer()
            ChatIconButton(systemName: "sidebar.left", help: "대화 목록 표시 전환") { sidebarVisible.toggle() }
            if !sidebarVisible {
                ChatIconButton(systemName: "square.and.pencil", help: "새 대화") { chat.newConversation() }
            }
            ChatIconButton(systemName: "pencil", help: "대화 이름 바꾸기") {
                editingConversation = chat.current; conversationName = chat.current.title; showRename = true
            }.disabled(chat.messages.isEmpty)
            ChatIconButton(systemName: "trash", help: "대화 삭제") {
                deletingConversation = chat.current; showDelete = true
            }.disabled(chat.messages.isEmpty || chat.activeMessage?.conversationID == chat.current.id)
            Button { showPlugins = true } label: {
                HStack(spacing: 6) { Image(systemName: "powerplug").font(.system(size: 11)); Text("플러그인") }
            }.buttonStyle(BrandButtonStyle())
        }.buttonStyle(.plain).padding(.horizontal, 28).frame(minHeight: 89)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
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
                                        .fill(activeID == turn.id ? Brand.ink : Brand.gray.opacity(0.45))
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
                    LazyVStack(alignment: .leading, spacing: 24) {
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
                    }.frame(maxWidth: 865).frame(maxWidth: .infinity).padding(.horizontal, 32).padding(.vertical, 24)
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
                            Image(systemName: "arrow.down").font(.system(size: 11)).foregroundStyle(Brand.tabText).frame(width: 30, height: 30).background(.white, in: Circle()).overlay(Circle().strokeBorder(Brand.line))
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
            Text(turn.question.text).font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink).lineLimit(2)
            Rectangle().fill(Brand.line).frame(height: 1)
            if let answer = turn.answer, !answer.text.isEmpty {
                Text(answer.text).font(Brand.suit(12)).foregroundStyle(Brand.gray).lineLimit(3)
            } else {
                Text(turn.answer?.status == "running" ? "답변 작성 중…" : "답변 없음")
                    .font(Brand.suit(12)).foregroundStyle(Brand.gray)
            }
        }
        .frame(width: 300, alignment: .leading)
        .padding(14)
        .glassPanel(cornerRadius: 8)
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

    private var attachmentChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            let attachments = library.sources(conversationID: chat.current.id, projectID: isProjectHome ? nil : chat.current.projectID)
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachments) { item in
                            Button { showSources = true } label: {
                                Label(item.title, systemImage: "doc.text").lineLimit(1)
                                    .font(Brand.suit(9)).foregroundStyle(Brand.tabText)
                                    .padding(.horizontal, 7).frame(height: 22)
                                    .background(ChatPalette.soft, in: RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.line))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if library.busy {
                HStack { ProgressView().controlSize(.small); Text("소스를 추가하고 있어요").font(Brand.suit(10)).foregroundStyle(Brand.gray) }
            }
            if !chat.current.scope.paths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chat.current.scope.paths, id: \.self) { path in
                            HStack(spacing: 5) {
                                Image(systemName: "folder").font(.system(size: 10))
                                Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(1)
                                Button { chat.current.scope.paths.removeAll { $0 == path } } label: { Image(systemName: "xmark").font(.system(size: 8)) }
                                    .disabled(chat.activeMessage?.conversationID == chat.current.id).help("연결 해제")
                            }.font(Brand.suit(9)).foregroundStyle(Brand.tabText).padding(.horizontal, 6).frame(height: 22)
                                .background(ChatPalette.soft, in: RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.line)).help(path)
                        }
                    }
                }
            }
        }
    }

    private var composerBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            attachmentChips.padding(.top, 12).padding(.horizontal, 14)
            HStack(alignment: .bottom, spacing: 12) {
                if isProjectHome { attachmentMenu }
                ZStack(alignment: .topLeading) {
                    if chat.draft.isEmpty {
                        let project = projects.projects.first(where: { $0.id == selectedProjectID })
                        Text(isProjectHome ? "\(project?.title ?? "프로젝트")의 새 채팅" : "기록을 바탕으로 무엇을 할까요?")
                            .font(Brand.suit(12)).foregroundStyle(Brand.text.opacity(0.5)).lineLimit(1)
                            .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                    }
                    ChatInput(text: $chat.draft, height: $inputHeight, minimumHeight: isProjectHome ? 34 : 38, onSend: sendDraft)
                        .frame(height: inputHeight)
                }
                if isProjectHome, !modelName.isEmpty {
                    ChatModelMenu(name: modelName, fontSize: 11, openSettings: openSettings).frame(maxWidth: 135)
                }
                sendButton.padding(.bottom, 4)
            }.padding(.horizontal, 14).padding(.vertical, 6)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ChatPalette.inputLine))
    }

    private var composerToolbar: some View {
        let busy = chat.activeMessage?.conversationID == chat.current.id
        return HStack(spacing: 10) {
            Menu {
                Button("자동 선택") { chat.current.skillID = "general" }
                ForEach(chat.skills) { skill in Button(skill.title) { chat.current.skillID = skill.id } }
            } label: {
                HStack {
                    Text(chat.skills.first(where: { $0.id == chat.current.skillID })?.title ?? "자동 선택")
                        .font(Brand.suit(10)).foregroundStyle(Brand.text)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(Brand.tabText)
                }.padding(.horizontal, 9).frame(width: 95, height: 27)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Brand.line))
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Button { chat.current.scope.useActivity.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: chat.current.scope.useActivity ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12)).foregroundStyle(chat.current.scope.useActivity ? Brand.sky : Brand.gray)
                    Text("활동 기록")
                }.foregroundStyle(chat.current.scope.useActivity ? Brand.ink : Brand.gray)
            }
            Button { chat.current.scope.useWeb.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe").font(.system(size: 11))
                    Text(chat.current.scope.useWeb ? "웹 검색 켬" : "웹 검색 끔")
                }.foregroundStyle(chat.current.scope.useWeb ? Brand.ink : Brand.gray)
            }
            attachmentMenu
            Spacer()
        }.font(Brand.suit(10)).buttonStyle(.plain).disabled(busy)
    }

    private var composer: some View {
        Group {
            if isProjectHome {
                composerBox.frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    composerToolbar.padding(.top, 15).padding(.bottom, 0)
                    composerBox.padding(.top, 12)
                    Text("질문과 조회한 자료는 연결한 AI로 전송돼요. 웹 검색과 플러그인은 허용한 범위만 사용해요.")
                        .font(Brand.suit(9)).foregroundStyle(Brand.gray).frame(maxWidth: .infinity).padding(.vertical, 9)
                }.padding(.horizontal, 27)
                    .background(.white)
                    .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
            }
        }.popover(isPresented: $showSources) { sourceOptions }
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
        } label: {
            if isProjectHome { Image(systemName: "plus").font(.system(size: 19)).frame(width: 24, height: 28) }
            else {
                HStack(spacing: 4) { Image(systemName: "paperclip").font(.system(size: 11)); Text("자료 연결") }
                    .font(Brand.suit(10)).foregroundStyle(Brand.gray)
            }
        }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("자료 추가").accessibilityLabel("자료 추가")
            .disabled(library.busy || chat.activeMessage?.conversationID == chat.current.id)
    }

    private var sendButton: some View {
        let empty = chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            if chat.running { chat.cancel() } else { sendDraft() }
        } label: {
            Image(systemName: chat.running ? "stop.fill" : "arrow.up")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Brand.ink.opacity(chat.running || !empty ? 1 : 0.38), in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).disabled(!chat.running && empty)
            .help(chat.running ? "응답 중단" : "전송 (Enter)").accessibilityLabel(chat.running ? "응답 중단" : "전송")
    }

    private var sourceOptions: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 13) {
            Text("답변에 사용할 자료").font(Brand.suit(14, .semibold)).foregroundStyle(Brand.ink)
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
        }.font(Brand.suit(12)).foregroundStyle(Brand.tabText).padding(20)
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

    /// Args: message는 저장된 요청 또는 응답이다.
    /// Returns: 사용자 질문 또는 출처, 실행 상태를 포함한 답변.
    /// Raises: 없음.
    @ViewBuilder private func messageView(_ message: ConversationMessage) -> some View {
        if message.role == "user" {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Text("나").font(Brand.suit(9, .medium)).foregroundStyle(Brand.tabText)
                        .frame(width: 21, height: 21).background(ChatPalette.soft, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.line))
                    Text("나").font(Brand.suit(11, .medium)).foregroundStyle(Brand.ink)
                }
                Text(message.text).font(Brand.suit(12)).foregroundStyle(Brand.tabText).lineSpacing(5).textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(ChatPalette.soft, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Text("S").font(Brand.jost(13)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Brand.ink, in: RoundedRectangle(cornerRadius: 5))
                    Text("Sillog").font(Brand.suit(11, .medium)).foregroundStyle(Brand.ink)
                    if chat.current.skillID != "general", let skill = chat.skills.first(where: { $0.id == chat.current.skillID }) {
                        BrandBadge(skill.title)
                    }
                }.padding(.top, 12)
                if message.status == "running" || !message.steps.isEmpty {
                    DisclosureGroup {
                        ForEach(Array(message.steps.enumerated()), id: \.offset) { _, step in
                            Text(step).font(Brand.suit(10)).foregroundStyle(Brand.gray).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if message.status == "running" { ProgressView().controlSize(.small) }
                            Text(message.steps.last ?? "답변을 준비하고 있습니다").font(Brand.suit(11))
                        }
                    }.foregroundStyle(Brand.gray)
                }
                if message.status == "failed" {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("응답을 완료하지 못했습니다", systemImage: "exclamationmark.circle").font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                        Text(message.text.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(Brand.suit(12)).foregroundStyle(Brand.tabText).textSelection(.enabled)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(ChatPalette.soft, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
                } else if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ChatMessageText(text: message.text, sources: message.sources) { source = $0 }
                }
                if !message.sources.isEmpty {
                    HStack(spacing: 7) {
                        Text("출처").font(Brand.suit(10)).foregroundStyle(Brand.gray)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(Array(message.sources.enumerated()), id: \.element.id) { index, item in
                                    Button { source = item } label: {
                                        HStack(spacing: 6) {
                                            Text("\(index + 1)").font(Brand.jost(9)).foregroundStyle(Brand.gray)
                                            Text(item.title).font(Brand.suit(9)).foregroundStyle(Brand.tabText).lineLimit(1)
                                            Image(systemName: "arrow.up.right").font(.system(size: 8)).foregroundStyle(Brand.gray)
                                        }.padding(.horizontal, 7).frame(height: 26)
                                            .background(.white, in: RoundedRectangle(cornerRadius: 4))
                                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.line))
                                    }.buttonStyle(.plain).help(item.title)
                                }
                            }
                        }
                    }
                }
                ForEach(message.artifacts) { item in
                    Button { artifact = item } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "doc.text").font(.system(size: 22, weight: .light)).foregroundStyle(Brand.ink)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                                Text("\(item.format.uppercased()) 결과물, 미리보기").font(Brand.suit(10)).foregroundStyle(Brand.gray)
                            }
                            Spacer(minLength: 24); Image(systemName: "arrow.up.right").font(.system(size: 13)).foregroundStyle(Brand.ink)
                        }.padding(.horizontal, 16).frame(width: 360, height: 68, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if let proposal = message.automation {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(proposal.title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                            Text("\(proposal.intervalHours)시간마다, 앱 실행 중").font(Brand.suit(10)).foregroundStyle(Brand.gray)
                        }
                        Spacer()
                        Button(message.approvedAutomationID == nil ? "예약안 확인" : "등록됨") { pendingAutomation = message }
                            .buttonStyle(BrandButtonStyle())
                            .disabled(message.approvedAutomationID != nil || message.status != "complete")
                    }.padding(14).background(ChatPalette.soft, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
                }
                if message.status != "running" {
                    HStack(spacing: 14) {
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) } label: {
                            Image(systemName: "doc.on.doc")
                        }.help("답변 복사")
                        if chat.current.projectID != nil, message.status == "complete", !message.text.isEmpty {
                            Button("프로젝트 자료로 저장") { savingResponse = message; sourceTitle = "\(chat.current.title) · 저장한 답변" }
                        }
                        if ["cancelled", "interrupted"].contains(message.status) { Text("중단됨").font(Brand.suit(10)) }
                        if message.status == "failed" {
                            Button("요청 다시 입력") {
                                if let index = chat.messages.firstIndex(where: { $0.id == message.id }),
                                   let request = chat.messages[..<index].last(where: { $0.role == "user" }) { chat.draft = request.text }
                            }.font(Brand.suit(10))
                        }
                    }.buttonStyle(.plain).foregroundStyle(Brand.gray).font(Brand.suit(11))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Args: message는 승인할 예약안을 포함한 답변이다.
    /// Returns: 요청 내용과 권한 범위를 확인하는 승인 화면.
    /// Raises: 없음.
    private func automationApproval(_ message: ConversationMessage) -> some View {
        let scope = chat.current.scope
        let plugins = (scope.plugins + (scope.useGitHub ? ["GitHub"] : [])).joined(separator: ", ")
        return ChatDialogFrame(eyebrow: "AUTOMATION", title: "예약 작업 등록", width: 600, height: 520, onClose: { pendingAutomation = nil }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let proposal = message.automation {
                        Text(proposal.title).font(Brand.suit(16)).foregroundStyle(Brand.tabText)
                        Text(proposal.prompt).font(Brand.suit(13)).foregroundStyle(Brand.tabText).lineSpacing(6).textSelection(.enabled)
                        Text("\(proposal.intervalHours)시간마다 현재 자료 범위로 실행해요. LLM과 외부 API 사용량이 발생할 수 있어요.")
                            .font(Brand.suit(12)).foregroundStyle(Brand.gray)
                        VStack(alignment: .leading, spacing: 8) {
                            ChatInfoRow(label: "활동 기록", value: scope.useActivity ? "사용" : "미사용")
                            ChatInfoRow(label: "웹 검색", value: scope.useWeb ? "허용" : "미허용")
                            ChatInfoRow(label: "플러그인", value: plugins.isEmpty ? "없음" : plugins)
                            if !scope.paths.isEmpty { ChatInfoRow(label: "연결한 파일", value: scope.paths.joined(separator: "\n")) }
                            ForEach(library.sources(conversationID: chat.current.id, projectID: chat.current.projectID)) { ChatInfoRow(label: "보관 자료", value: $0.title) }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(ChatPalette.soft, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
                        Label("원본 파일 변경, 명령 실행, 메시지 발송은 하지 않아요. 앱 종료나 절전 중에는 실행되지 않아요.", systemImage: "info.circle")
                            .font(Brand.suit(12)).foregroundStyle(Brand.gray)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 27).padding(.vertical, 24)
            }
        } footer: {
            Spacer()
            Button("취소") { pendingAutomation = nil }.buttonStyle(ChatDialogButtonStyle())
            Button("등록") { chat.approve(message); pendingAutomation = nil }.buttonStyle(ChatDialogButtonStyle(primary: true))
        }
    }
}

/// 채팅 화면 안에서 쓰는 보조 색
enum ChatPalette {
    static let soft = Color(hex: 0xF6F5F4)       // 말풍선, 칩, 대화 상자 머리글 바탕
    static let inputLine = Color(hex: 0xD8D2CD)  // 입력 상자 테두리
}

/// 작은 상태 태그: 일부, 예정, 일시 중지됨
struct ChatTag: View {
    let text: String
    var body: some View {
        Text(text).font(Brand.suit(10, .medium)).foregroundStyle(Brand.gray)
            .padding(.horizontal, 5).frame(height: 20)
            .background(ChatPalette.soft, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.line))
    }
}

/// 머리글 오른쪽의 28pt 아이콘 버튼
struct ChatIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 13)).foregroundStyle(Brand.tabText)
                .frame(width: 28, height: 28)
                .background(hovering && enabled ? ChatPalette.soft : .clear, in: RoundedRectangle(cornerRadius: 5))
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }.help(help).accessibilityLabel(help)
    }
}

/// 대화 상자 하단 버튼: 높이 38, primary는 주색 바탕
struct ChatDialogButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Brand.suit(12, .medium))
            .foregroundStyle(primary ? Color.white : Brand.tabText)
            .padding(.horizontal, 14).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 6).fill(primary ? Brand.ink : .white))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(primary ? Brand.ink : Brand.line))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// 대화 상자: 눈썹 글씨와 제목이 있는 머리글, 흰 본문, 하단 버튼 줄
struct ChatDialogFrame<Content: View, Footer: View>: View {
    let eyebrow: String
    let title: String
    var detail: String? = nil
    var width: CGFloat = 600
    var height: CGFloat? = nil
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(eyebrow)
                Text(title).font(Brand.suit(22)).tracking(-0.77).foregroundStyle(Brand.ink).lineLimit(1).padding(.top, 10).padding(.trailing, 30)
                if let detail { Text(detail).font(Brand.suit(12)).foregroundStyle(Brand.gray).padding(.top, 9) }
            }.padding(.horizontal, 27).padding(.top, 25).padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ChatPalette.soft)
                .overlay(alignment: .bottom) { Rectangle().fill(Brand.hairline).frame(height: 1) }
                .overlay(alignment: .topTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Brand.tabText).frame(width: 28, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("닫기").accessibilityLabel("닫기").padding(.top, 19).padding(.trailing, 16)
                }
            content().frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
            HStack(spacing: 10) { footer() }
                .padding(.horizontal, 24).frame(height: 73)
                .background(ChatPalette.soft)
                .overlay(alignment: .top) { Rectangle().fill(Brand.hairline).frame(height: 1) }
        }.frame(width: width, height: height)
    }
}

private struct ChatInfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).font(Brand.suit(11)).foregroundStyle(Brand.gray).frame(width: 72, alignment: .leading)
            Text(value).font(Brand.suit(12)).foregroundStyle(Brand.tabText).textSelection(.enabled)
            Spacer(minLength: 0)
        }
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
        ChatDialogFrame(eyebrow: "SOURCE", title: source.title, width: 600, height: 400, onClose: { dismiss() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !source.location.isEmpty {
                        Text(source.location).font(Brand.suit(11)).foregroundStyle(Brand.gray).textSelection(.enabled)
                    }
                    Text(source.excerpt).font(Brand.suit(13)).foregroundStyle(Brand.tabText).lineSpacing(6).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 27).padding(.vertical, 24)
            }
        } footer: {
            Spacer()
            if let url = URL(string: source.location), ["https", "http"].contains(url.scheme ?? "") {
                Link(destination: url) { HStack(spacing: 6) { Text("원문 열기"); Image(systemName: "arrow.up.right").font(.system(size: 11)) } }
                    .buttonStyle(ChatDialogButtonStyle())
            } else if source.location.hasPrefix("/") {
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: source.location)]) } label: {
                    HStack(spacing: 6) { Text("Finder에서 보기"); Image(systemName: "arrow.up.right").font(.system(size: 11)) }
                }.buttonStyle(ChatDialogButtonStyle())
            }
            Button("닫기") { dismiss() }.buttonStyle(ChatDialogButtonStyle())
        }
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
        ChatDialogFrame(eyebrow: "SCHEDULED WORK", title: "예약 작업",
                        detail: "앱이 켜져 있을 때만 실행돼요. 지난 실행은 한 번만 처리해요.",
                        width: chat.automations.isEmpty ? 600 : 760, height: 505, onClose: { dismiss() }) {
            if chat.automations.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        Image(systemName: "calendar.badge.clock").font(.system(size: 26, weight: .light)).foregroundStyle(Brand.tabText)
                        Text("등록된 예약이 없어요").font(Brand.suit(17, .medium)).foregroundStyle(Brand.ink).padding(.top, 16)
                        Text("채팅에서 반복할 일을 요청하고 예약안을 승인해 주세요.").font(Brand.suit(12)).foregroundStyle(Brand.gray).padding(.top, 10)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button { dismiss() } label: {
                        HStack(spacing: 8) { Text("채팅에서 예약안 만들기"); Image(systemName: "arrow.up.right").font(.system(size: 11)) }
                    }.buttonStyle(ChatDialogButtonStyle()).padding(.bottom, 24)
                }.padding(.horizontal, 27)
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(chat.automations) { job in
                                HStack(spacing: 2) {
                                    Button { selectedID = job.id } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(job.title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink).lineLimit(1)
                                            Text("\(job.intervalHours)시간마다, \(job.lastStatus)")
                                                .font(Brand.suit(10)).foregroundStyle(Brand.gray).lineLimit(1)
                                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    ChatIconButton(systemName: job.enabled ? "pause.fill" : "play.fill", help: job.enabled ? "일시 중지" : "다시 시작") { chat.toggle(job) }
                                    ChatIconButton(systemName: "trash", help: "예약 삭제") { deletingJob = job; confirmDelete = true }
                                }.padding(.leading, 12).padding(.trailing, 4).frame(height: 52)
                                    .background(selected?.id == job.id ? ChatPalette.soft : .clear, in: RoundedRectangle(cornerRadius: 5))
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(selected?.id == job.id ? Brand.line : .clear))
                            }
                        }.padding(12)
                    }.frame(width: 280)
                    Rectangle().fill(Brand.line).frame(width: 1)
                    if let job = selected {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Text(job.title).font(Brand.suit(16)).foregroundStyle(Brand.ink)
                                    ChatTag(text: job.enabled ? "실행 대기" : "일시 중지됨")
                                }
                                Text("요청 내용").font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.top, 4)
                                Text(job.prompt).font(Brand.suit(13)).foregroundStyle(Brand.tabText).lineSpacing(5)
                                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                Rectangle().fill(Brand.line).frame(height: 1).padding(.vertical, 4)
                                ChatInfoRow(label: "실행 간격", value: "\(job.intervalHours)시간마다")
                                ChatInfoRow(label: "자료 범위", value: job.scope.useActivity ? "활동 기록 포함" : "활동 기록 제외")
                                ChatInfoRow(label: "웹 검색", value: job.scope.useWeb ? "사용" : "사용 안 함")
                                ChatInfoRow(label: "플러그인", value: (job.scope.plugins + (job.scope.useGitHub ? ["GitHub"] : [])).joined(separator: ", "))
                                if !job.scope.paths.isEmpty { ChatInfoRow(label: "연결한 파일", value: job.scope.paths.joined(separator: "\n")) }
                                ForEach(chat.library.items.filter { job.scope.libraryIDs.contains($0.id) }) { ChatInfoRow(label: "보관 자료", value: $0.title) }
                                ChatInfoRow(label: "최근 상태", value: job.lastStatus)
                                if job.enabled { ChatInfoRow(label: "다음 실행", value: Date(timeIntervalSince1970: job.nextRun).formatted()) }
                                if let id = job.lastConversationID, let conversation = chat.conversations.first(where: { $0.id == id }) {
                                    Button("최근 실행 보기") { chat.select(conversation); dismiss() }.buttonStyle(ChatDialogButtonStyle()).padding(.top, 6)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        }
                    }
                }
            }
        } footer: {
            Spacer()
            Button("닫기") { dismiss() }.buttonStyle(ChatDialogButtonStyle())
        }
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

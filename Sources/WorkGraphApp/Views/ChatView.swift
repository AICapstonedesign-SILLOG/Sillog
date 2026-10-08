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
    @State private var showSkills = false
    @State private var showAddPanel = false
    @State private var showProjectPicker = false
    @State private var showSkillPicker = false
    @State private var showModelPicker = false
    @State private var searchingChats = false
    @State private var chatQuery = ""
    @EnvironmentObject private var appState: AppState
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
        .sheet(isPresented: $showSkills) { skillSheet }
        .sheet(isPresented: $showPlugins) {   // 페이지를 바꾸지 않고 위에 띄움
            PluginCatalogView(onClose: { showPlugins = false }) { id, example in
                chat.newConversation()
                selectedProjectID = nil
                if id == "github" { chat.current.scope.useGitHub = true }
                else { chat.current.scope.plugins.append(id) }
                chat.saveScope()
                chat.draft = example
                showPlugins = false
            }.frame(minWidth: 860, idealWidth: 960, minHeight: 600, idealHeight: 680)
        }
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
        .onChange(of: appState.chatSheet, initial: true) { _, sheet in openRailSheet(sheet) }
        .onChange(of: projects.projects) { _, values in
            if let selectedProjectID, !values.contains(where: { $0.id == selectedProjectID }) { self.selectedProjectID = nil }
        }
    }

    private var mainContent: some View {
        Group {
            if let project = projects.projects.first(where: { $0.id == selectedProjectID }) {
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
            Group { if chat.messages.isEmpty { ChatEmptyHero().frame(maxWidth: .infinity, maxHeight: .infinity) } else { conversation } }
                .overlay { if showSkillPicker || showProjectPicker || showAddPanel || showModelPicker { Color.black.opacity(0.001).onTapGesture { closeStacks() } } }
            if let error = chat.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(Brand.suit(11)).foregroundStyle(Brand.ink).textSelection(.enabled)
                    .padding(.horizontal, 28).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(ChatPalette.soft)
                    .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
            }
            composer.frame(maxWidth: chat.messages.isEmpty ? 760 : .infinity)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("채팅").font(Brand.suit(23, .semibold)).tracking(-0.805).foregroundStyle(Brand.ink)
                    Spacer()
                    ChatIconButton(systemName: "plus", help: "새 대화") { chat.newConversation(); showPlugins = false; selectedProjectID = nil }
                    ChatIconButton(systemName: "magnifyingglass", help: "대화 검색") { searchingChats.toggle(); if !searchingChats { chatQuery = "" } }
                    ChatIconButton(systemName: "sidebar.left", help: "대화 목록 닫기") { sidebarVisible = false }
                }.buttonStyle(.plain)
                if searchingChats {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Brand.gray)
                        TextField("대화 검색", text: $chatQuery).textFieldStyle(.plain).font(Brand.suit(12))
                            .onExitCommand { searchingChats = false; chatQuery = "" }
                    }.padding(.horizontal, 10).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.7)))
                        .padding(.top, 12)
                }
            }.padding(.horizontal, 24).padding(.top, 27).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 6)
                    LazyVStack(spacing: 5) {
                        ForEach(chat.conversations.filter { $0.projectID == nil && matchesQuery($0) }) { item in conversationRow(item) }
                    }
                    HStack {
                        Eyebrow("프로젝트")
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
                                ForEach(chat.conversations.filter { $0.projectID == project.id && matchesQuery($0) }) { conversation in conversationRow(conversation).padding(.leading, 26) }
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

    /// 왼쪽 아이콘 줄에서 누른 예약, 스킬, 플러그인 창을 띄우고 요청을 비운다
    private func openRailSheet(_ sheet: String?) {
        guard let sheet else { return }
        switch sheet { case "schedules": showSchedules = true; case "skills": showSkills = true; default: showPlugins = true }
        appState.chatSheet = nil
    }

    /// 스킬 고르기: 누르면 이 대화에 쓰고 닫는다
    private var skillSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("스킬").font(Brand.suit(18, .semibold)).foregroundStyle(Brand.ink)
                Spacer()
                ChatIconButton(systemName: "xmark", help: "닫기") { showSkills = false }
            }.padding(.bottom, 14)
            let rows = [("general", "sparkles", "자동 선택", "질문에 맞는 절차를 알아서 고릅니다.")] + chat.skills.map { ($0.id, $0.icon, $0.title, $0.summary) }
            ForEach(rows, id: \.0) { id, icon, title, summary in
                let on = chat.current.skillID == id
                Button { chat.current.skillID = id; showSkills = false } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color(hex: 0x4F7896)).frame(width: 20).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink)
                            Text(summary).font(Brand.suit(11)).foregroundStyle(Brand.gray).lineLimit(2)
                        }
                        Spacer()
                        if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.ink) }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? Brand.sky.opacity(0.18) : .clear))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(22).frame(width: 440)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !sidebarVisible {
                ChatIconButton(systemName: "sidebar.left", help: "대화 목록 열기") { sidebarVisible = true }
                ChatIconButton(systemName: "square.and.pencil", help: "새 대화") { chat.newConversation() }
                Spacer().frame(width: 6)   // 목록 단추와 제목 사이 여백
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(chat.messages.isEmpty ? "새 대화" : chat.current.title).font(Brand.suit(16)).foregroundStyle(Brand.ink).lineLimit(1)
                if let project = projects.projects.first(where: { $0.id == chat.current.projectID }) {
                    Button { openProject(project) } label: {
                        Label(project.title, systemImage: "folder").font(Brand.suit(10)).foregroundStyle(Brand.gray)
                    }.help("프로젝트의 채팅과 소스 보기")
                }
            }
            Spacer()
        }.buttonStyle(.plain).padding(.horizontal, 28).frame(minHeight: 56)
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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if let summary = chat.summaries[chat.current.id]?.text {      // 이 대화 한눈 요약 (질문 눈금 대신)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("요약").font(Brand.suit(10, .medium)).foregroundStyle(Color(hex: 0x5E97C8))
                                Text(summary).font(Brand.suit(13)).foregroundStyle(Brand.tabText).textSelection(.enabled)
                            }
                            .padding(.bottom, 16).frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
                        }
                        ForEach(chat.messages) { message in
                            messageView(message)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.frame(maxWidth: 865).frame(maxWidth: .infinity).padding(.horizontal, 32).padding(.vertical, 24)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: chat.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: chat.current.id) { _, _ in
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
.help(path)
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
            }.padding(.horizontal, 14).padding(.top, 8)
            HStack(spacing: 12) {
                attachmentMenu
                if !isProjectHome { composerToolbar }
                Spacer()
                if !modelName.isEmpty {
                    Button { let v = !showModelPicker; closeStacks(); withAnimation(.easeOut(duration: 0.18)) { showModelPicker = v } } label: {
                        HStack(spacing: 4) {
                            Text(modelLabel).font(Brand.suit(11)).foregroundStyle(showModelPicker ? Brand.ink : Brand.gray).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(Brand.gray)
                        }
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().fill(showModelPicker ? ChatPalette.soft : .clear))   // 열려 있으면 알약 바탕 (Codex)
                        .hoverHighlight(cornerRadius: 14, active: !showModelPicker)
                        .contentShape(Capsule())
                    }.buttonStyle(.plain).help("채팅 모델 바꾸기")
                        .overlay(alignment: .bottomTrailing) {
                            if showModelPicker {
                                modelCard.offset(y: -36)
                                    .transition(.scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity))
                            }
                        }
                }
                sendButton
            }.padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 2)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ChatPalette.inputLine))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    /// 활동 기록, 웹 검색, 플러그인이 기본값(활동 기록만 켬)과 다르면 참
    private var nonDefaultSources: Bool {
        let scope = chat.current.scope
        return !scope.useActivity || scope.useWeb || scope.useGitHub || !scope.plugins.isEmpty
    }

    /// 입력창 위 띠 (Codex 프로젝트 선택처럼): 프로젝트와 스킬을 함께 고른다. 프로젝트는 첫 메시지 전까지만 바꿀 수 있다
    private var contextStrip: some View {
        let project = projects.projects.first(where: { $0.id == chat.current.projectID })
        let skill = chat.skills.first(where: { $0.id == chat.current.skillID })
        let locked = !chat.messages.isEmpty
        return HStack(spacing: 14) {
            Button { let v = !showProjectPicker; closeStacks(); showProjectPicker = v } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder").font(.system(size: 11))
                    Text(project?.title ?? "프로젝트 선택").lineLimit(1)
                }.foregroundStyle(project == nil ? Brand.gray : Brand.ink)
                .padding(.horizontal, 6).frame(height: 24).hoverHighlight(cornerRadius: 6, active: !locked).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(locked)
                .overlay(alignment: .bottomLeading) { if showProjectPicker { ScatterStack(pills: projectPills).offset(y: -30) } }
                .help(locked ? "대화를 시작한 뒤에는 프로젝트를 바꿀 수 없어요" : "이 대화를 넣을 프로젝트")
            Rectangle().fill(Brand.line).frame(width: 1, height: 12)
            Button { let v = !showSkillPicker; closeStacks(); showSkillPicker = v } label: {
                HStack(spacing: 6) {
                    Image(systemName: skill?.icon ?? "sparkles").font(.system(size: 11))   // 고른 스킬의 아이콘
                        .contentTransition(.symbolEffect(.replace))
                    Text(skill?.title ?? "스킬 자동 선택").lineLimit(1)
                }.foregroundStyle(skill == nil ? Brand.gray : Brand.ink)
                .padding(.horizontal, 6).frame(height: 24).hoverHighlight(cornerRadius: 6).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .overlay(alignment: .bottomLeading) { if showSkillPicker { ScatterStack(pills: skillPills).offset(y: -30) } }
            Spacer()
        }
        .font(Brand.suit(11))
        .padding(.horizontal, 14).frame(height: 32)
        .background(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12).fill(Color(hex: 0xF4F2F0)))
    }

    private var composerToolbar: some View {
        let busy = chat.activeMessage?.conversationID == chat.current.id
        return HStack(spacing: 10) {
            Button { showSources = true } label: {
                HStack(spacing: 4) {
                    Text("자료")
                    if nonDefaultSources { Circle().fill(Brand.sky).frame(width: 5, height: 5) }
                }.foregroundStyle(Brand.gray).padding(.horizontal, 8).frame(height: 26).hoverHighlight(cornerRadius: 13).contentShape(Rectangle())
            }
        }.font(Brand.suit(11)).buttonStyle(.plain).disabled(busy)
    }

    private var composer: some View {
        Group {
            if isProjectHome {
                composerBox.frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    contextStrip.padding(.horizontal, 20)
                    composerBox
                }.padding(.top, 12).padding(.horizontal, 27).padding(.bottom, 16)
                    .background(.white)
                    }
        }.popover(isPresented: $showSources) { sourceOptions }
    }

    /// 대화 제목 검색 (사이드바 검색 단추)
    private func matchesQuery(_ item: ChatConversation) -> Bool {
        let q = chatQuery.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || item.title.localizedCaseInsensitiveContains(q)
    }

    private func closeStacks() { showSkillPicker = false; showProjectPicker = false; showAddPanel = false; showModelPicker = false }

    /// 모델 카드 (Codex 모델 선택 구조): 회색 제목 "모델 선택", 모델 줄마다 이름과 고른 것 체크, 맨 아래 모델 설정
    private var modelCard: some View {
        let pills = modelPills
        let models = pills.filter { $0.id != "settings" && !$0.id.hasPrefix("err") && $0.id != "loading" }
        let notes = pills.filter { $0.id.hasPrefix("err") || $0.id == "loading" }
        return VStack(alignment: .leading, spacing: 2) {
            Text("모델 선택").font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)
            ForEach(models) { pill in CardRow(title: pill.title, checked: pill.checked, action: pill.action) }
            ForEach(notes) { pill in
                Text(pill.title).font(Brand.suit(11)).foregroundStyle(Brand.gray).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
            Rectangle().fill(Brand.line).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 6)
            CardRow(title: "모델 설정…", checked: false) { closeStacks(); openSettings() }
        }
        .padding(6).frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.black.opacity(0.07)))
        .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
    }

    /// + 카드 (Codex 추가 구조): "추가" 구역과 "플러그인" 구역, 줄마다 아이콘, 이름, 회색 설명
    private var addCard: some View {
        let detail: [String: String] = isProjectHome
            ? ["upP": "이 프로젝트의 모든 채팅이 참고", "libP": "보관한 자료를 프로젝트 소스로", "linkP": "고친 내용이 그대로 반영돼요", "src": "활동 기록, 웹 검색 사용 여부"]
            : ["up": "이 채팅에서만", "lib": "이 채팅에서만", "link": "고친 내용이 그대로 반영돼요"]
        return VStack(alignment: .leading, spacing: 2) {
            Text(isProjectHome ? "소스 추가" : "추가").font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 4)
            ForEach(addPills) { p in CardRow(icon: p.icon, title: p.title, detail: detail[p.id], checked: p.checked, action: p.action) }
        }
        .padding(6).frame(width: 400)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.black.opacity(0.07)))
        .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
    }

    /// 입력창 모델 단추 글자: 확인된 목록의 표시 이름, 없으면 slug를 다듬은 이름
    private var modelLabel: String {
        guard appState.settings.chatProvider == "codex" else { return modelName }
        return appState.chatCodexModels.first { $0.slug == modelName }?.displayName ?? Self.prettyModel(modelName)
    }

    /// "gpt-5.6-luna" → "GPT-5.6-Luna": 단어 첫 글자만 대문자, gpt 같은 약어는 전부 대문자
    static func prettyModel(_ slug: String) -> String {
        slug.split(separator: "-").map { part in
            let p = String(part)
            if ["gpt", "o", "llm"].contains(p.lowercased()) || p.first?.isNumber == true { return p.uppercased() }
            return p.prefix(1).uppercased() + p.dropFirst()
        }.joined(separator: "-")
    }

    /// 모델 알약: 확인된 모델 목록(지금 모델에 체크), 오류는 한 줄 안내, 맨 끝 모델 설정
    private var modelPills: [ScatterPill] {
        var list: [ScatterPill] = []
        if appState.settings.chatProvider == "codex" {
            let current = appState.settings.chatCodexModel
            var models = appState.chatCodexModels.map { ($0.slug, $0.displayName) }
            if !current.isEmpty, !models.contains(where: { $0.0 == current }) { models.insert((current, Self.prettyModel(current)), at: 0) }
            list += models.map { slug, title in ScatterPill(id: slug, icon: "cpu", title: title, checked: slug == current) {
                appState.selectChatModel(slug)
                withAnimation(.easeOut(duration: 0.15)) { showModelPicker = false }
            } }
            if appState.codexModelsLoading { list.append(ScatterPill(id: "loading", icon: "hourglass", title: "모델 목록을 불러오는 중") {}) }
            if let error = appState.chatCodexModelsError {
                list += error.split(separator: "\n").prefix(2).enumerated().map { i, line in ScatterPill(id: "err\(i)", icon: "exclamationmark.circle", title: String(line)) {} }
            }
        } else {
            list.append(ScatterPill(id: "server", icon: "server.rack", title: "\(modelName), 직접 연결한 서버", checked: true) {})
        }
        list.append(ScatterPill(id: "settings", icon: "gearshape", title: "모델 설정") { closeStacks(); openSettings() })
        return list
    }

    /// 스킬 알약: 자동 선택 + 스킬
    private var skillPills: [ScatterPill] {
        [ScatterPill(id: "general", icon: "sparkles", title: "자동 선택", checked: chat.current.skillID == "general") { chat.current.skillID = "general"; closeStacks() }]
        + chat.skills.map { item in ScatterPill(id: item.id, icon: item.icon, title: item.title, checked: chat.current.skillID == item.id) { chat.current.skillID = item.id; closeStacks() } }
    }

    /// 프로젝트 알약: 없음, 프로젝트들, 새 프로젝트
    private var projectPills: [ScatterPill] {
        [ScatterPill(id: "none", icon: "folder.badge.minus", title: "프로젝트 없음", checked: chat.current.projectID == nil) { chat.current.projectID = nil; closeStacks() }]
        + projects.projects.map { item in ScatterPill(id: item.id, icon: "folder", title: item.title, checked: chat.current.projectID == item.id) { chat.current.projectID = item.id; closeStacks() } }
        + [ScatterPill(id: "new", icon: "plus", title: "새 프로젝트") { closeStacks(); showNewProject = true }]
    }

    /// + 알약: 자료 추가, 프로젝트, 스킬, 플러그인
    /// + 항목: 파일과 소스만 (플러그인은 왼쪽 아이콘 줄에 있다). 프로젝트 화면에서는 프로젝트 소스로 넣는 항목이 먼저
    private var addPills: [ScatterPill] {
        if isProjectHome, let project = projects.projects.first(where: { $0.id == selectedProjectID }) {
            return [ScatterPill(id: "upP", icon: "arrow.up.doc", title: "파일 올리기") { closeStacks(); chat.uploadFiles(projectWide: true) },
                    ScatterPill(id: "libP", icon: "tray.full", title: "보관함에서 가져오기") { closeStacks(); shareLibrarySelection = true; showLibraryPicker = true },
                    ScatterPill(id: "linkP", icon: "folder.badge.plus", title: "폴더 연결") { closeStacks(); projects.connectFiles(project) },
                    ScatterPill(id: "src", icon: "slider.horizontal.3", title: "참고할 자료 설정") { closeStacks(); showSources = true }]
        }
        var list = [ScatterPill(id: "up", icon: "arrow.up.doc", title: "파일 업로드") { closeStacks(); chat.uploadFiles() },
                    ScatterPill(id: "lib", icon: "tray.full", title: "보관함에서 선택") { closeStacks(); shareLibrarySelection = false; showLibraryPicker = true }]
        if chat.current.projectID != nil {
            list += [ScatterPill(id: "upP", icon: "arrow.up.doc.on.clipboard", title: "프로젝트 전체에 파일 업로드") { closeStacks(); chat.uploadFiles(projectWide: true) },
                     ScatterPill(id: "libP", icon: "tray.2", title: "프로젝트 전체에 보관함 자료 추가") { closeStacks(); shareLibrarySelection = true; showLibraryPicker = true }]
        }
        list.append(ScatterPill(id: "link", icon: "link", title: "원본 파일, 폴더 연결") { closeStacks(); chat.connectFiles() })
        return list
    }

    private var attachmentMenu: some View {
        Button { let v = !showAddPanel; closeStacks(); withAnimation(.easeOut(duration: 0.15)) { showAddPanel = v } } label: {
            Image(systemName: "plus").font(.system(size: 15)).foregroundStyle(Brand.gray).frame(width: 28, height: 28).hoverHighlight(cornerRadius: 14).contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .overlay(alignment: isProjectHome ? .topLeading : .bottomLeading) {   // 프로젝트 화면은 입력창이 위에 있어 아래로 연다
                if showAddPanel {
                    addCard.offset(y: isProjectHome ? 34 : -34)
                        .transition(.scale(scale: 0.96, anchor: isProjectHome ? .topLeading : .bottomLeading).combined(with: .opacity))
                }
            }
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
                .background(Brand.ink.opacity(chat.running || !empty ? 1 : 0.38), in: Circle())
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
            Text("연결한 원본 파일·폴더").font(.system(size: 13, weight: .medium))
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
                Text(message.text).font(Brand.suit(12)).foregroundStyle(Brand.tabText).lineSpacing(5).textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(ChatPalette.soft, in: RoundedRectangle(cornerRadius: 6))
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if chat.current.skillID != "general", let skill = chat.skills.first(where: { $0.id == chat.current.skillID }) {
                    BrandBadge(skill.title)
                }
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
                } else if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ChatMessageText(text: message.text, sources: message.sources) { source = $0 }
                }
                if !message.sources.isEmpty {
                    SourceList(sources: message.sources,
                               cited: ChatMessageText.citations(in: message.text, sources: message.sources).1) { source = $0 }
                }
                ForEach(message.artifacts) { item in
                    ArtifactCard(item: item) { artifact = item }
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
        return ChatDialogFrame(title: "예약 작업 등록", width: 600, height: 520, onClose: { pendingAutomation = nil }) {
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
                        Text("원본 파일 변경, 명령 실행, 메시지 발송은 하지 않아요. 앱 종료나 절전 중에는 실행되지 않아요.")
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

/// 대화 상자: 제목이 있는 머리글, 흰 본문, 하단 버튼 줄
struct ChatDialogFrame<Content: View, Footer: View>: View {
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
                Text(title).font(Brand.suit(22)).tracking(-0.77).foregroundStyle(Brand.ink).lineLimit(1).padding(.trailing, 30)
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

private struct ChatSourceSheet: View {
    let source: ChatSource
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ChatDialogFrame(title: source.title, width: 600, height: 400, onClose: { dismiss() }) {
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
        ChatDialogFrame(title: "예약 작업",
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

/// 빈 대화 가운데: 브랜드 로고(앱 아이콘)와 질문 한 줄 (Codex 첫 화면 구조)
private struct ChatEmptyHero: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: 64, height: 64)
            Text("무엇을 만들까요?").font(Brand.suit(26, .medium)).tracking(-0.6).foregroundStyle(Brand.ink)
        }
    }
}

/// 상자 없이 떠오르는 알약 한 개
struct ScatterPill: Identifiable {
    let id: String
    let icon: String
    let title: String
    var checked = false
    let action: () -> Void
}

/// 단추 위로 알약이 하나씩 흩뿌려지며 쌓인다 (Dock 스택처럼 바깥 상자 없이, 기울기는 아주 약하게). 첫 알약이 단추에 가장 가깝다
private struct ScatterStack: View {
    let pills: [ScatterPill]
    var trailing = false                                              // 오른쪽 단추(모델)는 오른쪽 끝을 맞추고 왼쪽으로 비껴 쌓는다
    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 7) {
            ForEach(Array(pills.enumerated().reversed()), id: \.element.id) { i, pill in
                PillButton(pill: pill).modifier(ScatterPop(order: i, trailing: trailing))
            }
        }
        .fixedSize()
    }
}

private struct PillButton: View {
    let pill: ScatterPill
    @State private var hover = false
    var body: some View {
        Button(action: pill.action) {
            HStack(spacing: 8) {
                Image(systemName: pill.icon).font(.system(size: 11)).foregroundStyle(Brand.tabText)
                Text(pill.title).font(Brand.suit(12)).foregroundStyle(Brand.ink).lineLimit(1)
                if pill.checked { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: 0x4F7896)) }
            }
            .padding(.horizontal, 13).frame(height: 30)
            .background(Capsule().fill(.ultraThinMaterial))
            .background(Capsule().fill(Color.white.opacity(hover ? 0.95 : 0.78)))
            .overlay(Capsule().strokeBorder(pill.checked ? Brand.sky : Color.black.opacity(0.06)))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .scaleEffect(hover ? 1.04 : 1, anchor: .leading)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

/// 단추 자리에서 위로 차례차례 튀어 오르며, 위로 갈수록 오른쪽으로 살짝 비껴 뿌려진 모양
private struct ScatterPop: ViewModifier {
    let order: Int
    var trailing = false
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        let lean = CGFloat(order) * (trailing ? -3 : 3)                                  // 위로 갈수록 오른쪽으로
        let tilt = order == 0 ? 0 : (order % 2 == 0 ? -1.2 : 1.2)       // 줄마다 아주 살짝 다르게 기울어 흩뿌린 느낌
        content
            .rotationEffect(.degrees(shown ? tilt : 0), anchor: trailing ? .trailing : .leading)
            .offset(x: shown ? lean : 0, y: shown ? 0 : CGFloat(order + 1) * 16)
            .scaleEffect(shown ? 1 : 0.6, anchor: trailing ? .bottomTrailing : .bottomLeading)
            .opacity(shown ? 1 : 0)
            .onAppear {
                if reduce { shown = true; return }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8).delay(Double(order) * 0.012)) { shown = true }
            }
    }
}

/// Codex 카드 한 줄: 커서를 대면 옅은 회색 둥근 바탕, 고른 것은 오른쪽 체크
private struct CardRow: View {
    var icon: String? = nil
    let title: String
    var detail: String? = nil
    let checked: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Brand.tabText).frame(width: 16) }
                Text(title).font(Brand.suit(13)).foregroundStyle(Brand.ink).lineLimit(1)
                if let detail { Text(detail).font(Brand.suit(11)).foregroundStyle(Brand.gray).lineLimit(1) }
                Spacer(minLength: 12)
                if checked { Image(systemName: "checkmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.ink) }
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(hover || checked ? ChatPalette.soft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// 결과물 카드: 하늘색 빛이 테두리를 따라 천천히 돌고(그래프 AI 검색과 같은 색), 커서를 대면 살짝 떠오른다
private struct ArtifactCard: View {
    let item: ChatArtifact
    let action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: item.format.lowercased() == "html" ? "safari" : "doc.text")
                    .font(.system(size: 17)).foregroundStyle(Color(hex: 0x4F7896))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0xEAF3FA)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(Brand.suit(13, .semibold)).foregroundStyle(Brand.ink).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.format.uppercased()).font(Brand.suit(9, .semibold)).foregroundStyle(Color(hex: 0x4F7896))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: 0xEAF3FA)))
                        Text("눌러서 미리보기").font(Brand.suit(10)).foregroundStyle(Brand.gray)
                    }
                }
                Spacer(minLength: 24)
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: 0x4F7896))
                    .offset(x: hover ? 2 : 0, y: hover ? -2 : 0)
            }
            .padding(.horizontal, 14).frame(width: 380, height: 72, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: 0xB4D0E4).opacity(0.7), lineWidth: 1))   // 늘 보이는 옅은 하늘 테두리
            .overlay {                                                                                                   // 하늘빛이 천천히 숨 쉬듯 밝아졌다 어두워진다
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduce)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let pulse = reduce ? 0.6 : 0.5 + 0.5 * sin(t * 2 * .pi / 3.2)
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(hex: 0x6FA8D6).opacity(0.35 + 0.5 * pulse), lineWidth: 1.5)
                        .shadow(color: Color(hex: 0x9CCBF0).opacity(0.5 * pulse), radius: 6)
                }
                .allowsHitTesting(false)
            }
            .shadow(color: Color(hex: 0x6FA8D6).opacity(hover ? 0.28 : 0.14), radius: hover ? 14 : 8, y: hover ? 5 : 2)
            .offset(y: hover ? -1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.25)) { hover = h } }
        .help("\(item.title) 미리보기")
    }
}

/// 출처 줄: 답에서 인용한 자료 앞 4개만 칩으로, 나머지는 "출처 전체 N개" 단추로 따로 띄운 상자에서 본다
private struct SourceList: View {
    let sources: [ChatSource]
    let cited: [ChatSource]
    let open: (ChatSource) -> Void
    @State private var showAll = false

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(cited.prefix(4).enumerated()), id: \.element.id) { i, item in
                Button { open(item) } label: {
                    HStack(spacing: 6) {
                        Text("\(i + 1)").font(Brand.jost(9)).foregroundStyle(Color(hex: 0x4F7896))
                        Text(item.title).font(Brand.suit(10)).foregroundStyle(Brand.tabText).lineLimit(1)
                    }.padding(.horizontal, 8).frame(height: 26).frame(maxWidth: 190)
                        .hoverHighlight(cornerRadius: 6)
                        .background(ChatPalette.soft, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).help(item.title)
            }
            if sources.count > min(cited.count, 4) {
                Button { showAll = true } label: {
                    HStack(spacing: 4) {
                        Text(cited.isEmpty ? "조회한 자료 \(sources.count)개" : "출처 전체 \(sources.count)개")
                        Image(systemName: "arrow.up.forward.square").font(.system(size: 9))
                    }.font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.horizontal, 6).frame(height: 26).hoverHighlight(cornerRadius: 6).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showAll) {
            SourceBox(sources: sources, cited: cited) { item in
                showAll = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { open(item) }   // 상자가 닫힌 뒤 출처 창을 연다
            } close: { showAll = false }
        }
    }
}

/// 출처 종류: id 앞머리로 나눈다 (ChatMessageText 인용 형식과 같은 접두사)
private enum SourceKind: Int, CaseIterable {
    case record, conversation, file, web, mail, drive, notion, git, digest, other
    init(_ id: String) {
        let head = id.hasPrefix("http") ? "web" : String(id.split(separator: ":").first ?? "")
        switch head {
        case "node", "observation", "card", "usage": self = .record
        case "chat", "conversation", "message": self = .conversation
        case "library", "file": self = .file
        case "web": self = .web
        case "gmail": self = .mail
        case "drive": self = .drive
        case "notion": self = .notion
        case "git": self = .git
        case "digest": self = .digest
        default: self = .other
        }
    }
    var title: String {
        switch self {
        case .record: "활동 기록"; case .conversation: "지난 대화"; case .file: "파일, 보관함"; case .web: "웹"
        case .mail: "Gmail"; case .drive: "Google Drive"; case .notion: "Notion"; case .git: "GitHub"; case .digest: "기간 요약"; case .other: "기타"
        }
    }
    var icon: String {
        switch self {
        case .record: "clock"; case .conversation: "bubble.left"; case .file: "doc"; case .web: "globe"
        case .mail: "envelope"; case .drive: "externaldrive"; case .notion: "note.text"; case .git: "chevron.left.forwardslash.chevron.right"
        case .digest: "calendar"; case .other: "questionmark.square"
        }
    }
}

/// 출처 상자: 검색 칸, 위에 "전체 / 답에 인용" 고르기와 종류 칩, 아래는 종류별 구역(인용한 것이 먼저, 하늘 번호)
private struct SourceBox: View {
    let sources: [ChatSource]
    let cited: [ChatSource]
    let open: (ChatSource) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var citedOnly = false
    @State private var kind: SourceKind?

    var body: some View {
        let number = Dictionary(uniqueKeysWithValues: cited.enumerated().map { ($0.element.id, $0.offset + 1) })
        let q = query.trimmingCharacters(in: .whitespaces)
        let shown = sources.filter { s in
            (q.isEmpty || s.title.localizedCaseInsensitiveContains(q) || s.location.localizedCaseInsensitiveContains(q))
                && (!citedOnly || number[s.id] != nil) && (kind == nil || SourceKind(s.id) == kind)
        }
        let groups = Dictionary(grouping: shown, by: { SourceKind($0.id) })
        let kinds = Dictionary(grouping: sources, by: { SourceKind($0.id) }).keys.sorted { $0.rawValue < $1.rawValue }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("출처").font(Brand.suit(18, .semibold)).foregroundStyle(Brand.ink)
                Text("\(sources.count)개 중 인용 \(cited.count)개").font(Brand.suit(12)).foregroundStyle(Brand.gray)
                Spacer()
                ChatIconButton(systemName: "xmark", help: "닫기", action: close).keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Brand.gray)
                TextField("제목이나 위치로 찾기", text: $query).textFieldStyle(.plain).font(Brand.suit(12))
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(ChatPalette.soft))
            .padding(.top, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterChip("답에 인용", icon: "quote.opening", on: citedOnly) { citedOnly.toggle() }
                    Rectangle().fill(Brand.line).frame(width: 1, height: 14)
                    filterChip("전체", icon: nil, on: kind == nil) { kind = nil }
                    ForEach(kinds, id: \.self) { k in filterChip(k.title, icon: k.icon, on: kind == k) { kind = kind == k ? nil : k } }
                }.padding(.vertical, 10)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(groups.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { k in
                        let items = groups[k]!.sorted { (number[$0.id] ?? .max) < (number[$1.id] ?? .max) }
                        HStack(spacing: 6) {
                            Image(systemName: k.icon).font(.system(size: 10))
                            Text("\(k.title) \(items.count)")
                        }.font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 4)
                        ForEach(items) { s in
                            let n = number[s.id]
                            SourceBoxRow(source: s, number: n.map(String.init) ?? "", strong: n != nil) { open(s) }
                        }
                    }
                    if shown.isEmpty { Text("찾는 출처가 없어요").font(Brand.suit(12)).foregroundStyle(Brand.gray).padding(.vertical, 20) }
                }
            }
        }
        .padding(20).frame(width: 560, height: 520)
    }

    private func filterChip(_ title: String, icon: String?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 9)) }
                Text(title)
            }
            .font(Brand.suit(11)).foregroundStyle(on ? Color(hex: 0x24150F) : Brand.tabText)
            .padding(.horizontal, 10).frame(height: 26)
            .background(Capsule().fill(on ? Color(hex: 0xEAF3FA) : .clear))
            .overlay(Capsule().strokeBorder(on ? Color(hex: 0xB4D0E4) : Brand.line))
            .contentShape(Capsule())
        }.buttonStyle(.plain)
    }
}

private struct SourceBoxRow: View {
    let source: ChatSource
    let number: String
    let strong: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number).font(Brand.jost(10)).foregroundStyle(strong ? Color(hex: 0x4F7896) : Brand.gray).frame(width: 18, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title).font(Brand.suit(12, strong ? .medium : .regular)).foregroundStyle(strong ? Brand.ink : Brand.tabText).lineLimit(1)
                    if !source.location.isEmpty { Text(source.location).font(Brand.suit(10)).foregroundStyle(Brand.gray).lineLimit(1).truncationMode(.middle) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(hover ? ChatPalette.soft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

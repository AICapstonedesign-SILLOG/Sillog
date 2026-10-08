import AppKit
import ServiceManagement
import SwiftUI
import WorkGraphCollectors
import WorkGraphCore

/// 설정 탭: 왼쪽 유리 사이드바(맨 위 기록 자료 3개, 선 아래 일반, AI 연결, 채팅 묶음)와 오른쪽 내용. Figma ST-01~06, ST-W1~W8.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var launchAtLogin = false
    @State private var launchStatusLoaded = false
    @State private var launchError: String?
    @State private var chatSeparate = false

    private var section: Section { state.settingsSection }

    enum Section: CaseIterable {
        case fileList, library, activity                 // 기록 자료: 예전 파일, 보관함, 활동 로그 탭
        case record, ai                                  // 일반 = 권한, 수집, 개인정보와 저장 공간, 앱 실행을 한 쪽에
        case projects, schedules, skills, plugins        // 채팅 기능 관리 (채팅 화면의 + 판, 스킬, 예약, 프로젝트와 같은 내용)
        var title: String {
            switch self {
            case .record: "일반"
            case .ai: "AI 연결"
            case .plugins: "플러그인"
            case .skills: "스킬"
            case .schedules: "예약 작업"
            case .projects: "프로젝트"
            case .fileList: "파일"
            case .library: "보관함"
            case .activity: "활동 로그"
            }
        }
        var icon: String {
            switch self {
            case .record: "slider.horizontal.3"     // 설정 탭 톱니와 겹치지 않게
            case .ai: "sparkles"
            case .plugins: "powerplug"
            case .skills: "sparkles"
            case .schedules: "clock"
            case .projects: "folder.badge.person.crop"
            case .fileList: "folder"
            case .library: "tray.full"
            case .activity: "list.bullet.rectangle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Group {
                switch section {
                case .fileList: FilesView()                  // 세 화면은 자기 머리말이 있어 그대로 넣는다
                case .library: if let chat = state.chat { LibraryView(library: chat.library, projects: chat.projects) } else { Color.white }
                case .activity: ActivityLogView()
                case .plugins:
                    PluginCatalogView(onClose: { state.settingsSection = .ai }, showsClose: false) { id, example in   // 채팅에서 써 보기
                        guard let chat = state.chat else { return }
                        chat.newConversation()
                        if id == "github" { chat.current.scope.useGitHub = true } else { chat.current.scope.plugins.append(id) }
                        chat.saveScope(); chat.draft = example
                        state.selectedTab = .chat
                    }
                default:
                    VStack(spacing: 0) {
                        BrandPageHeader(title: section.title)
                        ScrollView {
                            content
                                .padding(.horizontal, 34)
                                .padding(.bottom, 40)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: state.settings) { _, _ in state.applySettings() }
        .onChange(of: state.settings.llmProvider) { _, _ in state.updateCodexModelProviders() }
        .onChange(of: state.settings.chatProvider) { _, _ in state.updateCodexModelProviders() }
        .onAppear { state.refreshCodexStatus() }
        .task {
            // 로그인 항목 상태 조회는 수 초 걸릴 수 있는 동기 XPC 호출이라 메인 스레드 밖에서 읽는다.
            let enabled = await Task.detached(priority: .utility) { SMAppService.mainApp.status == .enabled }.value
            launchAtLogin = enabled
            try? await Task.sleep(nanoseconds: 100_000_000)
            launchStatusLoaded = true
        }
    }

    // MARK: 사이드바

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {                                        // 구역이 많아 창이 낮으면 목록만 스크롤
                VStack(spacing: 2) {
                    VStack(spacing: 2) {                        // 기록 자료: 맨 위, 진한 제목과 글씨로 강조
                        Text("기록 자료").font(Brand.suit(11, .semibold)).foregroundStyle(Brand.ink)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 13).padding(.top, 4).padding(.bottom, 4)
                        ForEach([Section.fileList, .library, .activity], id: \.self) { sidebarRow($0, strong: true) }
                    }
                    Rectangle().fill(Brand.line).frame(height: 1).padding(.vertical, 12).padding(.horizontal, 4)
                    ForEach([Section.record, .ai], id: \.self) { sidebarRow($0) }
                    Text("채팅").font(Brand.suit(10, .medium)).foregroundStyle(Brand.gray)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 13).padding(.top, 18).padding(.bottom, 4)
                    ForEach([Section.projects, .schedules, .skills, .plugins], id: \.self) { sidebarRow($0) }
                }
                .padding(.horizontal, 12).padding(.top, 12)
            }
        }
        .frame(width: 234)
        .frame(maxHeight: .infinity)
        .brandGlass()
        .overlay(alignment: .trailing) { Rectangle().fill(Brand.hairline).frame(width: 1) }
    }

    /// 사이드바 한 줄. strong 이면 기록 자료 줄: 아이콘과 글씨를 선택 안 됐을 때도 진하게
    private func sidebarRow(_ item: Section, strong: Bool = false) -> some View {
        let on = section == item
        return Button { state.settingsSection = item } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon).font(.system(size: 12))
                    .foregroundStyle(on || strong ? Brand.ink : Brand.gray).frame(width: 16)
                Text(item.title)
                    .font(Brand.suit(12, on || strong ? .medium : .regular))
                    .foregroundStyle(on || strong ? Brand.ink : Brand.tabText)
                if item == .fileList, state.pendingFileSuggestions > 0 { FileBadge(count: state.pendingFileSuggestions) }
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .hoverHighlight(cornerRadius: 8, active: !on)
            .glassPill(on)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 내용

    @ViewBuilder private var content: some View {
        switch section {
        case .record: record
        case .ai: aiConnection
        case .skills: if let chat = state.chat { SkillSettings(chat: chat) }
        case .schedules: if let chat = state.chat { ScheduleSettings(chat: chat) }
        case .projects: if let chat = state.chat { ProjectSettings(projects: chat.projects, chat: chat) }
        case .plugins, .fileList, .library, .activity: EmptyView()
        }
    }

    /// 일반: 예전 권한, 수집, 개인정보와 저장 공간, 일반 네 구역을 한 쪽에 잇는다
    private var record: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("권한"); permissions
            SectionLabel("수집"); collection
            privacy
            SectionLabel("앱 실행"); general
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
            permissionTile("손쉬운 사용", icon: "hand.raised",
                           detail: state.status.accessibility ? "창 제목, 주소, 문서 경로, 화면 텍스트를 읽어요." : "꺼져 있어 지금은 앱 이름만 기록하고 있어요.",
                           granted: state.status.accessibility) {
                _ = Permissions.accessibility(prompt: true)
                Permissions.openSettings(.accessibility)
            }
            permissionTile("화면 기록", icon: "camera.viewfinder",
                           detail: state.status.screenRecording ? "스크린샷을 남기고, 글자를 읽을 수 없는 화면은 OCR로 읽어요." : "꺼져 있어 스크린샷과 화면 카드를 만들지 못해요.",
                           granted: state.status.screenRecording) {
                Permissions.requestScreenRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Permissions.openSettings(.screenRecording) }
            }
            permissionTile("알림", icon: "bell", detail: "파일 정리 제안을 알려요. 꺼져 있어도 파일 구역에서 볼 수 있어요.", granted: !state.notificationsDenied) {
                SuggestionNotifier.openSystemSettings()
            }
            }
            .padding(.top, 4)
            InfoLine("화면 기록은 허용한 뒤 앱을 다시 실행해 주세요.")
        }
    }

    /// 권한 하나를 한눈에: 이름, 허용 상태(아이콘과 글), 하는 일 또는 꺼졌을 때 못 하는 일, 허용 단추
    private func permissionTile(_ title: String, icon: String, detail: String, granted: Bool, request: @escaping () -> Void) -> some View {
        let color = granted ? ActivityLogView.okColor : ActivityLogView.failColor
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Brand.ink).frame(width: 18)
                Text(title).font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink)
                Spacer(minLength: 4)
                Label(granted ? "허용됨" : "꺼짐", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(Brand.suit(11, .semibold)).foregroundStyle(color)
            }
            Text(detail).font(Brand.suit(11)).foregroundStyle(Brand.tabText).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            Spacer(minLength: 12)
            if !granted { Button("허용하기", action: request).buttonStyle(BrandButtonStyle()) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(granted ? Brand.paper : ActivityLogView.failColor.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(granted ? Brand.line : ActivityLogView.failColor.opacity(0.25)))
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingCard {
            SettingRow("화면 텍스트 읽기", detail: "텍스트가 부족하면 OCR로 보충해요.") {
                Toggle("", isOn: $state.settings.captureText).toggleStyle(BrandSwitchStyle())
            }
            SettingRow("스크린샷 저장", detail: "활성 창만 저장해요. 끄면 화면 내용 기록도 꺼져요.") {
                Toggle("", isOn: $state.settings.captureScreenshots).toggleStyle(BrandSwitchStyle())
            }
            SettingRow("화면 내용 기록", detail: "대표 화면 이미지를 AI로 보내 화면 기억 카드를 만들어요.") {
                Toggle("", isOn: $state.settings.screenCards).toggleStyle(BrandSwitchStyle())
                    .disabled(!state.settings.captureScreenshots)
            }
            SettingRow("다운로드 폴더 새 파일 기록", detail: "다운로드 파일과 출처 URL을 기록해요.") {
                Toggle("", isOn: $state.settings.watchDownloads).toggleStyle(BrandSwitchStyle())
            }
            SettingRow("AI 코딩 도구 대화 읽기", detail: "Claude Code와 Codex CLI에 입력한 메시지를 읽어요.") {
                Toggle("", isOn: $state.settings.readChatLogs).toggleStyle(BrandSwitchStyle())
            }
            SettingRow("5분마다 자동으로 정리", detail: "쌓인 기록을 연결한 AI 계정으로 보내 업무를 정리해요.") {
                Toggle("", isOn: $state.settings.batchEnabled).toggleStyle(BrandSwitchStyle())
            }
            }
            InfoLine("자동 정리를 꺼도 ‘지금 정리’를 누르면 기록이 전송돼요.")
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExcludedAppsView()
            StorageSettingsView()
            SectionLabel("저장 위치")
            SettingCard {
                SettingRow("기록 폴더", detail: state.databasePath) {
                    Button("Finder에서 보기") { state.revealDataFolder() }.buttonStyle(BrandButtonStyle())
                }
            }
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingCard {
            SettingRow("Dock 아이콘 표시", detail: "Dock에 Sillog를 표시해요.") {
                Toggle("", isOn: $state.settings.showDockIcon).toggleStyle(BrandSwitchStyle())
            }
            SettingRow("로그인 시 자동 실행", detail: "Mac에 로그인하면 메뉴 막대에서 시작해요.") {
                Toggle("", isOn: $launchAtLogin).toggleStyle(BrandSwitchStyle())
                    .disabled(!launchStatusLoaded)
                    .onChange(of: launchAtLogin) { _, enabled in if launchStatusLoaded { setLaunchAtLogin(enabled) } }
            }
            }
            if let launchError {
                Text(launchError).font(Brand.suit(11)).foregroundStyle(Brand.text).padding(.vertical, 12)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = "자동 실행을 바꾸지 못했어요. build/Sillog.app으로 실행했는지 확인해 주세요. (\(error.localizedDescription))"
        }
    }

    // MARK: AI 연결

    /// 채팅이 정리와 다른 연결을 쓰는지: 저장된 값이 서로 다르면 켠 채로 시작한다.
    private var chatDiffers: Bool {
        let c = state.settings
        return c.chatProvider != c.llmProvider || c.chatModel != c.llmModel || c.chatBaseURL != c.llmBaseURL
            || c.chatAPIKey != c.llmAPIKey || c.chatCodexModel != c.codexModel
    }

    /// 같은 연결을 쓰는 동안 채팅 값을 정리 값에 맞춘다 (저장 키는 그대로).
    private func syncChat() {
        guard !chatSeparate else { return }
        let c = state.settings
        guard chatDiffers else { return }
        state.settings.chatProvider = c.llmProvider; state.settings.chatModel = c.llmModel
        state.settings.chatBaseURL = c.llmBaseURL; state.settings.chatAPIKey = c.llmAPIKey
        state.settings.chatCodexModel = c.codexModel
    }

    private var aiConnection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ConnectionSection(
                provider: $state.settings.llmProvider,
                openAIModel: $state.settings.llmModel, baseURL: $state.settings.llmBaseURL, apiKey: $state.settings.llmAPIKey,
                modelPlaceholder: "gpt-5.4-mini", urlPlaceholder: "http://localhost:5010/v1",
                codexModel: $state.settings.codexModel, models: state.codexModels, modelsError: state.codexModelsError,
                testLabel: "연결 확인", testing: false, testResult: state.llmTestResult,
                test: { Task { await state.testLLM() } }, note: nil, showAccount: true)
            SectionLabel("채팅")
            SettingCard {
                SettingRow("채팅은 다른 모델 사용", detail: chatSeparate ? nil : "정리와 같은 연결로 채팅해요.") {
                    Toggle("", isOn: $chatSeparate).toggleStyle(BrandSwitchStyle())
                }
            }
            if chatSeparate {
                ConnectionSection(
                    provider: $state.settings.chatProvider,
                    openAIModel: $state.settings.chatModel, baseURL: $state.settings.chatBaseURL, apiKey: $state.settings.chatAPIKey,
                    modelPlaceholder: "모델", urlPlaceholder: "서버 주소",
                    codexModel: $state.settings.chatCodexModel, models: state.chatCodexModels, modelsError: state.chatCodexModelsError,
                    testLabel: "채팅 연결 확인", testing: state.chatTesting, testResult: state.chatTestResult,
                    test: { Task { await state.testChatLLM() } },
                    note: state.settings.chatProvider == "codex" ? "ChatGPT 구독으로 채팅하려면 Codex CLI 또는 Codex 앱이 필요해요." : nil,
                    showAccount: false)
            }
            Text("기록은 Mac에 저장되고, 정리와 채팅을 쓸 때 창 제목, 주소, 화면 텍스트 일부, 질문, 새 파일 정보가 연결한 AI 계정으로 전송돼요. 연결 확인은 개인 자료 없이 시험 호출만 하고, 모델 사용량이 소량 발생해요.")
                .font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 18).padding(.horizontal, 4)
        }
        .onAppear { chatSeparate = chatDiffers }
        .onChange(of: state.settings.llmProvider) { _, _ in syncChat() }
        .onChange(of: state.settings.llmModel) { _, _ in syncChat() }
        .onChange(of: state.settings.llmBaseURL) { _, _ in syncChat() }
        .onChange(of: state.settings.llmAPIKey) { _, _ in syncChat() }
        .onChange(of: state.settings.codexModel) { _, _ in syncChat() }
        .onChange(of: chatSeparate) { _, _ in syncChat() }
    }
}

// MARK: AI 연결 한 구역 (정리, 채팅 공용)

private struct ConnectionSection: View {
    @EnvironmentObject private var state: AppState
    @Binding var provider: String
    @Binding var openAIModel: String
    @Binding var baseURL: String
    @Binding var apiKey: String
    let modelPlaceholder: String
    let urlPlaceholder: String
    @Binding var codexModel: String
    let models: [CodexModel]
    let modelsError: String?
    let testLabel: String
    let testing: Bool
    let testResult: String?
    let test: () -> Void
    let note: String?
    let showAccount: Bool        // 로그인, 로그아웃, 기기 코드는 한 곳(정리 연결)에서만

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showAccount { SectionLabel("정리") }
            SettingCard {
                SettingRow("연결 방식") {
                    BrandMenu(selection: $provider, options: [("codex", "ChatGPT 로그인"), ("openai", "OpenAI 호환 서버")], width: 165)
                }
                if provider == "openai" { openAICardRows } else if showAccount { codexCardRows } else { SettingRow("모델", detail: "목록을 받지 못하면 직접 입력할 수 있어요.") { modelField } }
            }
            if provider == "openai" || !showAccount { testLine } else { codexExtras }
            if let note { InfoLine(note) }
        }
    }

    /// 카드 아래 확인 줄: 결과 글과 확인 단추
    private var testLine: some View {
        HStack(spacing: 10) {
            if let testResult { Text(testResult).font(Brand.suit(11)).foregroundStyle(Brand.text).textSelection(.enabled) }
            Spacer(minLength: 12)
            if testing { ProgressView().controlSize(.small) }
            Button(testLabel, action: test).buttonStyle(BrandButtonStyle()).disabled(testing)
        }
        .padding(.top, 12)
    }

    @ViewBuilder private var openAICardRows: some View {
        SettingRow("모델") { BrandInput(text: $openAIModel, placeholder: modelPlaceholder, width: 300) }
        SettingRow("서버 주소") { BrandInput(text: $baseURL, placeholder: urlPlaceholder, width: 300) }
        SettingRow("API 키", detail: "없으면 비워 둬요.") { BrandInput(text: $apiKey, placeholder: "", width: 300, secure: true) }
    }

    /// ChatGPT 계정 줄: 로그인했으면 계정, 모델, 사용량. 로그인 전이면 로그인 단추 한 줄
    @ViewBuilder private var codexCardRows: some View {
        switch state.codexStatus {
        case .loggedIn(let email, let plan, _):
            SettingRow(email ?? "ChatGPT 계정", detail: plan.map { "\($0) 요금제로 연결됨" } ?? "연결됨") {
                HStack(spacing: 8) {
                    if testing || state.codexModelsLoading { ProgressView().controlSize(.small) }
                    Button(testLabel, action: test).buttonStyle(BrandButtonStyle()).disabled(testing)
                    Menu {
                        if state.codexModelsLoading { Button("모델 검사 중단") { state.cancelCodexModelLoading() } }
                        else { Button("모델 다시 확인") { Task { await state.loadCodexModels(force: true) } } }
                        Button("사용량 자세히 보기") { NSWorkspace.shared.open(CodexResponsesClient.usagePage) }
                        Divider()
                        Button("로그아웃") { state.logoutCodex() }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(Brand.tabText).frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("더 보기")
                }
            }
            SettingRow("모델", detail: "목록을 받지 못하면 직접 입력할 수 있어요.") { modelField }
            if let usage = state.codexUsage {
                SettingRow("사용량") {
                    HStack(spacing: 18) {
                        ForEach([usage.primary, usage.secondary].compactMap { $0 }, id: \.windowSeconds) { window in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(window.label).font(Brand.suit(10)).foregroundStyle(Brand.gray)
                                    Spacer(minLength: 6)
                                    Text("\(Int(window.usedPercent.rounded()))%").font(Brand.jost(11)).foregroundStyle(Brand.text)
                                }
                                Capsule().fill(Brand.line).frame(height: 3)
                                    .overlay(alignment: .leading) {
                                        GeometryReader { g in Capsule().fill(Brand.ink.opacity(0.8)).frame(width: g.size.width * min(1, window.usedPercent / 100)) }
                                    }
                            }
                            .frame(width: 110)
                        }
                    }
                }
            }
        case .loggedOut:
            if state.deviceCode == nil {
                SettingRow("로그인 안 됨", detail: "ChatGPT 계정으로 로그인하면 정리와 채팅을 쓸 수 있어요.") {
                    Button("ChatGPT 로그인") { state.startCodexLogin() }.buttonStyle(BrandButtonStyle(kind: .primary))
                }
            }
        }
    }

    /// 카드 아래: 기기 코드, 확인 결과, 오류
    @ViewBuilder private var codexExtras: some View {
        if case .loggedOut = state.codexStatus, let code = state.deviceCode { deviceCodeRows(code) }
        if let testResult { resultLine(testResult) }
        if case .loggedIn = state.codexStatus, let modelsError { resultLine(modelsError) }
        if let message = state.codexMessage { resultLine(message) }
    }

    /// 모델 칸: 목록이 있으면 선택, 없으면 직접 입력, 불러오는 중이면 비활성 안내.
    @ViewBuilder private var modelField: some View {
        if state.codexModelsLoading {
            HStack(spacing: 8) {                            // 상자 없이 글자와 작은 진행 표시만
                Spacer()
                Text("불러오는 중…").font(Brand.suit(11)).foregroundStyle(Brand.gray)
                ProgressView().controlSize(.mini)
            }
            .frame(width: 190, height: 38)
        } else if models.isEmpty {
            BrandInput(text: $codexModel, placeholder: "gpt-5.6-luna", width: 190)
        } else {
            BrandMenu(selection: $codexModel,
                      options: (models.contains { $0.slug == codexModel } ? [] : [(codexModel, "\(codexModel) (확인되지 않음)")])
                        + models.map { ($0.slug, $0.displayName) },
                      width: 190)
        }
    }

    private func deviceCodeRows(_ code: DeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("열린 브라우저에 이 코드를 입력해 주세요").font(Brand.suit(12, .medium)).foregroundStyle(Brand.text)
                .padding(.vertical, 16)
            VStack(alignment: .leading, spacing: 8) {
                Text("기기 코드").font(Brand.suit(11)).foregroundStyle(Brand.gray)
                Text(code.userCode).font(Brand.jost(28)).tracking(1.4).foregroundStyle(Brand.ink).textSelection(.enabled)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
            HStack(spacing: 10) {
                Button("코드 복사") { state.copyDeviceCode() }.buttonStyle(BrandButtonStyle())
                Button("브라우저 다시 열기") { NSWorkspace.shared.open(code.verificationURL) }.buttonStyle(BrandButtonStyle())
                Button("취소") { state.cancelCodexLogin() }.buttonStyle(BrandButtonStyle())
                ProgressView().controlSize(.small)
            }
            .padding(.top, 14)
            Text("코드는 복사돼 있어요. 브라우저에 붙여 넣으세요.").font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 10).padding(.bottom, 14)
        }
    }

    private func resultLine(_ text: String) -> some View {
        Text(text).font(Brand.suit(11)).foregroundStyle(Brand.text).textSelection(.enabled).padding(.top, 10).padding(.horizontal, 4)
    }
}

// MARK: 설정 전용 부품 (공용 부품으로 옮기면 좋음)

/// 설정 묶음 카드: 옅은 회색 둥근 판 안에 줄을 담는다. 줄 사이 선은 안쪽으로 들이고 마지막 줄 선은 감춘다
enum SettingCardFill { static let color = Color(hex: 0xF7F6F5) }

struct SettingCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }   // 바탕 상자 없이 줄과 선만 (미니멀)
    }
}

private struct InSettingCardKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var inSettingCard: Bool { get { self[InSettingCardKey.self] } set { self[InSettingCardKey.self] = newValue } }
}

/// 설정 한 줄: 왼쪽 제목과 설명, 오른쪽 조작 요소, 아래 구분선. 카드 안이면 좌우 여백을 두고 선을 안쪽에서 시작한다
struct SettingRow<Trailing: View>: View {
    let title: String
    let detail: String?
    var icon: String? = nil                      // SF 기호 이름, 또는 앱 아이콘 같은 이미지(iconImage)
    var iconImage: NSImage? = nil
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.inSettingCard) private var inCard

    init(_ title: String, detail: String? = nil, icon: String? = nil, iconImage: NSImage? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title; self.detail = detail; self.icon = icon; self.iconImage = iconImage; self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 16) {
            if let iconImage {
                Image(nsImage: iconImage).resizable().frame(width: 18, height: 18)
            } else if let icon {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Brand.tabText).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Brand.suit(13)).foregroundStyle(Brand.ink)
                if let detail { Text(detail).font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.top, 3).lineLimit(2) }
            }
            Spacer(minLength: 16)
            trailing()
        }
        .padding(.vertical, detail == nil ? 10 : 12)
        .frame(minHeight: detail == nil ? 48 : 60)
        .padding(.horizontal, inCard ? 16 : 0)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1).padding(.leading, inCard ? 16 : 0) }
    }
}

/// 카드 위 구역 제목: 작은 회색 글씨
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Brand.suit(11, .medium)).foregroundStyle(Brand.gray).padding(.horizontal, 4).padding(.top, 26).padding(.bottom, 8)
    }
}

/// 회색 안내 줄
struct InfoLine: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.horizontal, 4).padding(.vertical, 10)
    }
}

/// 회색 안내 글 (Codex 필요 안내)
struct NoteBox: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.vertical, 6)
    }
}

/// 회색 상태 배지 (허용 안 됨, 예정)
struct GrayBadge: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Brand.suit(10, .medium)).foregroundStyle(Brand.gray)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xF6F5F4)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.line))
    }
}

/// 켜고 끄기: 토글 대신 체크 표시. 켜짐 = 하늘색 체크, 꺼짐 = 옅은 빈 동그라미 (채팅 + 판의 플러그인 체크와 같은 말투)
struct BrandSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(configuration.isOn ? Color(hex: 0x5E97C8) : Color(hex: 0xC9C4BF))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 30)
                .hoverHighlight(cornerRadius: 15)
                .opacity(enabled ? 1 : 0.4)
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}

/// 연결 방식, 모델 선택 상자: 흰 바탕 테두리 상자에 아래 화살표
struct BrandMenu: View {
    @Binding var selection: String
    let options: [(String, String)]
    let width: CGFloat

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { option in
                Button(option.1) { selection = option.0 }
            }
        } label: {
            HStack {
                Text(options.first { $0.0 == selection }?.1 ?? selection).font(Brand.suit(11)).foregroundStyle(Brand.text).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium)).foregroundStyle(Brand.tabText)
            }
            .brandField()
            .frame(width: width)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// 한 줄 입력칸
struct BrandInput: View {
    @Binding var text: String
    let placeholder: String
    let width: CGFloat
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Brand.sub))
            } else {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Brand.sub))
            }
        }
        .textFieldStyle(.plain).font(Brand.suit(12)).foregroundStyle(Brand.text)
        .brandField(height: 38)
        .frame(width: width)
    }
}

// MARK: 채팅 기능 관리 화면 (채팅 화면과 같은 동작을 설정에서)

/// 설정 페이지 머리나 줄 끝에 놓는 글자 단추: 상자 없이 글자만, 커서를 대면 옅은 회색 바탕
private struct SettingTextButton: View {
    let title: String
    var icon: String? = nil
    var iconTint: Color = Brand.gray
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .medium)).foregroundStyle(iconTint) }
                Text(title).font(Brand.suit(11, .medium)).foregroundStyle(Brand.tabText)
            }
            .padding(.horizontal, 8).frame(height: 26)
            .hoverHighlight(cornerRadius: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 스킬: 기본 스킬과 스킬마다 이름, 설명. 줄을 누르면 새 대화의 기본 스킬로 정한다
private struct SkillSettings: View {
    @ObservedObject var chat: ChatState
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("새 대화에 쓸 스킬")
            SettingCard {
                skillRow(id: "general", icon: "sparkles", title: "자동 선택", detail: "질문에 맞는 절차를 알아서 골라요.")
                ForEach(chat.skills) { skill in skillRow(id: skill.id, icon: skill.icon, title: skill.title, detail: skill.summary) }
            }
            InfoLine("대화마다 입력창 위 스킬 칸에서 따로 바꿀 수 있어요.")
        }
    }
    private func skillRow(id: String, icon: String, title: String, detail: String) -> some View {
        let on = chat.current.skillID == id
        return Button { chat.current.skillID = id } label: {
            SettingRow(title, detail: detail, icon: icon) {
                if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0x5E97C8)) }
            }
            .background(on ? ChatPalette.soft : Color.clear)             // 선택 = 옅은 회색 바탕
            .hoverHighlight(cornerRadius: 0)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// 예약 작업: 채팅에서 승인한 예약을 켜고 끄고 지운다. 마지막 결과를 바로 본다. 예약이 없어도 예시에서 바로 만들 수 있다
private struct ScheduleSettings: View {
    @ObservedObject var chat: ChatState
    @EnvironmentObject private var state: AppState
    @State private var deleting: ChatAutomation?

    private struct Idea: Identifiable {
        let title: String       // 줄에 보이는 설명
        let request: String     // 채팅 입력창에 넣을 부탁
        var id: String { title }
    }
    private let ideas = [
        Idea(title: "매일 아침 9시, 어제 기록 요약", request: "매일 아침 9시에 어제 기록을 요약해 줘"),
        Idea(title: "매주 월요일, 지난주 업무 정리", request: "매주 월요일 아침에 지난주 업무를 정리해 줘"),
        Idea(title: "매일 저녁, 오늘 만든 결과물 모아 보기", request: "매일 저녁 6시에 오늘 만든 결과물을 모아서 보여 줘"),
        Idea(title: "매주 금요일, 다음 주 할 일 제안", request: "매주 금요일 오후에 다음 주 할 일을 제안해 줘"),
        Idea(title: "매달 마지막 날, 이번 달 돌아보기", request: "매달 마지막 날 저녁에 이번 달 업무를 돌아보고 정리해 줘"),
    ]

    /// 새 대화를 열고 부탁을 입력창에 넣은 뒤 채팅 탭으로
    private func createInChat(_ request: String) {
        chat.newConversation()
        chat.draft = request
        state.selectedTab = .chat
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if chat.automations.isEmpty {
                InfoLine("정해 둔 때마다 채팅이 알아서 일하고 결과를 남겨요. 아직 만든 예약이 없어요.").padding(.top, 14)
            } else {
                SectionLabel("예약 \(chat.automations.count)개")
                SettingCard {
                    ForEach(chat.automations) { job in
                        SettingRow(job.title, detail: "\(job.intervalHours)시간마다, 다음 \(Date(timeIntervalSince1970: job.nextRun).formatted(date: .abbreviated, time: .shortened)), \(job.lastStatus)") {
                            HStack(spacing: 10) {
                                if let id = job.lastConversationID, let conversation = chat.conversations.first(where: { $0.id == id }) {
                                    Button("결과 보기") { chat.select(conversation); state.selectedTab = .chat }.buttonStyle(BrandButtonStyle())
                                }
                                ChatIconButton(systemName: "trash", help: "예약 삭제") { deleting = job }
                                Toggle("", isOn: Binding(get: { job.enabled }, set: { _ in chat.toggle(job) })).toggleStyle(BrandSwitchStyle())
                            }
                        }
                    }
                }
            }
            SectionLabel(chat.automations.isEmpty ? "이런 예약을 만들 수 있어요" : "다른 예약 만들기")
            SettingCard {
                ForEach(ideas) { idea in
                    SettingRow(idea.title, icon: "clock") {
                        SettingTextButton(title: "채팅에서 만들기") { createInChat(idea.request) }
                    }
                }
            }
            InfoLine("앱이 켜져 있을 때만 실행돼요. 지난 실행은 한 번만 처리해요.")
        }
        .alert("예약을 지울까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("삭제", role: .destructive) { if let deleting { chat.deleteAutomation(deleting) }; deleting = nil }
            Button("취소", role: .cancel) { deleting = nil }
        } message: { Text(deleting?.title ?? "") }
    }
}

/// 프로젝트: 목록, 새로 만들기, 자동 제안, 편집과 삭제. 줄을 누르면 편집 창
private struct ProjectSettings: View {
    @ObservedObject var projects: ProjectState
    @ObservedObject var chat: ChatState
    @EnvironmentObject private var state: AppState
    @State private var editing: ChatProject?
    @State private var creating = false
    @State private var showProposals = false
    @State private var deleting: ChatProject?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                SectionLabel("프로젝트 \(projects.projects.count)개")
                Spacer(minLength: 12)
                if !projects.proposals.isEmpty {
                    SettingTextButton(title: "제안 \(projects.proposals.count)", icon: "sparkles", iconTint: Color(hex: 0x5E97C8)) { showProposals = true }
                        .padding(.top, 18)
                }
                if !projects.projects.isEmpty {
                    SettingTextButton(title: "새 프로젝트", icon: "plus") { creating = true }
                        .padding(.top, 18)
                }
            }
            if projects.projects.isEmpty {
                HStack {
                    Text("채팅을 프로젝트로 묶으면 목표, 지침, 연결한 폴더를 함께 기억해요.").font(Brand.suit(12)).foregroundStyle(Brand.gray)
                    Spacer(minLength: 12)
                    SettingTextButton(title: "새 프로젝트", icon: "plus") { creating = true }
                }
                .padding(.horizontal, 4).padding(.vertical, 12)
                .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
            } else {
                SettingCard {
                    ForEach(projects.projects) { project in
                        let count = chat.conversations.filter { $0.projectID == project.id }.count
                        Button { editing = project } label: {
                            SettingRow(project.title, detail: [project.goal.isEmpty ? nil : project.goal, "대화 \(count)개", project.paths.isEmpty ? nil : "폴더 \(project.paths.count)개"].compactMap { $0 }.joined(separator: ", "), icon: "folder") {
                                HStack(spacing: 6) {
                                    ChatIconButton(systemName: "trash", help: "프로젝트 삭제") { deleting = project }
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Brand.gray)
                                }
                            }
                            .hoverHighlight(cornerRadius: 0)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $editing) { project in ProjectEditor(projects: projects, project: project) { _ in } }
        .sheet(isPresented: $creating) { ProjectEditor(projects: projects, project: nil) { _ in } }
        .sheet(isPresented: $showProposals) { ProjectProposalsSheet(projects: projects, chat: chat) }
        .alert("프로젝트를 지울까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("삭제", role: .destructive) { if let deleting { projects.delete(deleting) }; deleting = nil }
            Button("취소", role: .cancel) { deleting = nil }
        } message: { Text("대화는 지우지 않고 프로젝트 밖으로 옮겨요.") }
    }
}

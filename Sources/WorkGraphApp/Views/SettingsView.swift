import AppKit
import ServiceManagement
import SwiftUI
import WorkGraphCollectors
import WorkGraphCore

/// 설정 탭: 왼쪽 유리 사이드바(섹션 6개)와 오른쪽 내용. Figma ST-01~06, ST-W1~W8.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var section: Section = .permissions
    @State private var launchAtLogin = false
    @State private var launchStatusLoaded = false
    @State private var launchError: String?

    enum Section: CaseIterable {
        case permissions, collection, privacy, files, ai, general
        var title: String {
            switch self {
            case .permissions: "권한"
            case .collection: "수집"
            case .privacy: "기록과 개인정보"
            case .files: "파일 제안"
            case .ai: "AI 연결"
            case .general: "일반"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                BrandPageHeader(eyebrow: "PREFERENCES", title: section.title)
                ScrollView {
                    content
                        .padding(.horizontal, 34)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.white)
            }
            .frame(maxWidth: .infinity)
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

    private var loggedIn: Bool {
        if case .loggedIn = state.codexStatus { return true }
        return false
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("PREFERENCES")
                Text("설정").font(Brand.suit(23, .semibold)).tracking(-0.805).foregroundStyle(Brand.ink).padding(.top, 10)
                Text("기록의 범위는 내가 정해요.").font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.top, 8)
            }
            .padding(.horizontal, 24).padding(.top, 27).padding(.bottom, 20)

            VStack(spacing: 4) {
                ForEach(Section.allCases, id: \.self) { item in
                    Button { section = item } label: {
                        Text(item.title)
                            .font(Brand.suit(12))
                            .foregroundStyle(section == item ? Brand.ink : Brand.tabText)
                            .padding(.leading, 13)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .glassPill(section == item)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.top, 12)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xF6F5F4))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("ChatGPT 계정").font(Brand.suit(12, .medium)).foregroundStyle(Brand.text)
                    Text(loggedIn ? "ChatGPT 연결됨" : "로그인 안 됨").font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 3)
                }
            }
            .padding(.horizontal, 24).frame(height: 75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Brand.hairline).frame(height: 1) }
        }
        .frame(width: 234)
        .frame(maxHeight: .infinity)
        .background(.white.opacity(0.3))
        .background(BehindWindowGlass())
        .overlay(alignment: .trailing) { Rectangle().fill(Brand.hairline).frame(width: 1) }
    }

    // MARK: 내용

    @ViewBuilder private var content: some View {
        switch section {
        case .permissions: permissions
        case .collection: collection
        case .privacy: privacy
        case .files: files
        case .ai: aiConnection
        case .general: general
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            permissionRow("손쉬운 사용", detail: "창 제목, 주소, 문서 경로, 화면 텍스트를 읽어요. 꺼져 있으면 앱 이름만 기록해요.", granted: state.status.accessibility) {
                _ = Permissions.accessibility(prompt: true)
                Permissions.openSettings(.accessibility)
            } check: { Permissions.openSettings(.accessibility) }
            permissionRow("화면 기록", detail: "스크린샷을 남기고, 글자를 읽을 수 없는 화면은 OCR로 읽어요.", granted: state.status.screenRecording) {
                Permissions.requestScreenRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Permissions.openSettings(.screenRecording) }
            } check: { Permissions.openSettings(.screenRecording) }
            Text("허용한 뒤에는 앱을 다시 실행해 주세요.")
                .font(Brand.suit(12)).foregroundStyle(Brand.gray)
                .padding(.vertical, 18)
        }
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool, request: @escaping () -> Void, check: @escaping () -> Void) -> some View {
        SettingRow(title, detail: detail) {
            HStack(spacing: 10) {
                if granted {
                    BrandBadge("허용됨")
                    Button("권한 확인", action: check).buttonStyle(BrandButtonStyle())
                } else {
                    GrayBadge("허용 안 됨")
                    Button("허용하기", action: request).buttonStyle(BrandButtonStyle())
                }
            }
        }
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("COLLECTION")
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
            InfoLine("자동 정리를 꺼도 ‘지금 정리’를 누르면 기록이 전송돼요.")
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("RETENTION")
            SettingRow("스크린샷 보존 기간", detail: "지난 스크린샷만 지워요. 창 제목과 텍스트는 남아요.") {
                HStack(spacing: 10) {
                    HStack(spacing: 0) {
                        TextField("", value: $state.settings.retentionDays, format: .number)
                            .textFieldStyle(.plain).font(Brand.suit(11)).foregroundStyle(Brand.text)
                            .frame(width: 41)
                            .onChange(of: state.settings.retentionDays) { _, days in
                                let clamped = min(max(days, 1), 90)
                                if clamped != days { state.settings.retentionDays = clamped }
                            }
                        Text("일").font(Brand.suit(11)).foregroundStyle(Brand.text).padding(.leading, 12)
                    }
                    .brandField(height: 33)
                    .frame(width: 75 + 0)
                    Text("1~90일").font(Brand.suit(10)).foregroundStyle(Brand.gray)
                }
            }
            SectionLabel("EXCLUDED APPS")
            ExcludedAppsView()
            SectionLabel("DATA")
            SettingRow("저장 위치", detail: state.databasePath) {
                Button("Finder에서 보기") { state.revealDataFolder() }.buttonStyle(BrandButtonStyle())
            }
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow("새 파일의 정리 위치 제안", detail: "새 파일에 어울리는 폴더 한 곳을 추천해요.") {
                Toggle("", isOn: $state.settings.suggestFolders).toggleStyle(BrandSwitchStyle())
            }
            InfoLine("파일명, 출처, 최근 작업 내용과 후보 폴더 경로를 AI로 보내요. 승인한 파일만 옮겨요.")
            SuggestFolderRoots()
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow("Dock 아이콘 표시", detail: "Dock에 Sillog를 표시해요.") {
                Toggle("", isOn: $state.settings.showDockIcon).toggleStyle(BrandSwitchStyle())
            }
            SettingRow("로그인 시 자동 실행", detail: "Mac에 로그인하면 메뉴 막대에서 시작해요.") {
                Toggle("", isOn: $launchAtLogin).toggleStyle(BrandSwitchStyle())
                    .disabled(!launchStatusLoaded)
                    .onChange(of: launchAtLogin) { _, enabled in if launchStatusLoaded { setLaunchAtLogin(enabled) } }
            }
            if let launchError {
                Text(launchError).font(Brand.suit(11)).foregroundStyle(Brand.text).padding(.vertical, 12)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("ChatGPT 계정").font(Brand.suit(14, .medium)).foregroundStyle(Brand.text)
                if loggedIn {
                    Text("로그아웃하면 수집을 멈추고 로그인 화면으로 돌아가요.")
                        .font(Brand.suit(12)).foregroundStyle(Brand.gray).padding(.top, 10)
                    Button { state.logoutCodex() } label: {
                        Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(BrandButtonStyle()).padding(.top, 16)
                } else {
                    Text("로그인 안 됨").font(Brand.suit(12)).foregroundStyle(Brand.gray).padding(.top, 10)
                    Button("ChatGPT 로그인") { state.startCodexLogin() }
                        .buttonStyle(BrandButtonStyle(kind: .primary)).padding(.top, 16)
                }
            }
            .padding(.top, 30)
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

    private var aiConnection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ConnectionSection(
                eyebrow: "ORGANIZATION CONNECTION", title: "업무 정리", intro: nil,
                provider: $state.settings.llmProvider,
                openAIModel: $state.settings.llmModel, baseURL: $state.settings.llmBaseURL, apiKey: $state.settings.llmAPIKey,
                modelPlaceholder: "gpt-5.4-mini", urlPlaceholder: "http://localhost:5010/v1",
                codexModel: $state.settings.codexModel, models: state.codexModels, modelsError: state.codexModelsError,
                testLabel: "연결 확인", testing: false, testResult: state.llmTestResult,
                test: { Task { await state.testLLM() } }, note: nil)
            ConnectionSection(
                eyebrow: "CHAT CONNECTION", title: "채팅", intro: "정리용 모델과 별개로 저장돼요. 채팅과 하위 에이전트는 아래 모델을 써요.",
                provider: $state.settings.chatProvider,
                openAIModel: $state.settings.chatModel, baseURL: $state.settings.chatBaseURL, apiKey: $state.settings.chatAPIKey,
                modelPlaceholder: "모델", urlPlaceholder: "서버 주소",
                codexModel: $state.settings.chatCodexModel, models: state.chatCodexModels, modelsError: state.chatCodexModelsError,
                testLabel: "채팅 연결 확인", testing: state.chatTesting, testResult: state.chatTestResult,
                test: { Task { await state.testChatLLM() } },
                note: state.settings.chatProvider == "codex" ? "ChatGPT 구독으로 채팅하려면 Codex CLI 또는 Codex 앱이 필요해요." : nil)
            Text("개인 자료 없이 도구 호출과 답변을 확인해요. 모델 사용량이 소량 발생해요.")
                .font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 14)
        }
    }
}

// MARK: AI 연결 한 구역 (업무 정리, 채팅 공용)

private struct ConnectionSection: View {
    @EnvironmentObject private var state: AppState
    let eyebrow: String
    let title: String
    let intro: String?
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(eyebrow)
            Text(title).font(Brand.suit(19, .medium)).foregroundStyle(Brand.ink).padding(.top, 8).padding(.bottom, intro == nil ? 8 : 4)
            if let intro { Text(intro).font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.bottom, 10) }

            SettingRow("연결 방식") {
                BrandMenu(selection: $provider, options: [("codex", "ChatGPT 로그인"), ("openai", "OpenAI 호환 서버")], width: 165)
            }
            if provider == "openai" { openAIRows } else { codexRows }

            if let note { NoteBox(note).padding(.top, 14) }
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    private var openAIRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow("모델") { BrandInput(text: $openAIModel, placeholder: modelPlaceholder, width: 313) }
            SettingRow("서버 주소") { BrandInput(text: $baseURL, placeholder: urlPlaceholder, width: 313) }
            SettingRow("API 키", detail: "없으면 비워 둬요.") { BrandInput(text: $apiKey, placeholder: "", width: 313, secure: true) }
            HStack(spacing: 10) {
                if let testResult { Text(testResult).font(Brand.suit(11)).foregroundStyle(Brand.text).textSelection(.enabled) }
                Spacer(minLength: 12)
                if testing { ProgressView().controlSize(.small) }
                Button(testLabel, action: test).buttonStyle(BrandButtonStyle()).disabled(testing)
            }
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder private var codexRows: some View {
        switch state.codexStatus {
        case .loggedIn(let email, let plan, _):
            SettingRow("모델", detail: "목록을 받지 못하면 직접 입력할 수 있어요.") { modelField }
            HStack(spacing: 10) {
                statusDot("\(email ?? "ChatGPT 계정") 연결됨\(plan.map { " (\($0))" } ?? "")")
                Spacer(minLength: 12)
                if testing { ProgressView().controlSize(.small) }
                if state.codexModelsLoading {
                    Button("검사 중단") { state.cancelCodexModelLoading() }.buttonStyle(BrandButtonStyle())
                } else {
                    Button("모델 다시 확인") { Task { await state.loadCodexModels(force: true) } }.buttonStyle(BrandButtonStyle())
                }
                Button(action: test) { Label(testLabel, systemImage: "checkmark") }.buttonStyle(BrandButtonStyle()).disabled(testing)
            }
            .padding(.vertical, 14)
            if let testResult { resultLine(testResult) }
            if let usage = state.codexUsage {
                HStack(alignment: .top, spacing: 30) {
                    ForEach([usage.primary, usage.secondary].compactMap { $0 }, id: \.windowSeconds) { window in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(window.label) 사용률").font(Brand.suit(10)).foregroundStyle(Brand.gray)
                            Text("\(Int(window.usedPercent.rounded()))%").font(Brand.jost(12)).foregroundStyle(Brand.text)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("자세히") { NSWorkspace.shared.open(CodexResponsesClient.usagePage) }
                        .buttonStyle(.plain).font(Brand.suit(11)).foregroundStyle(Brand.tabText)
                }
                .padding(.bottom, 10)
            }
            if let modelsError { resultLine(modelsError) }
        case .loggedOut:
            if let code = state.deviceCode {
                deviceCodeRows(code)
            } else {
                HStack(spacing: 10) {
                    statusDot("로그인 안 됨", filled: false)
                    Spacer(minLength: 12)
                    Button(testLabel, action: test).buttonStyle(BrandButtonStyle()).disabled(testing)
                    Button("ChatGPT 로그인") { state.startCodexLogin() }.buttonStyle(BrandButtonStyle(kind: .primary))
                }
                .padding(.vertical, 14)
                if let testResult { resultLine(testResult) }
            }
        }
        if let message = state.codexMessage { resultLine(message) }
    }

    /// 모델 칸: 목록이 있으면 선택, 없으면 직접 입력, 불러오는 중이면 비활성 안내.
    @ViewBuilder private var modelField: some View {
        if state.codexModelsLoading {
            HStack {
                Text("불러오는 중…").font(Brand.suit(11)).foregroundStyle(Brand.sub)
                Spacer()
                ProgressView().controlSize(.mini)
            }
            .brandField(height: 38).frame(width: 190)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0xF6F5F4)))
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
            HStack {
                Text("열린 브라우저에 이 코드를 입력해 주세요").font(Brand.suit(12, .medium)).foregroundStyle(Brand.text)
                Spacer()
                Button(testLabel, action: test).buttonStyle(BrandButtonStyle()).disabled(testing)
            }
            .padding(.vertical, 16)
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("DEVICE CODE")
                Text(code.userCode).font(Brand.jost(28)).tracking(1.4).foregroundStyle(Brand.ink).textSelection(.enabled)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(width: 364, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xF6F5F4)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
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

    private func statusDot(_ text: String, filled: Bool = true) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(filled ? Brand.ink : .clear).overlay(Rectangle().strokeBorder(Brand.ink, lineWidth: filled ? 0 : 1)).frame(width: 6, height: 6)
            Text(text).font(Brand.suit(11)).foregroundStyle(Brand.tabText)
        }
    }

    private func resultLine(_ text: String) -> some View {
        Text(text).font(Brand.suit(11)).foregroundStyle(Brand.text).textSelection(.enabled).padding(.bottom, 10)
    }
}

// MARK: 파일 제안의 정리 대상 폴더

private struct SuggestFolderRoots: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("정리 대상 폴더").font(Brand.suit(14)).foregroundStyle(Brand.ink)
                Spacer()
                Button { addRoot() } label: { Label("폴더 추가", systemImage: "plus") }.buttonStyle(BrandButtonStyle())
            }
            .padding(.top, 34).padding(.bottom, 14)
            ForEach(state.settings.folderRoots, id: \.self) { root in
                HStack(spacing: 12) {
                    Image(systemName: "folder").font(.system(size: 14)).foregroundStyle(Brand.tabText)
                    Text(root).font(Brand.suit(13)).foregroundStyle(Brand.tabText)
                    Spacer()
                    Button { state.settings.folderRoots.removeAll { $0 == root } } label: {
                        Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(Brand.gray).frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("\(root) 폴더 삭제")
                }
                .frame(height: 61)
                .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
            }
        }
    }

    private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let home = NSHomeDirectory()
        for url in panel.urls {
            let path = url.path
            let shown = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
            if !state.settings.folderRoots.contains(shown) { state.settings.folderRoots.append(shown) }
        }
    }
}

// MARK: 설정 전용 부품 (공용 부품으로 옮기면 좋음)

/// 설정 한 줄: 왼쪽 제목과 설명, 오른쪽 조작 요소, 아래 구분선.
private struct SettingRow<Trailing: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title; self.detail = detail; self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink)
                if let detail { Text(detail).font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.top, 8).lineLimit(2) }
            }
            Spacer(minLength: 16)
            trailing()
        }
        .padding(.vertical, detail == nil ? 18 : 23)
        .frame(minHeight: detail == nil ? 72 : 93)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }
}

/// 영문 눈썹 글씨 구역 제목 (COLLECTION, RETENTION 같은 것)
private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Eyebrow(text).padding(.top, 24) }
}

/// 느낌표 아이콘 안내 줄
private struct InfoLine: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Brand.gray)
            Text(text).font(Brand.suit(12)).foregroundStyle(Brand.gray)
        }
        .padding(.vertical, 15)
    }
}

/// 회색 바탕 안내 상자 (Codex 필요 안내)
private struct NoteBox: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Brand.tabText)
            Text(text).font(Brand.suit(12)).foregroundStyle(Brand.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xF6F5F4)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
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

/// 켜짐은 주색 바탕에 흰 손잡이, 꺼짐은 회색 바탕. 34x20, 모서리 6.
private struct BrandSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 6).fill(configuration.isOn ? Brand.ink : Color(hex: 0xF6F5F4))
                RoundedRectangle(cornerRadius: 6).strokeBorder(configuration.isOn ? Brand.ink : Brand.line)
                RoundedRectangle(cornerRadius: 3).fill(configuration.isOn ? Color.white : Brand.sub)
                    .frame(width: 12, height: 12).padding(.horizontal, 4)
            }
            .frame(width: 34, height: 20)
            .opacity(enabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}

/// 연결 방식, 모델 선택 상자: 흰 바탕 테두리 상자에 아래 화살표
private struct BrandMenu: View {
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
private struct BrandInput: View {
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

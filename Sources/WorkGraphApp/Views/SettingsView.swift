import ServiceManagement
import SwiftUI
import WorkGraphCollectors
import WorkGraphCore

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var launchAtLogin = false
    @State private var launchStatusLoaded = false
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("권한") {
                permissionRow("손쉬운 사용", detail: "창 제목, URL, 문서 경로, 화면 텍스트를 읽습니다", granted: state.status.accessibility) {
                    _ = Permissions.accessibility(prompt: true)
                    Permissions.openSettings(.accessibility)
                }
                permissionRow("화면 기록", detail: "스크린샷과, 텍스트를 읽을 수 없는 화면의 OCR 에 씁니다", granted: state.status.screenRecording) {
                    Permissions.requestScreenRecording()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Permissions.openSettings(.screenRecording) }
                }
                Text("허용한 뒤에는 앱을 다시 실행하세요.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("수집") {
                Toggle("화면 텍스트 읽기", isOn: $state.settings.captureText)
                Toggle("스크린샷 저장", isOn: $state.settings.captureScreenshots)
                Toggle("화면 내용 기록 (스크린샷을 LLM에 보냄)", isOn: $state.settings.screenCards)
                    .disabled(!state.settings.captureScreenshots)
                Toggle("다운로드 폴더의 새 파일 기록", isOn: $state.settings.watchDownloads)
                Toggle("AI 코딩 도구 대화 읽기 (Claude Code, Codex CLI)", isOn: $state.settings.readChatLogs)
                Stepper("스크린샷 보관 \(state.settings.retentionDays)일", value: $state.settings.retentionDays, in: 1...90)
                Toggle("Dock 에 아이콘 표시", isOn: $state.settings.showDockIcon)
                Toggle("로그인할 때 자동으로 실행", isOn: $launchAtLogin)
                    .disabled(!launchStatusLoaded)
                    .onChange(of: launchAtLogin) { _, enabled in if launchStatusLoaded { setLaunchAtLogin(enabled) } }
                if let launchError { Text(launchError).font(.callout).foregroundStyle(.red) }
            }

            Section("내려받은 파일 정리") {
                Toggle("새 파일의 정리 위치 제안", isOn: $state.settings.suggestFolders)
                FolderRootsView()
            }

            Section("기록하지 않을 앱") {
                ExcludedAppsView()
                Text("제외한 앱은 이름과 시간만 남고 창 제목, 주소, 화면 텍스트, 스크린샷은 기록되지 않습니다.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("정리에 쓰는 LLM") {
                Toggle("5분마다 자동으로 정리", isOn: $state.settings.batchEnabled)
                Picker("연결 방식", selection: $state.settings.llmProvider) {
                    Text("ChatGPT 로그인").tag("codex")
                    Text("OpenAI 호환 서버").tag("openai")
                }
                if state.settings.llmProvider == "openai" {
                    TextField("모델", text: $state.settings.llmModel, prompt: Text("gpt-5.4-mini"))
                    TextField("서버 주소", text: $state.settings.llmBaseURL, prompt: Text("http://localhost:5010/v1"))
                    SecureField("API 키 (없으면 비워 둠)", text: $state.settings.llmAPIKey)
                } else {
                    codexLoginRows(model: $state.settings.codexModel)
                }
                HStack {
                    Button("연결 확인") { Task { await state.testLLM() } }
                    if let result = state.llmTestResult { Text(result).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }

            Section("채팅에 쓰는 LLM") {
                Text("정리용 모델과 별개로 저장됩니다. 채팅과 하위 에이전트는 아래 모델을 사용합니다.")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("연결 방식", selection: $state.settings.chatProvider) {
                    Text("ChatGPT 로그인").tag("codex")
                    Text("OpenAI 호환 서버").tag("openai")
                }
                if state.settings.chatProvider == "openai" {
                    TextField("모델", text: $state.settings.chatModel)
                    TextField("서버 주소", text: $state.settings.chatBaseURL)
                    SecureField("API 키 (없으면 비워 둠)", text: $state.settings.chatAPIKey)
                } else {
                    codexLoginRows(model: $state.settings.chatCodexModel)
                }
                HStack {
                    Button("채팅 연결 확인") { Task { await state.testChatLLM() } }.disabled(state.chatTesting)
                    if state.chatTesting { ProgressView().controlSize(.small) }
                    if let result = state.chatTestResult { Text(result).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                Text("개인 자료 없이 도구 호출과 답변을 확인합니다. 모델 사용량이 소량 발생합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("데이터") {
                LabeledContent("저장 위치") { Text(state.databasePath).font(.callout).textSelection(.enabled) }
                Button("Finder 에서 보기") { state.revealDataFolder() }
            }
        }
        .formStyle(.grouped)
        .onChange(of: state.settings) { _, _ in state.applySettings() }
        .onAppear { state.refreshCodexStatus() }
        .task {
            // 로그인 항목 상태 조회는 수 초 걸릴 수 있는 동기 XPC 호출이라 메인 스레드 밖에서 읽는다.
            let enabled = await Task.detached(priority: .utility) { SMAppService.mainApp.status == .enabled }.value
            launchAtLogin = enabled
            try? await Task.sleep(nanoseconds: 100_000_000)
            launchStatusLoaded = true
        }
    }

    /// Args: model은 정리용 또는 채팅용 모델 선택 값이다.
    /// Returns: 공유 로그인 상태와 독립적인 모델 선택 화면.
    /// Raises: 없음. 인증 오류는 기존 상태 메시지에 표시한다.
    @ViewBuilder private func codexLoginRows(model: Binding<String>) -> some View {
        switch state.codexStatus {
        case .loggedIn(let email, let plan, _):
            HStack {
                Label("\(email ?? "로그인됨")\(plan.map { " (\($0))" } ?? "")", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Spacer()
                Button("로그아웃") { state.logoutCodex() }
            }
            if let usage = state.codexUsage {
                LabeledContent("사용량") {
                    HStack(spacing: 10) {
                        Text([usage.primary, usage.secondary].compactMap { $0 }
                            .map { "\($0.label) \(Int($0.usedPercent.rounded()))%" }.joined(separator: ", "))
                            .monospacedDigit()
                        Button("자세히") { NSWorkspace.shared.open(CodexResponsesClient.usagePage) }.buttonStyle(.link)
                    }
                }
            }
            if state.codexModels.isEmpty {
                TextField("모델", text: model, prompt: Text(CodexResponsesClient.defaultModel))
            } else {
                Picker("모델", selection: model) {
                    ForEach(state.codexModels) { Text($0.displayName).tag($0.slug) }
                }
            }
        case .loggedOut:
            if let code = state.deviceCode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("열린 브라우저에 이 코드를 입력하세요").font(.callout)
                    Text(code.userCode).font(.system(size: 28, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Button("코드 복사") { state.copyDeviceCode() }
                        Button("브라우저 다시 열기") { NSWorkspace.shared.open(code.verificationURL) }
                        Button("취소") { state.cancelCodexLogin() }
                        ProgressView().controlSize(.small)
                    }
                    Text("코드는 복사돼 있습니다. 브라우저에 붙여 넣으세요.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Text("로그인 안 됨")
                    Spacer()
                    Button("ChatGPT 로그인") { state.startCodexLogin() }
                }
            }
        }
        if let message = state.codexMessage { Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("허용됨", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("허용하기", action: action)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = "자동 실행을 바꾸지 못했습니다. build/WorkGraph.app 으로 실행했는지 확인하세요. (\(error.localizedDescription))"
        }
    }
}

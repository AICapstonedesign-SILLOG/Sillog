import AppKit
import Combine
import Foundation
import WorkGraphCollectors
import WorkGraphCore

/// 앱의 단일 상태. 수집기(actor)와 배치 실행기(actor)를 소유하고, 화면에는 요약만 내보낸다.
@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings
    @Published var status = CollectorStatus()
    @Published var todayCount = 0
    @Published var pendingCount = 0
    @Published var lastBatchText = "아직 정리한 적 없음"
    @Published var batchRunning = false
    @Published var graphVersion = 0
    @Published var recent: [Observation] = []
    @Published var batches: [BatchRecord] = []
    @Published var llmTestResult: String?
    @Published var chatTestResult: String?
    @Published var chatTesting = false
    @Published var startupError: String?
    @Published var codexStatus: CodexAuthStatus = .loggedOut
    /// 로그인 진행 중일 때만 값이 있다. 화면에 코드와 안내를 보여준다.
    @Published var deviceCode: DeviceCode?
    @Published var codexMessage: String?
    @Published var codexModels: [CodexModel] = []
    @Published var chatCodexModels: [CodexModel] = []
    @Published var codexModelsLoading = false
    @Published var codexModelsError: String?
    @Published var chatCodexModelsError: String?
    @Published var codexUsage: CodexUsage?
    /// 로그인해야 쓸 수 있다. `.ready` 가 되기 전에는 수집기도 배치도 돌지 않는다.
    @Published var phase: AppPhase = .login
    @Published var selectedTab: MainWindow.Tab = MainWindow.initialTab
    /// 설정 탭에서 보고 있는 구역 (메뉴 막대·알림이 파일 구역으로 바로 연다)
    @Published var settingsSection: SettingsView.Section = .permissions
    /// 파일 정리 제안. 대기 중인 것이 앞에 온다.
    @Published var fileSuggestions: [FileSuggestion] = []
    @Published var fileError: String?
    @Published var notificationsDenied = false
    @Published var taskList: [TaskSummary] = []
    /// 오늘 업무 외(집중 이탈) 시간: 앱별 초
    @Published var offTaskToday: [(app: String, seconds: Double)] = []
    @Published var resumeRequest: ResumeRequest?
    @Published var bootstrapped = false
    @Published var chat: ChatState?
    /// 온보딩 시트가 보여 줄 단계. nil 이면 시트가 없다 (OnboardingFlow 가 정한다)
    @Published var onboardingStep: OnboardingStep?
    /// 기기 코드 로그인이 꺼진 계정이라 로그인을 시작하지 못했다. 창이 OUT-W1 카드를 보여 준다
    @Published var loginBlocked = false
    /// 온보딩 권한 단계가 1초마다 직접 읽는 권한 (이때는 수집기가 아직 돌지 않는다)
    @Published var permissionGrants = PermissionGrants(accessibility: false, screenRecording: false)
    /// 이번 실행에서 화면 기록 권한을 요청했다. 허용해도 다시 실행해야 적용된다 (OUT-05)
    @Published var askedScreenRecording = false
    /// 원문 보관 정책. DB 에 저장해 wgctl 과 같은 값을 쓴다
    @Published var retention = RetentionPolicy.standard
    @Published var storageUsage: StorageUsage?
    @Published var consolidationReport: Consolidator.Report?
    @Published var consolidating = false
    /// '지금 정리' 미리보기·첫 동의 시트
    @Published var cleanupPreview: CleanupPreview?
    @Published var retentionPins: [RetentionPin] = []
    @Published var pruneConsented = false
    /// 원문(화면 텍스트)이 남아 있는 첫 날. 정리한 적이 없으면 nil
    @Published var rawRecordsSince: String?

    let databasePath = WGDatabase.defaultPath()
    private(set) var db: WGDatabase?
    private(set) var store: EventStore?
    private var coordinator: CollectorCoordinator?
    private var batcher: OntologyBatcher?
    /// 기록 정리 (사용 시간 기록 → 주간·월간 요약 → 동의했으면 원문 정리). 실행 잠금을 가진 이 인스턴스에서만 돈다
    var consolidator: Consolidator?
    var suggester: FolderSuggester?
    var folderIndex: FolderIndex?
    var folderIndexAt = 0.0
    var folderIndexTask: Task<FolderIndex, Never>?
    let notifier = SuggestionNotifier()
    private var tasks: [Task<Void, Never>] = []
    private let codexAuth = CodexAuthManager()
    private var loginTask: Task<Void, Never>?
    private var codexModelTask: Task<Void, Never>?
    private var codexModelTaskID: UUID?
    private var servicesRunning = false
    private var bootstrapLogged = false
    /// 스냅샷용 미리보기 상태. DB·잠금·수집기·권한 읽기를 하지 않는다
    private var isPreview = false
    private let instanceLock = InstanceLock(databasePath: WGDatabase.defaultPath())
    private static let onboardingKey = "workgraph.onboardingCompleted"
    /// Figma OUT-W3 문구
    static let alreadyRunningMessage = "Sillog이 이미 실행 중이에요. 메뉴 막대의 아이콘을 확인해 주세요."

    init() {
        settings = AppSettings.load()
        guard instanceLock.acquire() else {
            startupError = Self.alreadyRunningMessage
            AppLog.write("이미 실행 중인 Sillog 이 있어 시작하지 않음 (터미널에서 swift run 으로 띄운 실행도 확인)")
            return
        }
        do {
            let database = try WGDatabase(path: databasePath)
            try database.writer.write { try TBox.seed(GraphTx($0), at: Date().timeIntervalSince1970) }
            let store = EventStore(database)
            let captures = URL(fileURLWithPath: databasePath).deletingLastPathComponent().appendingPathComponent("captures", isDirectory: true)
            let coordinator = CollectorCoordinator(store: store, capturesDir: captures, settings: settings.collector)
            self.db = database
            self.store = store
            self.coordinator = coordinator
            self.chat = ChatState(db: database, makeClient: { [unowned self] in self.makeChatClient() },
                                  makeProjectClient: { [unowned self] in self.makeClient() })
            var batchConfig = BatchConfig()
            // 숨은 설정: defaults write com.capstone.workgraph batchPipeline single (없으면 기본값인 3단계)
            batchConfig.pipeline = BatchPipeline(rawValue: UserDefaults.standard.string(forKey: "batchPipeline") ?? "") ?? batchConfig.pipeline
            // 숨은 설정: defaults write com.capstone.workgraph themes -bool true (없으면 분야 붙이기는 꺼짐)
            batchConfig.themes = UserDefaults.standard.bool(forKey: "themes")
            let batcher = OntologyBatcher(db: database, llm: makeClient(), config: batchConfig)
            self.batcher = batcher
            self.consolidator = Consolidator(db: database, llm: makeClient())
            loadRetentionState()
            let cardsOn = settings.screenCards && settings.captureScreenshots
            Task { await batcher.setScreenCards(cardsOn) }
            // 앱을 시작할 때 분야가 없거나 종류가 옛 판인 업무를 정리한다 (처음 한 번은 기존 업무 전부). 붙였으면 그래프를 새로 그린다
            Task { [weak self] in
                if await batcher.assignThemes() != nil { self?.graphVersion += 1 }
            }
            self.suggester = FolderSuggester(db: database, llm: makeQuickClient())
            notifier.onAction = { [weak self] action, id in Task { @MainActor in self?.handleNotificationAction(action, id: id) } }
            notifier.onDenied = { [weak self] denied in Task { @MainActor in self?.notificationsDenied = denied } }
        } catch {
            startupError = "데이터베이스를 열 수 없습니다: \(error.localizedDescription)"
        }
    }

    /// 개발용 미리보기 (SnapshotCatalog). DB·실행 잠금·수집기를 만들지 않고, configure 가 화면에 필요한 값만 채운다.
    /// database: 정리 상세처럼 DB 에서 읽는 화면을 그릴 때 쓰는 메모리 DB
    init(preview configure: (AppState) -> Void, database: WGDatabase? = nil) {
        settings = AppSettings()
        isPreview = true
        bootstrapped = true
        if let database { db = database; store = EventStore(database) }
        configure(self)
    }

    // MARK: 단계 (온보딩 → 사용)

    /// 앱이 뜰 때 한 번: 로그인 상태를 읽어 단계를 정하고, 쓸 수 있는 상태면 서비스를 켠다.
    func bootstrap() async {
        guard !bootstrapped, !isPreview else { return }
        codexStatus = await codexAuth.status()
        bootstrapped = true
        updatePhase()
        if phase == .ready { await loadCodexModels() }
    }

    private func updatePhase() {
        let previous = phase
        phase = AppPhase.decide(loggedIn: codexStatus != .loggedOut,
                                onboardingCompleted: UserDefaults.standard.bool(forKey: Self.onboardingKey))
        onboardingStep = OnboardingFlow.step(after: onboardingStep, phase: phase)
        if previous != phase || !bootstrapLogged {
            bootstrapLogged = true
            AppLog.write("단계: \(phase) (손쉬운 사용 \(Permissions.accessibility(prompt: false) ? "허용" : "없음"), 화면 기록 \(Permissions.screenRecording() ? "허용" : "없음"))")
        }
        phase.runsServices ? startServices() : stopServices()
    }

    /// 온보딩의 마지막 버튼. 이 뒤로는 실행할 때마다 바로 수집이 시작된다.
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        updatePhase()
        Task {
            await loadCodexModels()
            await runBatch(force: false)                    // 로그인 전에 쌓여 있던 활동이 있으면 바로 정리
        }
    }

    /// 온보딩 1단계의 "로그인 완료, 다음"
    func advanceOnboarding() {
        guard let step = onboardingStep else { return }
        onboardingStep = OnboardingFlow.advance(from: step, phase: phase)
    }

    /// 온보딩 시트의 닫기(×). 창은 화면 쪽이 닫는다
    func closeOnboarding() {
        onboardingStep = OnboardingFlow.close(onboardingStep, phase: phase)
    }

    /// 온보딩 권한 단계가 1초마다 부른다. 값이 같으면 화면을 건드리지 않는다
    func refreshPermissionGrants() {
        guard !isPreview else { return }
        let now = PermissionGrants(accessibility: Permissions.accessibility(prompt: false), screenRecording: Permissions.screenRecording())
        if now != permissionGrants { permissionGrants = now }
    }

    private func startServices() {
        guard !servicesRunning, let coordinator else { return }
        servicesRunning = true
        chat?.startScheduler()
        notifier.checkStatus()
        start(coordinator)
    }

    private func stopServices() {
        guard servicesRunning else { return }
        servicesRunning = false
        chat?.stop()
        tasks.forEach { $0.cancel() }
        tasks = []
        let coordinator = self.coordinator
        Task { await coordinator?.stop() }
    }

    /// 화면 기록 권한은 허용한 뒤 앱을 다시 켜야 적용된다.
    func relaunch() {
        // 새 실행이 잠금을 먼저 잡으려 하므로 미리 놓는다. 놓지 않으면 새 실행이 '이미 실행 중'(W3)으로 막힌다.
        // 다시 실행은 온보딩(수집기가 돌기 전)에서만 쓴다
        instanceLock.release()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func start(_ coordinator: CollectorCoordinator) {
        tasks.append(Task {
            await coordinator.setOnChange { [weak self] status in
                Task { @MainActor in self?.status = status }
            }
            await coordinator.setOnFileAppeared { [weak self] path, origin in
                Task { @MainActor in await self?.fileDownloaded(path: path, origin: origin) }
            }
            await coordinator.start()
        })
        tasks.append(Task { [weak self] in                 // 화면용 숫자 갱신
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        })
        tasks.append(Task { [weak self] in                 // 1분마다 배치 조건 확인
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self?.runBatch(force: false)
            }
        })
        tasks.append(Task { [weak self] in                 // 기록 정리: 시작 10분 뒤부터 10분마다 조건 확인 (하루 한 번, 자리를 비웠을 때)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600_000_000_000)
                await self?.consolidateIfDue()
            }
        })
    }

    private func makeOpenAIClient() -> OpenAICompatClient {
        let url = URL(string: settings.llmBaseURL.trimmingCharacters(in: .whitespaces)) ?? URL(string: "http://localhost:5010/v1")!
        return OpenAICompatClient(baseURL: url, model: settings.llmModel, apiKey: settings.llmAPIKey.isEmpty ? nil : settings.llmAPIKey)
    }

    /// 행 배정(배치)용: 추론 medium. 평가에서 low 보다 업무 판정 +1.6%p, 자료 판정 +4%p 였고 배치는 백그라운드라 지연이 상관없다
    private func makeClient() -> any LLMClient {
        settings.llmProvider == "openai" ? makeOpenAIClient() : CodexResponsesClient(auth: codexAuth, model: settings.codexModel, reasoningEffort: "medium")
    }

    /// 파일 정리 제안용: 알림이 바로 떠야 하므로 low
    private func makeQuickClient() -> any LLMClient {
        settings.llmProvider == "openai" ? makeOpenAIClient() : CodexResponsesClient(auth: codexAuth, model: settings.codexModel, reasoningEffort: "low")
    }

    /// Args: 없음.
    /// Returns: 정리용 설정과 분리된 채팅 전용 연결.
    /// Raises: 없음. 인증·연결 오류는 실제 요청 시 전달된다.
    private func makeChatClient() -> ChatBackend {
        if settings.chatProvider == "openai" {
            let url = URL(string: settings.chatBaseURL.trimmingCharacters(in: .whitespaces)) ?? URL(string: "http://localhost:5010/v1")!
            return .model(OpenAICompatClient(baseURL: url, model: settings.chatModel, apiKey: settings.chatAPIKey.isEmpty ? nil : settings.chatAPIKey))
        }
        return .codex(CodexAppServerClient(auth: codexAuth, model: settings.chatCodexModel))
    }

    /// Args: 없음.
    /// Returns: 없음. 개인 자료 없이 실제 채팅 스트림과 도구 호출을 검사한다.
    /// Raises: 없음. 연결·프로토콜 오류는 설정 화면에 표시한다.
    func testChatLLM() async {
        guard !chatTesting else { return }
        chatTesting = true; chatTestResult = "채팅 연결 확인 중…"
        defer { chatTesting = false }
        do {
            try await makeChatClient().checkChatConnection()
            chatTestResult = "연결됨 · 응답과 도구 호출 확인"
        } catch {
            chatTestResult = (error as? LLMError)?.description ?? error.localizedDescription
        }
    }

    // MARK: ChatGPT 로그인

    /// 서버가 로그인을 폐기했으면(계정에서 Codex 연결 해제 등) 토큰이 지워져 있다. 그때는 수집을 멈추고 로그인 화면을 띄운다.
    func handleAuthLossIfNeeded() async {
        let status = await codexAuth.status()
        guard settings.llmProvider != "openai", status == .loggedOut, phase == .ready else { return }
        cancelCodexModelLoading(clear: true)
        codexStatus = status
        codexMessage = "ChatGPT 연결이 끊겨 다시 로그인해야 합니다. 계정 설정에서 Codex 연결을 해제했거나 다른 곳에서 로그아웃하면 이렇게 됩니다."
        AppLog.write("로그인 무효화 감지 → 로그인 화면으로")
        updatePhase()
        WindowOpener.shared.openMain()
    }

    func refreshCodexStatus() {
        Task {
            codexStatus = await codexAuth.status()
            if codexStatus == .loggedOut { cancelCodexModelLoading(clear: true) }
            await loadCodexModels()
            await loadCodexUsage()
        }
    }

    func loadCodexUsage() async {
        guard codexStatus != .loggedOut else { codexUsage = nil; return }
        codexUsage = try? await CodexResponsesClient.fetchUsage(auth: codexAuth)
    }

    /// 선택한 ChatGPT 연결만 확인한다. 취소된 검사 결과는 새 로그인·검사에 적용하지 않는다.
    func loadCodexModels(force: Bool = false) async {
        let checkBatch = settings.llmProvider == "codex" && (force || codexModels.isEmpty)
        let checkChat = settings.chatProvider == "codex" && (force || chatCodexModels.isEmpty)
        guard codexStatus != .loggedOut, !codexModelsLoading, checkBatch || checkChat else { return }
        let id = UUID()
        codexModelTaskID = id
        codexModelsLoading = true
        if checkBatch { codexModelsError = nil }
        if checkChat { chatCodexModelsError = nil }
        let task = Task { [self] in
            defer {
                if codexModelTaskID == id {
                    codexModelsLoading = false
                    codexModelTask = nil
                    codexModelTaskID = nil
                }
            }
            do {
                let candidates = try await CodexResponsesClient.listModels(auth: codexAuth)
                try Task.checkCancellation()
                guard codexModelTaskID == id else { return }
                guard !candidates.isEmpty else { throw LLMError.backend("모델 후보 목록이 비어 있습니다.") }
                let auth = codexAuth
                if checkBatch {
                    let result = try await CodexResponsesClient.verifyModels(candidates) { model in
                        let client = CodexResponsesClient(auth: auth, model: model.slug, reasoningEffort: "medium", timeout: 45)
                        if case .failure(let error) = await client.selfTest() { throw error }
                    }
                    try Task.checkCancellation()
                    guard codexModelTaskID == id else { return }
                    codexModels = result.models
                    codexModelsError = verificationError(result, empty: "현재 연결에서 사용할 수 있는 정리 모델이 없습니다.")
                    if result.isComplete, let first = result.models.first,
                       !result.models.contains(where: { $0.slug == settings.codexModel }),
                       !result.failures.contains(where: { $0.model.slug == settings.codexModel }) {
                        settings.codexModel = result.models.first { $0.slug == CodexResponsesClient.defaultModel }?.slug ?? first.slug
                        applySettings()
                    }
                    if !result.isComplete {
                        if checkChat { chatCodexModelsError = codexModelsError }
                        return
                    }
                }
                if checkChat {
                    let result = try await CodexResponsesClient.verifyModels(candidates) { model in
                        try await CodexAppServerClient(auth: auth, model: model.slug).checkConnection()
                    }
                    try Task.checkCancellation()
                    guard codexModelTaskID == id else { return }
                    chatCodexModels = result.models
                    chatCodexModelsError = verificationError(result, empty: "현재 연결에서 사용할 수 있는 채팅 모델이 없습니다.")
                    if result.isComplete, let first = result.models.first,
                       !result.models.contains(where: { $0.slug == settings.chatCodexModel }),
                       !result.failures.contains(where: { $0.model.slug == settings.chatCodexModel }) {
                        settings.chatCodexModel = result.models.first { $0.slug == CodexResponsesClient.defaultModel }?.slug ?? first.slug
                        applySettings()
                    }
                }
            } catch is CancellationError {
                // 로그아웃·연결 변경·중단으로 끝난 검사는 이전 결과를 덮어쓰지 않는다.
            } catch {
                guard codexModelTaskID == id, !Task.isCancelled else { return }
                let message = "모델 확인 실패: \((error as? LLMError)?.description ?? error.localizedDescription)"
                if checkBatch { codexModelsError = message }
                if checkChat { chatCodexModelsError = message }
            }
        }
        codexModelTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func verificationError(_ result: CodexModelVerification, empty: String) -> String? {
        if !result.failures.isEmpty {
            return result.failures.map { "\($0.model.displayName): \($0.message)" }.joined(separator: "\n")
        }
        return result.models.isEmpty ? empty : nil
    }

    func cancelCodexModelLoading(clear: Bool = false) {
        codexModelTask?.cancel()
        codexModelTask = nil
        codexModelTaskID = nil
        codexModelsLoading = false
        if clear {
            codexModels = []
            chatCodexModels = []
            codexModelsError = nil
            chatCodexModelsError = nil
        }
    }

    func updateCodexModelProviders() {
        cancelCodexModelLoading()
        Task { await loadCodexModels() }
    }

    /// 기기 코드 로그인: 코드를 받아 클립보드에 넣고 브라우저를 연 뒤, 사용자가 승인할 때까지 기다린다.
    func startCodexLogin() {
        guard loginTask == nil else { return }
        cancelCodexModelLoading(clear: true)
        codexMessage = nil
        loginBlocked = false
        loginTask = Task { [weak self] in
            guard let self else { return }
            defer { self.loginTask = nil; self.deviceCode = nil }
            do {
                let code = try await self.codexAuth.beginDeviceLogin()
                self.deviceCode = code
                self.copyDeviceCode()
                NSWorkspace.shared.open(code.verificationURL)
                self.codexStatus = try await self.codexAuth.completeDeviceLogin(code)
                self.codexMessage = "로그인했습니다"
                self.updatePhase()                                      // 로그인 → 권한 안내(처음) 또는 바로 사용
                await self.loadCodexModels()
                if self.phase == .ready { await self.runBatch(force: false) }   // 밀려 있던 활동을 바로 정리
            } catch let error as CodexAuthError {
                self.codexMessage = error == .cancelled ? nil : error.description
                self.loginBlocked = error == .deviceLoginNotEnabled
            } catch is CancellationError {
                self.codexMessage = nil
            } catch {
                self.codexMessage = error.localizedDescription
            }
        }
    }

    func cancelCodexLogin() {
        loginTask?.cancel()
    }

    func copyDeviceCode() {
        guard let code = deviceCode?.userCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    func logoutCodex() {
        cancelCodexModelLoading(clear: true)
        Task {
            try? await codexAuth.logout()
            codexStatus = await codexAuth.status()
            codexMessage = nil
            updatePhase()                                               // 로그아웃하면 수집을 멈추고 로그인 화면으로
        }
    }

    // MARK: 동작

    func runBatch(force: Bool) async {
        guard let batcher, settings.batchEnabled || force, !batchRunning else { return }
        batchRunning = true
        defer { batchRunning = false }
        var applied = false
        for _ in 0..<20 {                                  // 밀린 구간이 많으면 이어서 처리
            let outcome = await batcher.runIfDue(force: force)
            switch outcome {
            case .ok(let stats):
                applied = true
                AppLog.write("정리 성공: 세션 \(stats.sessions + stats.sessionsExtended), 새 업무 \(stats.tasksCreated), 자료 \(stats.resources)")
                lastBatchText = MenuBarModel.batchSummary(clock: Self.clock.string(from: Date()), newTasks: stats.tasksCreated, resources: stats.resources)
                continue
            case .failed(let message):
                AppLog.write("정리 실패: \(message.prefix(200))")
                await handleAuthLossIfNeeded()
                lastBatchText = "\(Self.clock.string(from: Date())) 정리 실패: \(message.prefix(120))"
            case .skipped:
                break
            }
            break
        }
        if applied { graphVersion += 1; refreshTasks(); chat?.projects.check() }
        refresh()
    }

    func togglePause() {
        guard let coordinator else { return }
        let next = !status.paused
        Task { await coordinator.setPaused(next) }
    }

    /// 채팅 화면에서 모델 바꾸기: 다음 메시지부터 그 모델로 보낸다. 설정 화면을 거치지 않으니 여기서 저장한다 (업무 정리 모델은 그대로)
    func selectChatModel(_ slug: String) {
        guard !slug.isEmpty, settings.chatCodexModel != slug else { return }
        settings.chatCodexModel = slug
        if !isPreview { settings.save() }
    }

    func applySettings() {
        settings.save()
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
        let collectorSettings = settings.collector
        let client = makeClient()
        let cardsOn = settings.screenCards && settings.captureScreenshots
        if let db { suggester = FolderSuggester(db: db, llm: makeQuickClient()) }
        folderIndex = nil                                   // 검색 폴더가 바뀌었을 수 있으니 다음 제안 때 다시 색인
        Task { [coordinator, batcher, consolidator] in
            await coordinator?.update(settings: collectorSettings)
            await batcher?.setLLM(client)
            await batcher?.setScreenCards(cardsOn)
            await consolidator?.setLLM(client)
        }
    }

    func testLLM() async {
        llmTestResult = "확인 중…"
        if settings.llmProvider == "openai" {
            let client = makeOpenAIClient()
            let reachable = await client.ping()
            switch await client.selfTest() {
            case .success(let message): llmTestResult = "연결됨. \(message)"
            case .failure(let error):
                llmTestResult = reachable
                    ? "서버는 응답하지만 호출에 실패했습니다.\n\(error.description.prefix(300))"
                    : "서버에 연결할 수 없습니다. 서버가 켜져 있는지 확인하세요.\n\(error.description.prefix(200))"
            }
            return
        }
        switch await makeClient().selfTest() {
        case .success(let message): llmTestResult = "연결됨. \(message)"
        case .failure(let error): llmTestResult = String(error.description.prefix(300))
        }
        codexStatus = await codexAuth.status()
    }

    func refresh() {
        guard let store else { return }
        let startOfDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        if let counts = try? store.counts(since: startOfDay) {
            todayCount = counts.total
            pendingCount = counts.unprocessed
        }
        // 값이 같으면 @Published 를 건드리지 않는다. 5초마다 전체 화면이 다시 그려지는 것을 막는다.
        let newRecent = (try? store.recent(limit: 500)) ?? []
        if newRecent != recent { recent = newRecent }
        let newBatches = (try? store.recentBatchSummaries(limit: 100)) ?? []
        if newBatches != batches { batches = newBatches }
        refreshFileSuggestions()
    }

    func observationText(_ textId: Int64) -> String? {
        (try? store?.texts(ids: [textId]))?[textId]
    }

    /// 상세 패널용: 선택한 배치만 프롬프트·응답까지 전부 읽는다.
    func batchDetail(_ id: Int64) -> BatchRecord? {
        (try? store?.batch(id: id)) ?? nil
    }

    /// 그래프 뷰로 보낼 JSON. 클래스 층도 함께 보내고, 보일지 말지는 화면에서 정한다.
    func graphJSON() -> String {
        guard let db, let graph = try? db.writer.read({ try GraphTx($0).subgraph(since: nil, includeTBox: true) }),
              let data = try? GraphJSONExporter.export(graph) else { return #"{"nodes":[],"links":[]}"# }
        return String(data: data, encoding: .utf8) ?? #"{"nodes":[],"links":[]}"#
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: databasePath)])
    }

    var statusLine: String {
        if startupError != nil { return "시작 실패" }
        if phase != .ready { return "시작하려면 ChatGPT 로그인이 필요합니다" }
        if status.paused { return "일시정지됨" }
        if status.idle { return "자리 비움" }
        return status.running ? "수집 중" : "시작하는 중"
    }

    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

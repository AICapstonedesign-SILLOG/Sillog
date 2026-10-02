import AppKit
import Combine
import Foundation
import WorkGraphCore

@MainActor
final class ChatState: ObservableObject {
    @Published var conversations: [ChatConversation] = []
    @Published var conversationPreviews: [String: String] = [:]
    @Published var current = ChatConversation()
    @Published var messages: [ConversationMessage] = []
    @Published var skills: [ChatSkill] = []
    @Published var automations: [ChatAutomation] = []
    @Published var draft = ""
    @Published var error: String?
    @Published var activeMessage: ConversationMessage?
    let projects: ProjectState
    let library: LibraryState
    private let db: WGDatabase
    private let store: ChatStore
    private let makeClient: () -> ChatBackend
    private var runTask: Task<Void, Never>?
    private var scheduler: Task<Void, Never>?
    private var titleTask: Task<Void, Never>?
    var running: Bool { activeMessage != nil }

    /// Args: db는 앱 DB, makeClient는 현재 설정으로 모델 연결을 생성한다.
    /// Returns: 저장된 대화와 스킬을 불러온 채팅 상태.
    /// Raises: 없음. 초기화 오류는 화면에 표시한다.
    init(db: WGDatabase, makeClient: @escaping () -> ChatBackend, makeProjectClient: @escaping () -> any LLMClient) {
        self.db = db; self.store = ChatStore(db); self.makeClient = makeClient
        projects = ProjectState(db: db, makeClient: makeProjectClient)
        library = LibraryState(db: db)
        library.onChange = { [weak self] in self?.projects.reload() }
        projects.onChange = { [weak self] in
            guard let self else { return }
            do {
                try self.reload()
                if let saved = self.conversations.first(where: { $0.id == self.current.id }) { self.current.projectID = saved.projectID }
                else if !self.projects.projects.contains(where: { $0.id == self.current.projectID }) { self.current.projectID = nil }
            } catch { self.error = error.localizedDescription }
        }
        do {
            try store.recoverInterruptedRuns()
            skills = try ChatSkill.load()
            try reload()
            if let first = conversations.first { select(first) }
        } catch { self.error = error.localizedDescription }
    }

    /// Args: 없음.
    /// Returns: 없음. 새 대화 작성 화면으로 이동한다.
    /// Raises: 없음.
    func newConversation(projectID: String? = nil) {
        current = ChatConversation(); current.projectID = projectID; messages = []; draft = ""; error = nil
    }

    /// Args: conversation은 선택한 대화이다.
    /// Returns: 없음. 저장된 메시지와 진행 중인 응답을 표시한다.
    /// Raises: 없음. 조회 오류는 화면에 표시한다.
    func select(_ conversation: ChatConversation) {
        do {
            let loaded = try store.messages(conversation.id)
            current = conversation; messages = loaded; draft = ""; error = nil
            if let activeMessage, activeMessage.conversationID == conversation.id { replaceVisible(activeMessage) }
        } catch { self.error = error.localizedDescription }
    }

    /// Args: conversation은 대상 대화, title은 사용자가 입력한 이름이다.
    /// Returns: 없음. 빈 이름은 저장하지 않는다.
    /// Raises: 없음. 저장 오류는 화면에 표시한다.
    func rename(_ conversation: ChatConversation, title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            try store.renameConversation(conversation.id, title: title)
            if current.id == conversation.id { current.title = title }
            try reload()
        } catch { self.error = error.localizedDescription }
    }

    /// Args: conversation은 사용자가 삭제를 확인한 대화이다.
    /// Returns: 없음. 응답 생성 중인 대화는 삭제하지 않는다.
    /// Raises: 없음. 삭제 오류는 화면에 표시한다.
    func delete(_ conversation: ChatConversation) {
        guard activeMessage?.conversationID != conversation.id else { return }
        do {
            try store.deleteConversation(conversation.id)
            try reload()
            projects.reload()
            if current.id == conversation.id {
                if let next = conversations.first { select(next) } else { newConversation() }
            }
        } catch { self.error = error.localizedDescription }
    }

    /// Args: 없음.
    /// Returns: 없음. 선택한 스킬·자료 범위를 저장한다.
    /// Raises: 없음. 저장 오류는 화면에 표시한다.
    func saveScope() {
        guard conversations.contains(where: { $0.id == current.id }) else { return }
        do { try store.save(current); try reload(); projects.reload() } catch { self.error = error.localizedDescription }
    }

    /// Args: 없음.
    /// Returns: 없음. 사용자가 선택한 파일·폴더를 대화에 연결한다.
    /// Raises: 없음. 파일 내용은 이 단계에서 읽지 않는다.
    func connectFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.message = "이 대화에서 읽을 파일 또는 저장소 폴더를 선택하세요. 필요한 내용은 설정된 LLM에 전송됩니다."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !current.scope.paths.contains(url.path) { current.scope.paths.append(url.path) }
        saveScope()
    }

    func uploadFiles(projectWide: Bool = false) {
        do {
            try store.save(current); try reload()
            let projectID = projectWide ? current.projectID : nil
            library.importFiles(projectID: projectID, conversationID: projectID == nil ? current.id : nil)
        } catch { self.error = error.localizedDescription }
    }

    func attachLibraryItem(_ item: ChatLibraryItem, projectWide: Bool = false) {
        do {
            try store.save(current); try reload()
            if projectWide, let id = current.projectID { library.attach(item, projectID: id) }
            else { library.attach(item, conversationID: current.id) }
        } catch { self.error = error.localizedDescription }
    }

    /// Args: 없음.
    /// Returns: 없음. 현재 입력을 저장하고 응답 생성을 시작한다.
    /// Raises: 없음. 실행 오류는 해당 응답과 화면에 남긴다.
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !running else { return }
        if begin(text, conversation: current, automationID: nil) { draft = "" }
    }

    /// Args: 없음.
    /// Returns: 없음. 실행 중인 모델·하위 작업에 취소를 전달한다.
    /// Raises: 없음.
    func cancel() { runTask?.cancel() }

    /// Args: message는 예약안을 포함한 답변이다.
    /// Returns: 없음. 사용자의 명시적 승인으로 예약을 등록한다.
    /// Raises: 없음. 저장 오류는 화면에 표시한다.
    func approve(_ message: ConversationMessage) {
        guard let proposal = message.automation, message.approvedAutomationID == nil else { return }
        do {
            var job = ChatAutomation(proposal: proposal, conversation: current)
            job.scope.libraryIDs = try library.store.sourceIDs(conversationID: current.id)
            var updated = message; updated.approvedAutomationID = job.id
            try store.approve(job, message: updated)
            replaceVisible(updated); try reload()
        } catch { self.error = error.localizedDescription }
    }

    /// Args: job은 사용자가 활성 상태를 변경한 예약이다.
    /// Returns: 없음. 다시 켜면 현재 시각부터 새 간격을 적용한다.
    /// Raises: 없음. 저장 오류는 화면에 표시한다.
    func toggle(_ job: ChatAutomation) {
        var updated = job; updated.enabled.toggle()
        if updated.enabled { updated.nextRun = Date().timeIntervalSince1970 + Double(updated.intervalHours) * 3600 }
        do { try store.save(updated); try reload() } catch { self.error = error.localizedDescription }
    }

    /// Args: job은 삭제할 예약이다.
    /// Returns: 없음. 예약만 삭제하고 이미 생성된 대화는 보존한다.
    /// Raises: 없음. 저장 오류는 화면에 표시한다.
    func deleteAutomation(_ job: ChatAutomation) {
        do {
            try store.deleteAutomation(job.id)
            for index in messages.indices where messages[index].approvedAutomationID == job.id {
                messages[index].approvedAutomationID = nil
            }
            try reload()
        } catch { self.error = error.localizedDescription }
    }

    /// Args: 없음.
    /// Returns: 없음. 앱 실행 중 예약을 확인하는 작업을 시작한다.
    /// Raises: 없음. 로그인·앱 종료 시 stop으로 중단한다.
    func startScheduler() {
        guard scheduler == nil else { return }
        projects.check()
        library.collectExisting()
        titleTask = Task { [weak self] in
            guard let self else { return }
            await self.updateOldTitles()
        }
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                self?.runDueAutomation()
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { break }
            }
        }
    }

    /// Args: 없음.
    /// Returns: 없음. 예약 확인과 진행 중인 요청을 중단한다.
    /// Raises: 없음.
    func stop() { scheduler?.cancel(); scheduler = nil; titleTask?.cancel(); titleTask = nil; projects.stop(); cancel() }

    /// Args: text는 요청, conversation은 실행 범위, automationID가 있으면 승인된 예약 실행이다.
    /// Returns: 요청을 저장하고 시작했으면 true.
    /// Raises: 없음. 시작 실패는 화면에 표시한다.
    @discardableResult private func begin(_ text: String, conversation: ChatConversation, automationID: String?) -> Bool {
        guard !running else { return false }
        do {
            var conversation = conversation
            var scope = try ProjectStore(db).scope(for: conversation)
            conversation.projectID = scope.projectID
            let previous = try store.messages(conversation.id)
            let needsTitle = previous.isEmpty && automationID == nil && conversation.title == "새 대화"
            conversation.updatedAt = Date().timeIntervalSince1970
            let user = ConversationMessage(conversationID: conversation.id, role: "user", text: text)
            let answer = ConversationMessage(conversationID: conversation.id, role: "assistant", text: "", status: "running")
            let backend = makeClient()
            let searchKey: String, searchModel: String
            if case .model(let client as OpenAICompatClient) = backend,
               client.baseURL.host == "api.openai.com", scope.useWeb {
                searchKey = client.apiKey ?? ""; searchModel = client.model
            } else { searchKey = ""; searchModel = "" }
            try store.startTurn(conversation: conversation, user: user, answer: answer)
            if automationID != nil {
                let existing = Set(try library.store.items().map(\.id))
                for id in conversation.scope.libraryIDs where existing.contains(id) { try library.store.attach(id, conversationID: conversation.id) }
                scope.libraryIDs = try library.store.sourceIDs(conversationID: conversation.id, projectID: conversation.projectID)
            }
            let tools = ChatTools(db: db, scope: scope,
                                  searchKey: searchKey, searchModel: searchModel,
                                  pluginToken: { id in
                                      if id == "github" { return (try? await PluginAuth.accessToken(id)) ?? "" }
                                      return try await PluginAuth.accessToken(id)
                                  })
            let runner = ChatRunner(backend: backend, tools: tools)
            try reload()
            if current.id == conversation.id { current = conversation; messages = previous + [user, answer] }
            activeMessage = answer; error = nil
            runTask = Task { [weak self] in
                guard let self else { return }
                var succeeded = false
                do {
                    let project = self.projects.projects.first(where: { $0.id == conversation.projectID })
                    let result = try await runner.run(history: previous + [user], skillID: conversation.skillID, allowAutomation: automationID == nil, project: project) { [weak self] event in
                        await self?.receive(event)
                    }
                    try Task.checkCancellation()
                    self.activeMessage?.text = result.text
                    self.activeMessage?.sources = result.sources
                    self.activeMessage?.artifacts = result.artifacts
                    self.activeMessage?.automation = result.automation
                    self.activeMessage?.status = "complete"
                    succeeded = true
                } catch {
                    let cancelled = Task.isCancelled || error is CancellationError
                    self.activeMessage?.status = cancelled ? "cancelled" : "failed"
                    if !cancelled {
                        let description = (error as? LLMError)?.description ?? error.localizedDescription
                        self.activeMessage?.text += "\n\n응답을 완료하지 못했습니다: \(description)"
                    }
                }
                if let message = self.activeMessage {
                    self.replaceVisible(message)
                    do { try self.store.save(message) } catch { self.error = "응답 저장 실패: \(error.localizedDescription)"; succeeded = false }
                    if succeeded { self.library.collect(message) }
                }
                if let automationID, var job = self.automations.first(where: { $0.id == automationID }) {
                    job.lastStatus = succeeded ? "완료" : "실패 또는 중단 — 다음 예약에 실행"
                    do { try self.store.save(job) } catch { self.error = error.localizedDescription }
                }
                self.activeMessage = nil; self.runTask = nil
                do { try self.reload() } catch { self.error = error.localizedDescription }
                if needsTitle, !Task.isCancelled {
                    do {
                        let title = try await backend.conversationTitle(for: text)
                        self.applyTitle(title, to: conversation.id, replacing: "새 대화")
                    } catch { self.error = "대화 제목 생성 실패: \(error.localizedDescription)" }
                }
                if !Task.isCancelled { self.projects.check() }
            }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    /// Args: event는 실제 모델·도구 실행에서 발생한 이벤트이다.
    /// Returns: 없음. 현재 응답을 갱신하고 단계 변경 시 저장한다.
    /// Raises: 없음. 저장 오류는 화면에 표시한다.
    private func receive(_ event: ChatRunEvent) {
        guard var message = activeMessage else { return }
        var checkpoint = true
        switch event {
        case .textReset: message.text = ""; checkpoint = false
        case .text(let text): message.text += text; checkpoint = false
        case .step(let text): message.steps.append(text)
        case .source(let source):
            message.sources.removeAll { $0.id == source.id }; message.sources.append(source)
        case .artifact(let artifact): message.artifacts.append(artifact)
        case .automation(let proposal): message.automation = proposal
        }
        activeMessage = message; replaceVisible(message)
        if checkpoint {
            do { try store.save(message) } catch { self.error = "진행 기록 저장 실패: \(error.localizedDescription)" }
        }
    }

    /// Args: message는 갱신된 응답이다.
    /// Returns: 없음. 선택된 대화에 속한 경우에만 화면을 바꾼다.
    /// Raises: 없음.
    private func replaceVisible(_ message: ConversationMessage) {
        guard current.id == message.conversationID else { return }
        if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message }
    }

    /// Args: 없음.
    /// Returns: 없음. 대화·예약 목록을 저장소와 맞춘다.
    /// Raises: DB·디코딩 오류.
    private func reload() throws {
        conversations = try store.conversations(); conversationPreviews = try store.conversationPreviews()
        automations = try store.automations()
    }

    /// Args: title은 생성된 제목, id는 대상 대화, oldTitle은 덮어써도 되는 자동 제목이다.
    /// Returns: 없음. 사용자가 직접 변경한 제목은 유지한다.
    /// Raises: 없음. 저장 오류는 화면에 표시한다.
    private func applyTitle(_ title: String, to id: String, replacing oldTitle: String) {
        guard conversations.first(where: { $0.id == id })?.title == oldTitle else { return }
        do {
            try store.renameConversation(id, title: title)
            if current.id == id { current.title = title }
            try reload()
        } catch { self.error = error.localizedDescription }
    }

    /// Args: 없음.
    /// Returns: 없음. 첫 요청을 잘라 만든 기존 제목만 모델로 다시 작성한다.
    /// Raises: 없음. 실패한 제목은 그대로 둔다.
    private func updateOldTitles() async {
        for conversation in conversations {
            if Task.isCancelled { return }
            do {
                guard let first = try store.messages(conversation.id).first, first.role == "user" else { continue }
                let oldTitle = String(first.text.prefix(48))
                guard conversation.title == oldTitle else { continue }
                let title = try await makeClient().conversationTitle(for: first.text)
                applyTitle(title, to: conversation.id, replacing: oldTitle)
            } catch { return }
        }
    }

    /// Args: 없음.
    /// Returns: 없음. 기한이 지난 예약 하나를 실행하며 누락 횟수는 재생하지 않는다.
    /// Raises: 없음. 등록·실행 실패는 예약 상태에 표시한다.
    private func runDueAutomation() {
        guard !running else { return }
        let now = Date().timeIntervalSince1970
        guard var job = automations.filter({ $0.enabled && $0.nextRun <= now }).min(by: { $0.nextRun < $1.nextRun }) else { return }
        var conversation = ChatConversation()
        conversation.title = "예약 · \(job.title)"; conversation.scope = job.scope; conversation.skillID = job.skillID
        conversation.projectID = job.scope.projectID
        job.nextRun = now + Double(job.intervalHours) * 3600
        job.lastStatus = "실행 중"; job.lastConversationID = conversation.id
        do {
            try store.save(job); try reload()
            if !begin(job.prompt, conversation: conversation, automationID: job.id) {
                job.lastStatus = "시작 실패 — 설정을 확인하세요"; try store.save(job); try reload()
            }
        } catch { self.error = error.localizedDescription }
    }
}

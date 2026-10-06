import SwiftUI
import WorkGraphCollectors
import WorkGraphCore

/// 스냅샷으로 그릴 화면 목록. 이름은 Figma 화면 번호를 따른다 (Figma 에서 내보낸 같은 이름의 PNG 와 나란히 본다)
@MainActor
enum SnapshotCatalog {
    static var all: [Snapshot] { menus + windows + activity + chat }

    /// Figma 창(760) 에서 제목 줄(44)을 뺀 내용 영역
    static let window = CGSize(width: 1180, height: 716)

    static var menus: [Snapshot] {
        [
            shot("OUT-W2", MenuBarView()) { s in s.phase = .login },
            shot("OUT-W7", MenuBarView()) { s in
                s.phase = .ready; s.status = collector(paused: true)
                s.todayCount = 8; s.pendingCount = 2; s.lastBatchText = "14:05 정리 완료(새 업무 2개, 자료 5개)"
            },
            shot("OUT-W6", MenuBarView()) { s in
                s.phase = .ready; s.status = collector(accessibility: false)
                s.todayCount = 8; s.pendingCount = 2; s.lastBatchText = "14:05 정리 완료(새 업무 1개, 자료 3개)"
            },
            shot("OUT-06", MenuBarView()) { s in
                s.phase = .ready; s.status = collector()
                s.todayCount = 62; s.pendingCount = 6; s.notificationsDenied = true
                s.fileSuggestions = pendingFiles(2); s.taskList = recentTasks
            },
            // 리뷰 포커스 4: 큰 숫자와 긴 업무 이름
            shot("OUT-06-long", MenuBarView()) { s in
                s.phase = .ready; s.status = collector()
                s.todayCount = 1234; s.pendingCount = 0
                s.taskList = [TaskSummary(id: 9, key: "long", title: "아주 긴 업무 이름이 메뉴 폭을 넘어가면 한 줄로 잘려야 하는지 보는 업무",
                                          taskType: nil, activeSeconds: 60, lastActive: todayAt(9, 5), sessionCount: 1)]
            },
        ]
    }

    static var windows: [Snapshot] {
        [
            shot("OUT-01", MainWindow(), size: window) { s in loginStep(s) },
            shot("OUT-02", MainWindow(), size: window) { s in loginStep(s); s.deviceCode = sampleCode },
            shot("OUT-02-signed-in", MainWindow(), size: window) { s in
                loginStep(s); s.phase = .permissions
                s.codexStatus = .loggedIn(email: "sillog@example.com", plan: nil, expiresAt: nil)
            },
            shot("OUT-03", MainWindow(), size: window) { s in permissionStep(s, PermissionGrants(accessibility: false, screenRecording: false)) },
            shot("OUT-04", MainWindow(), size: window) { s in permissionStep(s, PermissionGrants(accessibility: true, screenRecording: false)) },
            shot("OUT-05", MainWindow(), size: window) { s in
                permissionStep(s, PermissionGrants(accessibility: true, screenRecording: true)); s.askedScreenRecording = true
            },
            shot("OUT-W1", MainWindow(), size: window) { s in s.phase = .login; s.loginBlocked = true },
            shot("OUT-W3", MainWindow(), size: window) { s in s.startupError = AppState.alreadyRunningMessage },
            shot("OUT-W4", MainWindow(), size: window) { s in s.bootstrapped = false },
            // 업무 탭: 분야 폴더 안에 업무 (파일 트리)
            shot("TK-01", MainWindow(), size: window) { s in
                s.phase = .ready; s.status = collector(); s.selectedTab = .tasks; s.taskList = themedTasks
            },
            shot("OUT-W5", MainWindow(), size: window) { s in
                s.phase = .ready; s.status = collector(); s.batchRunning = true; s.pendingCount = 6
                s.fileSuggestions = pendingFiles(2); s.taskList = recentTasks; s.selectedTab = .tasks
            },
        ]
    }

    /// 활동 로그 정리 기록: 정리 40번이 쌓인 표와 아래에 고정된 LLM 교환 카드 (보낸 내용, 받은 응답, 실패)
    static var activity: [Snapshot] {
        [
            batchShot("LG-W3", ActivityLogView(section: .batches)),
            batchShot("LG-W4", ActivityLogView(section: .batches, showReceived: true)),
            batchShot("LG-W7", ActivityLogView(section: .batches), failedFirst: true),
        ]
    }

    /// 채팅: 머리의 모델 칩 (누르면 그 자리에서 채팅 모델을 고른다)
    static var chat: [Snapshot] {
        guard let database = try? WGDatabase.inMemory() else { return [] }
        let state = AppState(preview: { s in
            s.phase = .ready; s.status = collector(); s.selectedTab = .chat
            s.settings.chatProvider = "codex"; s.settings.chatCodexModel = "gpt-6-luna"
            s.chatCodexModels = [CodexModel(slug: "gpt-6-luna", displayName: "GPT-6 Luna", defaultEffort: nil),
                                 CodexModel(slug: "gpt-6", displayName: "GPT-6", defaultEffort: nil)]
            let offline = OpenAICompatClient(baseURL: URL(string: "http://localhost:5010/v1")!, model: "preview", apiKey: nil)   // 그리기만 하고 부르지 않는다
            s.chat = ChatState(db: database, makeClient: { .model(offline) }, makeProjectClient: { offline })
        })
        return [Snapshot(name: "CH-01", size: window, view: AnyView(MainWindow().environmentObject(state)))]
    }

    private static func batchShot(_ name: String, _ view: ActivityLogView, failedFirst: Bool = false) -> Snapshot {
        let records = sampleBatches(failedFirst: failedFirst)
        let database = try? WGDatabase.inMemory()
        try? database?.writer.write { conn in for var record in records { try record.insert(conn) } }
        let state = AppState(preview: { s in s.phase = .ready; s.batches = records }, database: database)
        return Snapshot(name: name, size: window, view: AnyView(view.environmentObject(state)))
    }

    private static func sampleBatches(failedFirst: Bool) -> [BatchRecord] {
        let stats = #"{"resources":2,"problems":0,"topics":1,"uncoveredRows":0,"laterItems":0,"offTaskRows":0,"tasksCreated":0,"tasksMerged":0,"sessions":1,"sessionsExtended":0,"unassignedRows":0}"#
        let rows = (1...14).map { i in "\(i) | 14:\(String(format: "%02d", 20 + i))-14:\(String(format: "%02d", 21 + i)) | \(40 + i * 7)s | Chrome | Documentation | Flask 공식 문서 \(i) | https://flask.palletsprojects.com/quickstart/" }
        let prompt = (["NOW: 2026-09-28 14:35", "TASK_TYPES: 문헌조사, 시장조사, 문서작성, 발표자료, 코드작성, 회의, 메신저대응, 강의수강, 복습, 데이터정리, 기타",
                       "OPEN_TASKS:", "- id=t12 | Flask 웹앱 개발 | 코드작성 | topics: 로그인 흐름 구현", "ROWS (row | time | dwell | app | type | title | uri) — assign every row:"] + rows)
            .joined(separator: "\n")
        let patch = #"{ "rows" : [ { "reason" : "로그인 예제 확인", "resource" : true, "rows" : "1", "task" : "A" } ], "tasks" : [ { "id" : "t12", "match" : "existing", "ref" : "A" } ] }"#
        let applied = "row | task | resource\n1 | Flask 웹앱 개발 | 로그인 예제 확인\n2 | Flask 웹앱 개발 | 자료 아님 | 내용 없음"
        return (0..<40).map { k in
            let id = Int64(212 - k), newest = k == 0, failed = newest && failedFirst
            return BatchRecord(id: id, startedAt: todayAt(14, 35) - Double(k) * 300, rowCount: 6, status: failed ? "failed" : "ok", model: "gpt-6-luna",
                               promptTokens: failed ? 0 : 3120, completionTokens: failed ? 0 : 840, error: failed ? "연결 실패: 요청 시간 초과" : nil,
                               rawResponse: newest && !failed ? #"{"id":"resp_0a91","object":"response","model":"gpt-6-luna","output":[{"type":"function_call","name":"assign_rows"}]}"# : nil,
                               stats: failed ? nil : stats, systemPrompt: newest ? OntologyPrompt.system : nil, userPrompt: newest ? prompt : nil,
                               llmPatch: newest && !failed ? patch : nil, appliedPatch: newest && !failed ? applied : nil)
        }
    }

    // MARK: 예시 상태

    private static func shot<V: View>(_ name: String, _ view: V, size: CGSize? = nil, _ configure: (AppState) -> Void) -> Snapshot {
        let state = AppState(preview: configure)
        return Snapshot(name: name, size: size, view: AnyView(view.environmentObject(state)))
    }

    /// 시트 뒤에는 업무 탭(그래프 탭은 웹 보기라 스냅샷에 안 그려진다)
    private static func loginStep(_ s: AppState) {
        s.phase = .login; s.onboardingStep = .login; s.selectedTab = .tasks
        s.taskList = recentTasks; s.fileSuggestions = pendingFiles(2); s.pendingCount = 6
    }

    private static func permissionStep(_ s: AppState, _ grants: PermissionGrants) {
        s.phase = .permissions; s.onboardingStep = .permissions; s.permissionGrants = grants; s.selectedTab = .tasks
        s.taskList = recentTasks; s.fileSuggestions = pendingFiles(2); s.pendingCount = 6
    }

    private static func collector(accessibility: Bool = true, screenRecording: Bool = true, paused: Bool = false) -> CollectorStatus {
        var status = CollectorStatus()
        status.running = true
        status.accessibility = accessibility
        status.screenRecording = screenRecording
        status.paused = paused
        return status
    }

    private static func todayAt(_ hour: Int, _ minute: Int) -> Double {
        (Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()).timeIntervalSince1970
    }

    private static var recentTasks: [TaskSummary] {
        [TaskSummary(id: 1, key: "flask", title: "Flask 웹앱 개발", taskType: nil, activeSeconds: 9600, lastActive: todayAt(14, 32), sessionCount: 3),
         TaskSummary(id: 2, key: "stats", title: "통계학 수업", taskType: nil, activeSeconds: 3000, lastActive: todayAt(12, 10), sessionCount: 1),
         TaskSummary(id: 3, key: "report", title: "분기 성과 보고서", taskType: nil, activeSeconds: 4500, lastActive: todayAt(11, 45), sessionCount: 1)]
    }

    private static var themedTasks: [TaskSummary] {
        let rows: [(String, String?, String, Double, Int, Int)] = [
            ("Sillog 캡스톤 기능·UI 고도화", "프로젝트", "코드작성", 5340, 14, 32), ("WorkGraph 파이프라인 변경사항 커밋·PR 및 그래프 확인", "프로젝트", "코드작성", 4860, 13, 10),
            ("기하학습 회귀 실습 노트북 완성", "학업", "복습", 1620, 12, 40), ("캡스톤 Claude 요금제·환불 검토", "프로젝트", "문헌조사", 360, 11, 20),
            ("자료구조 기초 및 활용 수업 학습", "학업", "강의수강", 60, 10, 5), ("SK AX ERP·Talent AX 직무 지원 준비", "취업 준비", "면접·시험준비", 300, 9, 50),
            ("현대오토에버 2026년 4분기 신입채용 지원서 작성", "취업 준비", "신청·지원", 240, 9, 10), ("분류 전 업무", nil, "기타", 120, 8, 0),
        ]
        return rows.enumerated().map { i, r in
            TaskSummary(id: Int64(i + 1), key: "t\(i)", title: r.0, taskType: r.2, activeSeconds: r.3, lastActive: todayAt(r.4, r.5), sessionCount: 1, theme: r.1)
        }
    }

    private static func pendingFiles(_ count: Int) -> [FileSuggestion] {
        (0..<count).map {
            FileSuggestion(id: Int64($0 + 1), ts: 0, path: "/tmp/file\($0).pdf", fileName: "file\($0).pdf", originUrl: nil,
                           suggestedFolder: "/tmp", confidence: 0.9, reason: nil, source: "llm")
        }
    }

    private static var sampleCode: DeviceCode {
        DeviceCode(verificationURL: URL(string: "https://auth.openai.com/codex/device")!, userCode: "SILL-OG26",
                   deviceAuthId: "preview", interval: 5, expiresAt: Date().timeIntervalSince1970 + 900)
    }
}

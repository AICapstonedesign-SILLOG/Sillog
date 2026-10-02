import Foundation
import ImageIO
import GRDB
import WorkGraphCore
import WorkGraphCollectors

// wgctl — 권한이나 GUI 없이 파이프라인을 돌려보는 개발용 CLI.

setvbuf(stdout, nil, _IOLBF, 0)      // 파이프·파일로 보내도 줄 단위로 바로 출력 (로그인 코드가 버퍼에 갇히지 않게)

let usage = """
wgctl [--db PATH] <command>

  seed-demo [--day YYYY-MM-DD]          하루치 데모 활동을 L0 에 넣는다
  codex-login [--no-open]               ChatGPT 계정으로 로그인 (기기 코드 방식, 브라우저에서 코드 입력)
  codex-status | codex-logout           로그인 상태 확인 / 로그아웃
  codex-models                          로그인한 계정에서 쓸 수 있는 모델 목록
  codex-usage                           구독 한도 대비 Codex 사용률 (5시간 창, 주간 창)
  batch [--provider codex|openai] [--model M] [--base-url URL] [--api-key K] [--force] [--all] [--demo-llm]
                                        미처리 행을 LLM 으로 온톨로지화한다
                                        (--demo-llm: 모델 없이 데모 시드를 규칙으로 분류하는 가짜 LLM)
  llm-test [--provider codex|openai] [--model M] [--base-url URL]
                                        LLM 연결과 로그인이 유효한지 실제 호출로 확인
  collect [--seconds N] [--no-screenshots]
                                        수집기를 N초(기본 20) 돌리며 생기는 행을 출력한다
                                        (권한은 이 명령을 실행한 터미널 앱 기준으로 적용된다)
  rebuild-graph --yes                   그래프를 지우고 원시 행 전체를 미처리로 되돌린다 (이후 batch --all 로 다시 정리).
                                        원시 행과 스크린샷은 그대로다. 분류 로직을 바꾼 뒤 결과를 다시 만들 때 쓴다. 앱을 끄고 실행할 것
  rebuild-graph --from-assignments      LLM 없이: 행마다 기록된 업무 판단은 그대로 두고 세션·앱·자료·흐름·프로젝트만 다시 계산한다
                                        (세션 규칙을 바꿨을 때. 업무·주제·문제·할 일 노드는 유지)
  rows [--last N] [--text]              최근 관측 행 (원시 데이터). --text 면 화면 텍스트 앞부분도
  batches [--last N] | batch-show ID     정리 기록 목록 / 한 배치가 LLM 에 보낸 것과 받은 것 전문
  dump FILE.md [--since-hours N] [--text]
                                        원시 행 + 정리 기록(프롬프트·응답) 전체를 마크다운 한 파일로
  stats                                 행·노드·엣지 수
  export-graph FILE [--tbox] [--since-hours N]
  export-cypher FILE [--tbox]
  export-rdf FILE                       PROV-O·SKOS 에 매핑한 Turtle(RDF). 표준 RDF 도구(rdflib, Protégé, GraphDB)로 읽힌다
  schema                                클래스와 관계 정의 (정의역·치역, 표준 어휘 대응)
  neighbors LABEL KEY [--hops N]        한 노드에서 N 다리 안의 부분 그래프
  suggest FILE [--origin URL] [--context "제목|제목"] [--screen "화면 텍스트"] [--roots ~/Desktop,~/Documents] [--dry]
                                        내려받은 파일을 어느 폴더에 둘지 제안 (후보 목록과 LLM 의 선택을 출력. --dry 면 기록하지 않음)
  suggestions [--last N]                파일 정리 제안 기록
  tasks [--last N]                      업무 목록 (id, 시간, 세션 수) / sessions TASK_ID  그 업무의 세션 목록
  resume-plan TASK_ID | --session ID    그 업무·세션을 "다시 열기" 하면 무엇을 열지 (열지는 않음)
  clean-topics [--yes]                  주제 노드 중 앱·플랫폼·프로젝트 이름·채움말을 찾아 보여 주고, --yes 면 지운다 (앱을 끄고 실행)
  rebind-projects                       업무 ↔ 프로젝트를 1:1 로 다시 맞춘다 (기존 ON 엣지의 시간을 근거로. 앱을 끄고 실행)
  merge-tasks [--dry] [--days N]        제목만 다른 같은 목표의 업무를 LLM 에 물어 합친다 (--dry: 묻기만. 앱을 끄고 실행)
  eval-assign SCENARIO.json [--out result.json] [--runs N]
                                        정답이 붙은 가짜 하루를 LLM 에 보내 행 판정(업무/이탈/없음, 자료 여부)을 채점한다 (기록 안 함)
  backfill-screen-hash                  예전 스크린샷 파일에서 차이 해시를 계산해 원시 행에 채운다 (화면 기억 카드의 재료)
  cards [--last N]                      화면 기억 카드 (무엇을 했나, 화면 내용, 이름 붙은 것들)
  recard [--ids 1,2] [--kind message]   카드를 저장된 스크린샷으로 지금 규칙에 맞춰 다시 만든다 (12장씩 한 호출)
  topic-audit [--last N]                지난 배치들의 LLM 응답에서 주제 태그를 모아 필터가 거를 것을 센다 (프롬프트 대 필터 평가)
  replay-batch ID [ID…]                 저장된 배치의 입력을 지금 프롬프트로 다시 보내 응답을 비교한다 (기록하지 않음. 배치당 LLM 호출 1번)

기본 DB: \(WGDatabase.defaultPath())
기본 LLM: ChatGPT 로그인(codex), 모델 \(CodexResponsesClient.defaultModel). --base-url 을 주면 OpenAI 호환 서버(openai)로 간주한다
"""

var args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    let value = args[index + 1]
    args.removeSubrange(index...(index + 1))
    return value
}

func flag(_ name: String) -> Bool {
    guard let index = args.firstIndex(of: name) else { return false }
    args.remove(at: index)
    return true
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let dbPath = option("--db") ?? WGDatabase.defaultPath()
guard let command = args.first else { print(usage); exit(0) }
args.removeFirst()

let db: WGDatabase
do {
    db = try WGDatabase(path: dbPath)
    try db.writer.write { try TBox.seed(GraphTx($0), at: Date().timeIntervalSince1970) }
} catch {
    fail("DB 를 열 수 없음 (\(dbPath)): \(error)")
}
let store = EventStore(db)

let codexAuth = CodexAuthManager()

/// --provider 가 없으면: --base-url 이 있을 때 openai, 없으면 codex.
func makeClient() -> (client: any LLMClient, pingable: OpenAICompatClient?) {
    let base = option("--base-url")
    let provider = option("--provider") ?? (base == nil ? "codex" : "openai")
    let model = option("--model") ?? (provider == "openai" ? "gpt-5.4-mini" : CodexResponsesClient.defaultModel)
    if provider == "openai" {
        let address = base ?? "http://localhost:5010/v1"
        guard let url = URL(string: address) else { fail("잘못된 --base-url: \(address)") }
        let client = OpenAICompatClient(baseURL: url, model: model, apiKey: option("--api-key"))
        return (client, client)
    }
    return (CodexResponsesClient(auth: codexAuth, model: model, reasoningEffort: option("--reasoning") ?? "medium"), nil)
}

func describe(_ status: CodexAuthStatus) -> String {
    switch status {
    case .loggedOut: return "로그인 안 됨 (wgctl codex-login)"
    case .loggedIn(let email, let plan, let expiresAt):
        let until = expiresAt.map { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened) } ?? "?"
        return "로그인됨: \(email ?? "이메일 없음") (\(plan ?? "플랜 정보 없음")), 액세스 토큰 만료 \(until) — 만료 전에 자동 갱신됨"
    }
}

func printStats() throws {
    let pending = try store.counts(since: 0)
    let counts = try db.writer.read { try GraphTx($0).counts() }
    print("observations: \(pending.total) (미처리 \(pending.unprocessed))")
    print("nodes: " + counts.nodesByLabel.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
    print("edges: " + counts.edgesByType.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
    for batch in try store.recentBatches(limit: 5).reversed() {
        print("batch #\(batch.id ?? 0) \(batch.status) rows=\(batch.rowCount) model=\(batch.model ?? "-") "
              + "tokens=\(batch.promptTokens)+\(batch.completionTokens)\(batch.error.map { " error=\($0.prefix(160))" } ?? "")")
    }
}

do {
    switch command {
    case "seed-demo":
        var calendar = Calendar.current
        calendar.timeZone = .current
        var day = calendar.startOfDay(for: Date())
        if let text = option("--day") {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            guard let parsed = formatter.date(from: text) else { fail("--day 형식은 YYYY-MM-DD") }
            day = parsed
        }
        let count = try DemoScenarios.seed(into: store, dayStart: day.timeIntervalSince1970, home: NSHomeDirectory())
        print("데모 관측 행 \(count)개 추가")

    case "codex-login":
        let code = try await codexAuth.beginDeviceLogin()
        print("""

        1. 브라우저에서 이 주소를 열고 ChatGPT 계정으로 로그인: \(code.verificationURL.absoluteString)
        2. 이 코드를 입력 (15분 안에): \(code.userCode)

        직접 시작한 로그인일 때만 입력하세요. 승인을 기다리는 중… (Ctrl+C 로 취소)
        """)
        if !flag("--no-open") {
            let opener = Process()
            opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            opener.arguments = [code.verificationURL.absoluteString]
            try? opener.run()
        }
        print(describe(try await codexAuth.completeDeviceLogin(code)))
        print("토큰 위치: \(CodexAuthStore.defaultURL().path)")

    case "codex-models":
        for model in try await CodexResponsesClient.listModels(auth: codexAuth) {
            print("\(model.slug)\t\(model.displayName)\t기본 추론 강도: \(model.defaultEffort ?? "-")")
        }

    case "codex-usage":
        let usage = try await CodexResponsesClient.fetchUsage(auth: codexAuth)
        print("요금제: \(usage.planType ?? "-")")
        for window in [usage.primary, usage.secondary].compactMap({ $0 }) {
            let reset = Date(timeIntervalSince1970: window.resetAt).formatted(date: .abbreviated, time: .shortened)
            print("\(window.label) 한도: \(Int(window.usedPercent.rounded()))% 사용, \(reset) 에 초기화")
        }
        print("자세히: \(CodexResponsesClient.usagePage.absoluteString)")

    case "codex-status":
        print(describe(await codexAuth.status()))

    case "codex-logout":
        try await codexAuth.logout()
        print("로그아웃했습니다")

    case "batch":
        let instance = InstanceLock(databasePath: dbPath)
        guard instance.acquire() else { fail("이 DB 를 쓰는 Sillog 앱이 실행 중입니다. 앱이 직접 정리하므로 CLI 배치는 앱을 끈 뒤에 실행하세요.") }
        defer { instance.release() }
        let force = flag("--force"), all = flag("--all")
        let client: any LLMClient = flag("--demo-llm") ? DemoLLM() : makeClient().client
        let batcher = OntologyBatcher(db: db, llm: client)
        var round = 0
        repeat {
            round += 1
            let outcome = await batcher.runIfDue(force: force || all)
            print("[\(round)] \(outcome)")
            if case .ok = outcome { continue }
            break
        } while all && round < 50
        try printStats()

    case "llm-test":
        let (client, pingable) = makeClient()
        if let pingable {
            print("서버 응답(/models): \(await pingable.ping() ? "OK" : "실패")")
        } else {
            print(describe(await codexAuth.status()))
        }
        switch await client.selfTest() {
        case .success(let message): print("함수 호출: \(message)")
        case .failure(let error): fail("함수 호출 실패 — \(error)")
        }

    case "collect":
        let seconds = option("--seconds").flatMap(Double.init) ?? 20
        var settings = CollectorSettings()
        settings.captureScreenshots = !flag("--no-screenshots")
        settings.settleDelay = 1
        let captures = URL(fileURLWithPath: (dbPath as NSString).deletingLastPathComponent).appendingPathComponent("captures")
        print("권한 — 손쉬운 사용: \(Permissions.accessibility(prompt: false) ? "허용" : "없음"), 화면 기록: \(Permissions.screenRecording() ? "허용" : "없음")")
        let coordinator = CollectorCoordinator(store: store, capturesDir: captures, settings: settings)
        await coordinator.start()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        await coordinator.stop()
        let status = await coordinator.currentStatus()
        print("행 \(status.observations)개, 스크린샷 \(status.screenshots)장")
        for row in try store.recent(limit: 10).reversed() {
            let time = Date(timeIntervalSince1970: row.ts).formatted(date: .omitted, time: .standard)
            let text = try row.textId.flatMap { try store.texts(ids: [$0])[$0] }.map { " text=\($0.count)자" } ?? ""
            print("  \(time) [\(row.trigger)] \(row.appName) | \(row.windowTitle ?? "-") | \(row.url ?? row.docPath ?? "-")\(text)\(row.screenshotPath == nil ? "" : " +shot")")
        }

    case "rebuild-graph" where flag("--from-assignments"):
        let instance = InstanceLock(databasePath: dbPath)
        guard instance.acquire() else { fail("이 DB 를 쓰는 Sillog 앱이 실행 중입니다. 앱을 종료한 뒤 다시 실행하세요.") }
        defer { instance.release() }
        let stats = try GraphRebuilder(db: db, store: store).rebuildFromAssignments(now: Date().timeIntervalSince1970)
        print("세션 \(stats.sessions)개, 자료 \(stats.resources)개를 행 판단에서 다시 만들었습니다 (업무 \(stats.tasks)개, 행 \(stats.rows)개)")
        try printStats()

    case "rebuild-graph":
        guard flag("--yes") else { fail("그래프(파생 데이터)를 지우고 원시 행을 전부 미처리로 되돌립니다. 원시 행·스크린샷은 남습니다. 진행하려면 --yes 를 붙이세요.") }
        let instance = InstanceLock(databasePath: dbPath)
        guard instance.acquire() else { fail("이 DB 를 쓰는 Sillog 앱이 실행 중입니다. 앱을 종료한 뒤 다시 실행하세요.") }
        try db.writer.write { conn in
            // 카드 연결(card_id)은 남긴다: 화면 카드는 판정과 무관한 사실이라 다시 만들 필요가 없다
            try conn.execute(sql: "UPDATE observations SET batch_id = NULL, task_id = NULL, resource_relevant = 1, off_task = 0, task_reason = NULL")
            try conn.execute(sql: "UPDATE chat_messages SET batch_id = NULL, task_id = NULL")
            try conn.execute(sql: "DELETE FROM edges")
            try conn.execute(sql: "DELETE FROM nodes")
            try TBox.seed(GraphTx(conn), at: Date().timeIntervalSince1970)
        }
        instance.release()
        print("그래프를 비웠습니다. 이어서: wgctl batch --all")
        try printStats()

    case "rows":
        let limit = option("--last").flatMap(Int.init) ?? 50
        let withText = flag("--text")
        let rows = try store.recent(limit: limit).reversed()
        let texts = withText ? try store.texts(ids: rows.compactMap(\.textId)) : [:]
        for row in rows {
            let time = Date(timeIntervalSince1970: row.ts).formatted(date: .numeric, time: .standard)
            let marks = [row.textId == nil ? nil : "텍스트", row.screenshotPath == nil ? nil : "캡처", row.batchId.map { "정리#\($0)" } ?? "미처리"].compactMap { $0 }.joined(separator: ",")
            print("#\(row.id ?? 0) \(time) [\(row.trigger)] \(row.appName) | \(row.windowTitle ?? "-") | \(row.url ?? row.docPath ?? "-") (\(marks))")
            if withText, let id = row.textId, let text = texts[id] {
                print("    " + text.split(whereSeparator: \.isNewline).joined(separator: " ").prefix(300))
            }
        }

    case "batches":
        let limit = option("--last").flatMap(Int.init) ?? 20
        for batch in try store.recentBatches(limit: limit).reversed() {
            let time = Date(timeIntervalSince1970: batch.startedAt).formatted(date: .numeric, time: .standard)
            print("#\(batch.id ?? 0) \(time) \(batch.status) rows=\(batch.rowCount) model=\(batch.model ?? "-") tokens=\(batch.promptTokens)+\(batch.completionTokens)"
                  + (batch.error.map { " error=\($0.prefix(120))" } ?? "") + (batch.userPrompt == nil ? " (프롬프트 미저장)" : ""))
        }

    case "batch-show":
        guard let id = args.first.flatMap(Int64.init) else { fail("사용법: batch-show ID") }
        guard let batch = try db.writer.read({ try BatchRecord.fetchOne($0, key: id) }) else { fail("배치 #\(id) 없음") }
        print("=== 배치 #\(id) \(batch.status) \(batch.model ?? "-") 행 \(batch.rowCount) 토큰 \(batch.promptTokens)+\(batch.completionTokens)")
        if let error = batch.error { print("오류: \(error)") }
        print("\n--- LLM 이 받은 것: 시스템 프롬프트 ---\n\(batch.systemPrompt ?? "(미저장)")")
        print("\n--- LLM 이 받은 것: 활동 행 ---\n\(batch.userPrompt ?? "(미저장)")")
        print("\n--- LLM 이 돌려준 것 ---\n\(batch.llmPatch ?? "(없음)")")
        if let applied = batch.appliedPatch, applied != batch.llmPatch { print("\n--- 다듬은 뒤 반영한 것 ---\n\(applied)") }

    case "dump":
        guard let file = args.first else { fail("출력 파일 경로가 필요함") }
        let since = option("--since-hours").flatMap(Double.init).map { Date().timeIntervalSince1970 - $0 * 3600 } ?? 0
        let withText = flag("--text")
        let rows = try store.recent(limit: 100_000).filter { $0.ts >= since }.reversed()
        let texts = withText ? try store.texts(ids: rows.compactMap(\.textId)) : [:]
        let batches = try store.recentBatches(limit: 10_000).filter { $0.startedAt >= since }.reversed()
        let clock = Date.FormatStyle(date: .numeric, time: .standard)
        var md = ["# Sillog 데이터 덤프 (\(Date().formatted(clock)))", "", "## 1. 원시 데이터 — 관측 행 \(rows.count)개", "",
                  "| # | 시각 | 계기 | 앱 | 창 제목 | URL / 문서 | 텍스트 | 캡처 | 정리 |", "|---|---|---|---|---|---|---|---|---|"]
        func cell(_ text: String?) -> String { (text ?? "").replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
        for row in rows {
            md.append("| \(row.id ?? 0) | \(Date(timeIntervalSince1970: row.ts).formatted(clock)) | \(row.trigger) | \(cell(row.appName)) | \(cell(row.windowTitle)) | \(cell(row.url ?? row.docPath)) | \(row.textId == nil ? "" : "있음") | \(row.screenshotPath == nil ? "" : "있음") | \(row.batchId.map { "#\($0)" } ?? "대기") |")
            if withText, let id = row.textId, let text = texts[id] { md.append("| | | | | 텍스트 | \(cell(String(text.prefix(500)))) | | | |") }
        }
        md += ["", "## 2. 정리 기록 — 배치 \(batches.count)개 (LLM 이 받은 것과 돌려준 것)", ""]
        for batch in batches {
            md += ["### 배치 #\(batch.id ?? 0) — \(batch.status), \(batch.model ?? "-"), 행 \(batch.rowCount), 토큰 \(batch.promptTokens)+\(batch.completionTokens), \(Date(timeIntervalSince1970: batch.startedAt).formatted(clock))", ""]
            if let error = batch.error { md += ["오류: `\(error)`", ""] }
            if let user = batch.userPrompt { md += ["<details><summary>LLM 이 받은 것 (활동 행)</summary>", "", "```text", user, "```", "", "</details>", ""] }
            if let patch = batch.llmPatch { md += ["**LLM 이 돌려준 것**", "", "```json", patch, "```", ""] }
            if let applied = batch.appliedPatch, applied != batch.llmPatch { md += ["**다듬은 뒤 반영한 것**", "", "```json", applied, "```", ""] }
        }
        md += ["", "## 3. 시스템 프롬프트 (고정 지시문)", "", "```text", OntologyPrompt.system, "```", ""]
        try md.joined(separator: "\n").write(toFile: file, atomically: true, encoding: .utf8)
        print("관측 행 \(rows.count)개, 배치 \(batches.count)개 → \(file)")

    case "stats":
        try printStats()

    case "schema":
        print("클래스 (\(ClassSchema.classes.count))")
        for cls in ClassSchema.classes { print("  \(cls.label.padding(toLength: 13, withPad: " ", startingAt: 0)) \(cls.name.padding(toLength: 9, withPad: " ", startingAt: 0)) ⊂ \(cls.standardSuperclass.padding(toLength: 19, withPad: " ", startingAt: 0)) \(cls.meaning)") }
        print("관계 (\(RelationSchema.rules.count))")
        for rule in RelationSchema.rules {
            let pairs = rule.pairs.map { "\($0.from) → \($0.to)" }.sorted().joined(separator: ", ")
            print("  \(rule.type.padding(toLength: 15, withPad: " ", startingAt: 0)) \(pairs)\n    \(rule.meaning)  [\(rule.standard)]")
        }

    case "export-rdf":
        guard let file = args.first else { fail("출력 파일 경로가 필요함") }
        let graph = try db.writer.read { try GraphTx($0).subgraph(since: nil, includeTBox: true) }
        try RDFExporter.export(graph).write(toFile: file, atomically: true, encoding: .utf8)
        print("노드 \(graph.nodes.count)개, 엣지 \(graph.edges.count)개 → \(file)")

    case "export-graph", "export-cypher":
        let includeTBox = flag("--tbox")
        let since = option("--since-hours").flatMap(Double.init).map { Date().timeIntervalSince1970 - $0 * 3600 }
        guard let file = args.first else { fail("출력 파일 경로가 필요함") }
        let graph = try db.writer.read { try GraphTx($0).subgraph(since: since, includeTBox: includeTBox) }
        if command == "export-graph" {
            try GraphJSONExporter.export(graph).write(to: URL(fileURLWithPath: file))
        } else {
            try CypherExporter.export(graph).write(toFile: file, atomically: true, encoding: .utf8)
        }
        print("노드 \(graph.nodes.count)개, 엣지 \(graph.edges.count)개 → \(file)")

    case "suggest":
        let home = NSHomeDirectory()
        let origin = option("--origin")
        let roots = (option("--roots") ?? "~/Desktop,~/Documents").split(separator: ",").map { FolderSuggester.expand(String($0).trimmingCharacters(in: .whitespaces), home: home) }
        let titles = (option("--context") ?? "").split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let screen = option("--screen")
        let dry = flag("--dry")
        guard args.count >= 1 else { fail("사용법: suggest FILE [--origin URL] [--context \"제목|제목\"] [--roots a,b] [--dry]") }
        let file = FolderSuggester.expand(args[0], home: home)
        guard FileManager.default.fileExists(atPath: file) else { fail("파일이 없음: \(file)") }
        let started = Date()
        let index = FolderIndex.scan(roots: roots, home: home)
        print("폴더 색인: \(index.folders.count)개 (\(String(format: "%.1f", Date().timeIntervalSince(started)))초)")
        let openTasks = try db.writer.read { try GraphTx($0).openTasks(limit: 6) }
        let fileName = (file as NSString).lastPathComponent
        var contextStrings = titles + openTasks.flatMap { [$0.title] + $0.topics }
        if let origin { contextStrings.append(origin) }
        print("후보 (문맥 점수 순):")
        for folder in index.rank(fileName: fileName, context: contextStrings, limit: 25) {
            print("  \(folder.relativePath)  — \(folder.sampleFiles.prefix(4).joined(separator: ", "))")
        }
        let target: WGDatabase = dry ? try WGDatabase.inMemory() : db
        let suggester = FolderSuggester(db: target, llm: makeClient().client, home: home)
        let context = FolderSuggester.Context(recentTitles: titles, screenText: screen, openTasks: openTasks, now: Date().timeIntervalSince1970)
        let llmStarted = Date()
        if let suggestion = try await suggester.suggest(filePath: file, originURL: origin, index: index, context: context) {
            print("제안: \(suggestion.suggestedFolder)  (\(suggestion.source), 신뢰도 \(Int(suggestion.confidence * 100))%, \(String(format: "%.1f", Date().timeIntervalSince(llmStarted)))초)")
            print("이유: \(suggestion.reason ?? "-")")
            if !dry { print("기록됨 #\(suggestion.id ?? 0) — 앱의 파일 탭에서 옮길 수 있다") }
        } else {
            print("제안 없음 (후보가 없거나 LLM 이 확신하지 못함, \(String(format: "%.1f", Date().timeIntervalSince(llmStarted)))초)")
        }

    case "clean-topics":
        let apply = flag("--yes")
        let victims: [(GraphNode, String)] = try db.writer.read { conn in
            let tx = GraphTx(conn)
            let apps = Set(try tx.nodes(label: NodeLabel.app).map(\.title))
            let projects = Set(try tx.nodes(label: NodeLabel.project).map(\.title))
            return try tx.nodes(label: NodeLabel.topic).compactMap { node in
                TopicFilter.rejection(node.title, apps: apps, projects: projects).map { (node, $0) }
            }
        }
        if victims.isEmpty { print("거를 주제가 없습니다."); break }
        for (node, why) in victims { print("  \(node.title)  — \(why)") }
        guard apply else { print("\(victims.count)개. 지우려면 --yes 를 붙이세요 (앱을 끈 뒤)."); break }
        let instance = InstanceLock(databasePath: dbPath)
        guard instance.acquire() else { fail("이 DB 를 쓰는 Sillog 앱이 실행 중입니다. 앱을 종료한 뒤 다시 실행하세요.") }
        try db.writer.write { conn in
            for (node, _) in victims {
                try conn.execute(sql: "DELETE FROM edges WHERE src = ? OR dst = ?", arguments: [node.id, node.id])
                try conn.execute(sql: "DELETE FROM nodes WHERE id = ?", arguments: [node.id])
            }
        }
        instance.release()
        print("주제 \(victims.count)개를 지웠습니다.")

    case "merge-tasks":
        let dry = flag("--dry")
        let days = option("--days").flatMap(Double.init) ?? 7
        let instance = InstanceLock(databasePath: dbPath)
        guard dry || instance.acquire() else { fail("이 DB 를 쓰는 Sillog 앱이 실행 중입니다. 앱을 종료한 뒤 다시 실행하세요.") }
        defer { if !dry { instance.release() } }
        let now = Date().timeIntervalSince1970
        let titles: [String: String] = try db.writer.read { conn in
            Dictionary(try GraphTx(conn).nodes(label: NodeLabel.task).map { ($0.key, $0.title) }, uniquingKeysWith: { first, _ in first })
        }
        let outcome = try await TaskMerger.run(db: db, llm: makeClient().client, since: now - days * 86_400, now: now, dry: dry)
        if outcome.groups.isEmpty { print("합칠 업무가 없습니다."); break }
        for group in outcome.groups {
            print("  남김: \(titles[group.keep] ?? group.keep)\(group.title.map { " → \($0)" } ?? "")")
            for key in group.merge { print("    ← \(titles[key] ?? key)") }
        }
        print(dry ? "(--dry: 반영하지 않음)" : "업무 \(outcome.merged)개를 합쳤습니다.")

    case "rebind-projects":
        let instance = InstanceLock(databasePath: dbPath)
        guard instance.acquire() else { fail("이 DB 를 쓰는 Sillog 앱이 실행 중입니다. 앱을 종료한 뒤 다시 실행하세요.") }
        let chosen: [(String, String, Double)] = try db.writer.write { conn in
            let tx = GraphTx(conn)
            // 예전 방식(행마다 ON, 가중치 = 초)으로 쌓인 엣지를 시간 집계로 옮긴다
            for edge in try Row.fetchAll(conn, sql: "SELECT * FROM edges WHERE type = 'ON'").map(GraphTx.edge) {
                guard let task = try tx.node(id: edge.src), let project = try tx.node(id: edge.dst) else { continue }
                let known = task.props["project_seconds"]?.objectValue?[project.key]?.doubleValue ?? 0
                if edge.weight > known { try tx.addProjectSeconds(taskId: task.id, projectKey: project.key, seconds: edge.weight - known, at: edge.lastAt) }
            }
            return try tx.rebindProjects(at: Date().timeIntervalSince1970).compactMap { item in
                guard let task = try tx.node(id: item.taskId), let project = try tx.node(id: item.projectId) else { return nil }
                return (task.title, project.title, item.seconds)
            }
        }
        instance.release()
        for (task, project, seconds) in chosen { print("  \(task) → \(project)  (\(Int(seconds))초)") }
        print("업무 ↔ 프로젝트 \(chosen.count)쌍. 나머지 연결은 지웠습니다.")

    case "eval-assign":
        let outPath = option("--out")
        let runs = option("--runs").flatMap(Int.init) ?? 1
        guard let file = args.first, let data = FileManager.default.contents(atPath: file),
              let scenario = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rowSpecs = scenario["rows"] as? [[String: Any]] else { fail("사용법: eval-assign SCENARIO.json") }
        let base = 1_790_000_000.0                                   // 가짜 하루의 시작 시각
        var rows: [ActivityRow] = []
        for (index, spec) in rowSpecs.enumerated() {
            let start = base + (spec["min"] as? Double ?? 0) * 60, dur = (spec["dur"] as? Double ?? 0) * 60
            var row = ActivityRow(row: index + 1, start: start, end: start + dur, dwell: Int(dur),
                                  app: spec["app"] as? String ?? "?", appBundle: spec["bundle"] as? String ?? "?",
                                  title: spec["title"] as? String, uri: spec["uri"] as? String, type: spec["type"] as? String,
                                  projectKey: spec["project"] as? String, projectTitle: (spec["project"] as? String).map { ($0 as NSString).lastPathComponent },
                                  snippet: spec["text"] as? String, observationIds: [Int64(index + 1)])
            row.isChat = spec["chat"] as? Bool ?? false
            rows.append(row)
        }
        let openTasks = (scenario["open_tasks"] as? [[String: Any]] ?? []).map { task in
            TaskDigest(id: task["id"] as? String ?? "", title: task["title"] as? String ?? "", taskType: task["type"] as? String,
                       topics: task["topics"] as? [String] ?? [], recentResources: task["resources"] as? [String] ?? [], lastActive: base,
                       recentSummaries: task["recent"] as? [String] ?? [])
        }
        let prompt = OntologyPrompt.build(rows: rows, openTasks: openTasks, now: base + 7_200)
        let effort = option("--reasoning")                               // low | medium | high
        let client: any LLMClient = effort.map { CodexResponsesClient(auth: codexAuth, model: option("--model") ?? CodexResponsesClient.defaultModel, reasoningEffort: $0) } ?? makeClient().client
        var results: [[String: Any]] = []
        for run in 1...max(1, runs) {
            let started = Date()
            let answer = try await client.callFunction(system: prompt.system, user: prompt.user, tool: AssignmentSchema.tool)
            guard let patch = AssignmentPatch.decodeLenient(from: answer.arguments) else { fail("응답 해석 실패: \(answer.raw.prefix(300))") }
            let elapsed = Date().timeIntervalSince(started)
            // ref → 사람이 읽는 이름과 정답 비교용 키
            var refName: [String: String] = [:], refKey: [String: String] = [:]
            for def in patch.tasks {
                if def.match == "existing", let id = def.id { refName[def.ref] = openTasks.first { $0.id == id }?.title ?? id; refKey[def.ref] = id }
                else { refName[def.ref] = "새: " + (def.title ?? "?"); refKey[def.ref] = "new:" + (def.title ?? "") }
            }
            let decided = patch.byRow()
            var correct = 0, resourceCorrect = 0, resourceJudged = 0
            var rowResults: [[String: Any]] = []
            for (index, spec) in rowSpecs.enumerated() {
                let number = index + 1
                let expect = spec["expect"] as? [String: Any] ?? [:]
                let expectedTasks: [String?] = (expect["task"] as? [Any]).map { $0.map { $0 as? String } } ?? [expect["task"] as? String]   // "t_x" | "new:라벨" | "off" | nil, 여러 개면 그중 하나
                let expectedTask = expectedTasks.first ?? nil
                let expectedResource = expect["resource"]                // true | false | "any"
                let decision = decided[number]
                let actualRef = decision?.task
                let actualKey: String? = actualRef.flatMap { $0 == AssignmentPatch.offTask ? "off" : refKey[$0] }
                let actualName: String = actualRef.map { $0 == AssignmentPatch.offTask ? "이탈" : (refName[$0] ?? $0) } ?? (decision == nil ? "(언급 없음)" : "없음")
                func matches(_ wanted: String?) -> Bool {
                    guard let wanted else { return actualKey == nil && decision != nil }
                    if wanted == "off" { return actualKey == "off" }
                    if wanted.hasPrefix("new:") { return actualKey?.hasPrefix("new:") ?? false }
                    return actualKey == wanted
                }
                let taskOK = expectedTasks.contains(where: matches)
                let resourceActual = decision?.resource ?? AssignmentApplier.defaultResource(rows[index])
                var resourceOK: Bool? = nil
                if let wanted = expectedResource as? Bool, expectedTask != nil, expectedTask != "off" {
                    resourceOK = resourceActual == wanted; resourceJudged += 1; if resourceOK == true { resourceCorrect += 1 }
                }
                if taskOK { correct += 1 }
                rowResults.append(["row": number, "app": spec["app"] ?? "", "title": spec["title"] ?? NSNull(), "uri": spec["uri"] ?? NSNull(), "reason": decision?.reason ?? NSNull(),
                                   "text": spec["text"] ?? NSNull(), "min": spec["min"] ?? 0, "dur": spec["dur"] ?? 0, "why": spec["why"] ?? "",
                                   "expected_task": expectedTask ?? NSNull(), "expected_tasks": expectedTasks.map { $0 ?? "null" }, "expected_resource": expectedResource ?? NSNull(),
                                   "actual_task": actualKey ?? NSNull(), "actual_name": actualName, "actual_resource": resourceActual,
                                   "task_ok": taskOK, "resource_ok": resourceOK ?? NSNull()])
            }
            let work = patch.work.map { ["task": refName[$0.task] ?? $0.task, "summary": $0.summary, "topics": $0.topics] }
            let problems = (patch.problems ?? []).map { ["row": $0.row, "kind": $0.kind, "message": $0.message, "resolved_by_row": $0.resolvedByRow ?? NSNull()] as [String: Any] }
            print("run \(run): 업무 판정 \(correct)/\(rowSpecs.count), 자료 판정 \(resourceCorrect)/\(resourceJudged), \(String(format: "%.1f", elapsed))초, 토큰 \(answer.promptTokens)+\(answer.completionTokens)")
            for r in rowResults where !(r["task_ok"] as? Bool ?? false) || (r["resource_ok"] as? Bool) == false {
                print("  ✗ \(r["row"] ?? 0) \(r["title"] ?? "") — 기대 \(r["expected_task"] ?? "없음")/\(r["expected_resource"] ?? "-") 실제 \(r["actual_name"] ?? "")/\(r["actual_resource"] ?? "")")
            }
            results.append(["run": run, "elapsed": elapsed, "model": answer.model, "prompt_tokens": answer.promptTokens, "completion_tokens": answer.completionTokens,
                            "task_correct": correct, "resource_correct": resourceCorrect, "resource_judged": resourceJudged,
                            "tasks": patch.tasks.map { ["ref": $0.ref, "match": $0.match, "id": $0.id ?? NSNull(), "title": $0.title ?? NSNull(), "task_type": $0.taskType ?? NSNull()] as [String: Any] },
                            "work": work, "problems": problems, "rows": rowResults])
        }
        if let outPath {
            let payload: [String: Any] = ["scenario": file, "persona": scenario["persona"] ?? "", "open_tasks": scenario["open_tasks"] ?? [],
                                          "system_prompt": prompt.system, "user_prompt": prompt.user, "runs": results]
            try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: URL(fileURLWithPath: outPath))
            print("결과 → \(outPath)")
        }

    case "backfill-screen-hash":
        let rows: [(Int64, String)] = try db.writer.read { conn in
            try Row.fetchAll(conn, sql: "SELECT id, screenshot_path FROM observations WHERE screenshot_path IS NOT NULL AND screen_hash IS NULL")
                .map { ($0["id"] as Int64, $0["screenshot_path"] as String) }
        }
        var filled = 0, missing = 0
        for (id, path) in rows {
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { missing += 1; continue }
            try store.attachScreen(observationId: id, path: nil, hash: ScreenCapturer.differenceHash(image))
            filled += 1
        }
        print("해시 \(filled)개 채움, 파일 없음 \(missing)개")

    case "recard":
        let ids = (option("--ids") ?? "").split(separator: ",").compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
        let kind = option("--kind")
        var targets: [ScreenCard] = try db.writer.read { conn in
            if !ids.isEmpty { return try ScreenCard.fetchAll(conn, keys: ids) }
            if let kind { return try ScreenCard.fetchAll(conn, sql: "SELECT * FROM screen_cards WHERE kind = ? ORDER BY ts_start", arguments: [kind]) }
            return []
        }
        targets = targets.filter { $0.screenshotPath.map { FileManager.default.fileExists(atPath: $0) } ?? false }
        guard !targets.isEmpty else { fail("다시 만들 카드가 없음 (--ids 또는 --kind, 스크린샷이 남아 있어야 함)") }
        guard let vision = makeClient().client as? any VisionLLMClient else { fail("이미지를 받는 LLM 이 아님") }
        var updated = 0
        for start in stride(from: 0, to: targets.count, by: CardMaker.maxImages) {
            let chunk = Array(targets[start..<min(start + CardMaker.maxImages, targets.count)])
            let groups = chunk.map { card in
                KeyframeSelector.Group(appBundle: card.appBundle, appName: card.appName, title: card.windowTitle, uri: card.uri,
                                       shots: [KeyframeSelector.Shot(observationId: 0, ts: card.tsStart, path: card.screenshotPath!, hash: UInt64(bitPattern: card.screenHash))],
                                       seconds: card.tsEnd - card.tsStart, rows: [], observationIds: [], start: card.tsStart, end: card.tsEnd)
            }
            let (drafts, result) = try await CardMaker.make(groups, llm: vision)
            try await db.writer.write { conn in
                for (index, draft) in drafts.enumerated() {
                    guard let draft, let id = chunk[index].id else { continue }
                    try conn.execute(sql: "UPDATE screen_cards SET activity = ?, content = ?, kind = ?, entities = ? WHERE id = ?",
                                     arguments: [draft.activity, draft.content.joined(separator: "\n"), draft.kind, CardMaker.entitiesJSON(draft.entities), id])
                }
            }
            for (index, draft) in drafts.enumerated() {
                guard let draft else { continue }
                updated += 1
                print("#\(chunk[index].id ?? 0) 전: \(chunk[index].activity)")
                print("      후: \(draft.activity)")
            }
            if let result { print("  (토큰 \(result.promptTokens)+\(result.completionTokens))") }
        }
        print("카드 \(updated)/\(targets.count)장을 다시 만들었습니다.")

    case "cards":
        let last = option("--last").flatMap(Int.init) ?? 20
        let cards = try db.writer.read { try ScreenCard.fetchAll($0, sql: "SELECT * FROM screen_cards ORDER BY ts_start DESC LIMIT ?", arguments: [last]) }
        for card in cards.reversed() {
            let start = Date(timeIntervalSince1970: card.tsStart).formatted(date: .numeric, time: .shortened)
            print("#\(card.id ?? 0) \(start) [\(card.kind)] \(card.appName) | \(card.windowTitle ?? "-")")
            print("   \(card.activity)")
            for line in card.contentLines { print("   · \(line)") }
            if card.entities != "{}" { print("   entities: \(card.entities)") }
        }

    case "topic-audit":
        let last = option("--last").flatMap(Int.init) ?? 200
        let (apps, projects) = try db.writer.read { conn -> (Set<String>, Set<String>) in
            let tx = GraphTx(conn)
            return (Set(try tx.nodes(label: NodeLabel.app).map(\.title)), Set(try tx.nodes(label: NodeLabel.project).map(\.title)))
        }
        var total = 0, rejected: [String: Int] = [:], examples: [String: Set<String>] = [:], batchesWithRejects = 0
        for batch in try store.recentBatches(limit: last).reversed() where batch.status == "ok" {
            guard let raw = batch.llmPatch, let patch = AssignmentPatch.decodeLenient(from: Data(raw.utf8)) else { continue }
            var hit = false
            for work in patch.work {
                for topic in work.topics {
                    total += 1
                    if let why = TopicFilter.rejection(topic, apps: apps, projects: projects) {
                        rejected[why, default: 0] += 1
                        examples[why, default: []].insert(topic)
                        hit = true
                    }
                }
            }
            if hit { batchesWithRejects += 1 }
        }
        let rejectedTotal = rejected.values.reduce(0, +)
        print("주제 태그 \(total)개 중 필터가 거르는 것 \(rejectedTotal)개 (\(total == 0 ? 0 : rejectedTotal * 100 / total)%), 배치 \(batchesWithRejects)개에서")
        for (why, count) in rejected.sorted(by: { $0.value > $1.value }) {
            print("  \(why): \(count)  예) \(examples[why, default: []].sorted().prefix(12).joined(separator: ", "))")
        }

    case "replay-batch":
        let ids = args.compactMap(Int64.init)
        guard !ids.isEmpty else { fail("사용법: replay-batch ID [ID…]") }
        let client = makeClient().client
        let (apps, projects) = try db.writer.read { conn -> (Set<String>, Set<String>) in
            let tx = GraphTx(conn)
            return (Set(try tx.nodes(label: NodeLabel.app).map(\.title)), Set(try tx.nodes(label: NodeLabel.project).map(\.title)))
        }
        func describe(_ patch: AssignmentPatch) -> [String] {
            let names = Dictionary(patch.tasks.map { ($0.ref, "\($0.match)\($0.id.map { "(\($0))" } ?? "") \($0.title ?? "")") }, uniquingKeysWith: { first, _ in first })
            var lines = patch.rows.map { "  rows \($0.rows) → \($0.task.flatMap { names[$0] } ?? "(없음)")\(($0.resource ?? true) ? "" : " [보이기만]")" }
            for work in patch.work {
                let flagged = work.topics.map { topic in TopicFilter.rejection(topic, apps: apps, projects: projects).map { "\(topic)✗(\($0))" } ?? topic }
                lines.append("  work \(names[work.task] ?? work.task): \(work.summary) — topics: \(flagged.joined(separator: ", "))")
            }
            return lines
        }
        for id in ids {
            guard let batch = try store.batch(id: id), let userPrompt = batch.userPrompt else { print("#\(id): 배치 없음 또는 프롬프트 미저장"); continue }
            print("=== 배치 #\(id) (\(batch.rowCount)행, \(Date(timeIntervalSince1970: batch.startedAt).formatted(date: .omitted, time: .shortened))) ===")
            if let raw = batch.llmPatch, let old = AssignmentPatch.decodeLenient(from: Data(raw.utf8)) {
                print("이전 응답 (배정 \(old.rows.count)줄):"); describe(old).forEach { print($0) }
            }
            let started = Date()
            let result = try await client.callFunction(system: OntologyPrompt.system, user: userPrompt, tool: AssignmentSchema.tool)
            guard let fresh = AssignmentPatch.decodeLenient(from: result.arguments) else { print("새 응답: 해석 실패\n\(result.raw.prefix(300))"); continue }
            print("지금 프롬프트 (배정 \(fresh.rows.count)줄, \(String(format: "%.1f", Date().timeIntervalSince(started)))초, 토큰 \(result.promptTokens)+\(result.completionTokens)):")
            describe(fresh).forEach { print($0) }
        }

    case "tasks":
        let last = option("--last").flatMap(Int.init) ?? 20
        let rows: [(GraphNode, Int)] = try db.writer.read { conn in
            let tx = GraphTx(conn)
            return try tx.nodes(label: NodeLabel.task).map { ($0, try tx.edges(to: $0.id, type: EdgeType.partOf).count) }
        }
        for (node, sessions) in rows.sorted(by: { ($0.0.props["last_active"]?.doubleValue ?? 0) > ($1.0.props["last_active"]?.doubleValue ?? 0) }).prefix(last) {
            let minutes = Int((node.props["active_seconds"]?.doubleValue ?? 0) / 60)
            let last = Date(timeIntervalSince1970: node.props["last_active"]?.doubleValue ?? 0).formatted(date: .numeric, time: .shortened)
            print("#\(node.id)  \(node.title)  — \(minutes)분, 세션 \(sessions)개, 마지막 \(last)  [\(node.key)]")
        }

    case "sessions":
        guard let taskId = args.first.flatMap(Int64.init) else { fail("사용법: sessions TASK_ID") }
        let sessions: [GraphNode] = try db.writer.read { conn in
            let tx = GraphTx(conn)
            return try tx.edges(to: taskId, type: EdgeType.partOf).compactMap { try tx.node(id: $0.src) }
        }
        for node in sessions.sorted(by: { ($0.props["start"]?.doubleValue ?? 0) > ($1.props["start"]?.doubleValue ?? 0) }) {
            let start = Date(timeIntervalSince1970: node.props["start"]?.doubleValue ?? 0).formatted(date: .numeric, time: .shortened)
            let end = Date(timeIntervalSince1970: node.props["end"]?.doubleValue ?? 0).formatted(date: .omitted, time: .shortened)
            print("#\(node.id)  \(start) – \(end)  \(node.title)")
        }

    case "resume-plan":
        let sessionId = option("--session").flatMap(Int64.init)
        let nodeId = sessionId ?? args.first.flatMap(Int64.init)
        guard let nodeId else { fail("사용법: resume-plan TASK_ID | --session SESSION_ID") }
        let home = NSHomeDirectory()
        let plan: ResumePlan? = try db.writer.read { conn in
            let tx = GraphTx(conn)
            guard let node = try tx.node(id: nodeId) else { return nil }
            let exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
            if node.label == NodeLabel.task { return try ResumePlanner.plan(task: node, tx: tx, home: home, fileExists: exists) }
            if node.label == NodeLabel.session { return try ResumePlanner.plan(session: node, tx: tx, home: home, fileExists: exists) }
            return nil
        }
        guard let plan else { fail("업무나 세션 노드가 아님: #\(nodeId)") }
        print("다시 열기: \(plan.title)  ([x] = 기본으로 켜는 것)")
        for item in plan.items {
            let target = item.target.hasPrefix(home) ? "~" + item.target.dropFirst(home.count) : item.target
            let when = Date(timeIntervalSince1970: item.lastAt).formatted(date: .omitted, time: .shortened)
            print("  \(item.selected ? "[x]" : "[ ]") [\(item.kind.rawValue)] \(item.title)  → \(target)\(item.appBundle.map { "  (\($0))" } ?? "")  \(Int(item.seconds / 60))분, 마지막 \(when)")
        }
        if plan.items.isEmpty { print("  (열 것이 없음)") }

    case "suggestions":
        let last = option("--last").flatMap(Int.init) ?? 20
        for item in try FileSuggestionStore(db).recent(limit: last).reversed() {
            let time = Date(timeIntervalSince1970: item.ts).formatted(date: .numeric, time: .shortened)
            print("#\(item.id ?? 0) \(time) [\(item.status)] \(item.fileName) → \(item.suggestedFolder) (\(item.source) \(Int(item.confidence * 100))%)\(item.movedTo.map { " 옮긴 곳: \($0)" } ?? "")")
        }

    case "neighbors":
        let hops = option("--hops").flatMap(Int.init) ?? 2
        guard args.count >= 2 else { fail("사용법: neighbors LABEL KEY [--hops N]") }
        let graph = try db.writer.read { conn -> Subgraph in
            let tx = GraphTx(conn)
            guard let node = try tx.node(label: args[0], key: args[1]) else { return Subgraph() }
            return try tx.neighbors(of: node.id, hops: hops)
        }
        for node in graph.nodes { print("(\(node.label)\(node.subtype.map { ":\($0)" } ?? "")) \(node.title)  [\(node.key)]") }
        let titles = Dictionary(graph.nodes.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        for edge in graph.edges { print("  \(titles[edge.src] ?? "?") -[\(edge.type) w=\(Int(edge.weight))]-> \(titles[edge.dst] ?? "?")") }

    default:
        print(usage)
        exit(command == "help" || command == "--help" ? 0 : 1)
    }
} catch {
    fail("\(error)")
}

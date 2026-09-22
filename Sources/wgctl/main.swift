import Foundation
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
    return (CodexResponsesClient(auth: codexAuth, model: model), nil)
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
        guard instance.acquire() else { fail("이 DB 를 쓰는 WorkGraph 앱이 실행 중입니다. 앱이 직접 정리하므로 CLI 배치는 앱을 끈 뒤에 실행하세요.") }
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

    case "rebuild-graph":
        guard flag("--yes") else { fail("그래프(파생 데이터)를 지우고 원시 행을 전부 미처리로 되돌립니다. 원시 행·스크린샷은 남습니다. 진행하려면 --yes 를 붙이세요.") }
        let instance = InstanceLock(databasePath: dbPath)
        guard instance.acquire() else { fail("이 DB 를 쓰는 WorkGraph 앱이 실행 중입니다. 앱을 종료한 뒤 다시 실행하세요.") }
        try db.writer.write { conn in
            try conn.execute(sql: "UPDATE observations SET batch_id = NULL")
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
        var md = ["# WorkGraph 데이터 덤프 (\(Date().formatted(clock)))", "", "## 1. 원시 데이터 — 관측 행 \(rows.count)개", "",
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

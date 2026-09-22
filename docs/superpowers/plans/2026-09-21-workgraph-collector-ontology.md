# WorkGraph 수집 · 온톨로지 · 그래프 뷰 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS 백그라운드 앱이 PC 활동을 SQLite에 기록하고, LLM 배치로 온톨로지 그래프를 만들어 옵시디언식 그래프 뷰로 보여준다.

**Architecture:** SwiftPM 패키지 하나. 순수 로직(`WorkGraphCore`)은 AppKit 없이 테스트하고, macOS 수집기(`WorkGraphCollectors`)와 메뉴바 앱(`WorkGraphApp`), 개발용 CLI(`wgctl`)가 그 위에 얹힌다. L0 로그와 그래프는 같은 SQLite 파일에 두고 배치 반영을 한 트랜잭션으로 처리한다.

**Tech Stack:** Swift 6.2 툴체인(Swift 5 언어 모드), SwiftUI/AppKit, GRDB 7, ScreenCaptureKit, Vision, Accessibility API, FSEvents, WKWebView + force-graph.

**Spec:** `docs/superpowers/specs/2026-09-21-workgraph-collector-ontology-design.md`

**실행 방식:** 작성자가 같은 세션에서 인라인 실행한다. 그래서 이 문서는 구현 코드 전문 대신 파일 구조, 정확한 시그니처, 테스트 목록, 검증 명령을 고정한다. 코드의 정본은 저장소다.

## Global Constraints

- 최소 macOS 14, arm64/x86_64 모두 빌드 가능해야 함
- 외부 의존성은 GRDB 하나. JS는 `force-graph` UMD 파일을 저장소에 번들(런타임 네트워크 요청 금지)
- DB 컬럼은 snake_case, Swift 프로퍼티는 camelCase (`CodingKeys`로 매핑)
- 시각은 전부 Unix 초(`Double`)
- LLM 기본값: base URL `http://localhost:5010/v1`, 모델 `gpt-5.4-mini`. 둘 다 설정으로 변경 가능
- 수집은 어떤 실패(권한 없음, LLM 다운)에도 멈추지 않는다. 사용자에게 질문하지 않는다
- 자동 커밋 없음 (사용자가 요청할 때만)
- 경로에 공백·한글이 있으므로 스크립트의 모든 경로는 따옴표로 감싼다

## File Map

```
Package.swift
.gitignore
README.md
scripts/make-app.sh
Sources/WorkGraphCore/
  Models/JSONValue.swift            props용 JSON 값 enum
  Models/Observation.swift          Observation, TextSnapshot, FileEvent, IdleSpan, BatchRecord
  Models/GraphModels.swift          GraphNode, GraphEdge, Subgraph, TaskDigest
  Storage/WGDatabase.swift          DatabasePool/Queue + 마이그레이션 v1
  Storage/EventStore.swift          L0 읽기/쓰기
  Storage/GraphTx.swift             그래프 upsert/조회 (Database 핸들 위에서 동작)
  Ontology/TBox.swift               클래스 층 정의 + 시드
  Ontology/URINormalizer.swift
  Ontology/RuleClassifier.swift
  Ontology/EventCompressor.swift    Observation[] → ActivityRow[]
  Ontology/OntologyPatch.swift      LLM 출력 모델 + 함수 스키마
  Ontology/OntologyPrompt.swift     system/user 메시지 생성
  Ontology/OntologyApplier.swift    patch → 그래프 upsert
  Ontology/OntologyBatcher.swift    배치 조건·트랜잭션·백오프
  LLM/LLMClient.swift               프로토콜 + 결과 타입
  LLM/OpenAICompatClient.swift
  Export/GraphJSONExporter.swift
  Export/CypherExporter.swift
  Demo/DemoScenarios.swift          프론트 개발 / 서류 작업 / 공부 시드
Sources/WorkGraphCollectors/
  Permissions.swift  ContextSampler.swift  AXTextReader.swift  BrowserURL.swift
  ScreenCapturer.swift  OCRReader.swift  IdleMonitor.swift  DownloadsWatcher.swift
  PrivacyFilter.swift  CollectorCoordinator.swift
Sources/WorkGraphApp/
  WorkGraphApp.swift  AppState.swift  Settings.swift
  Views/MenuBarView.swift  Views/MainWindow.swift  Views/GraphWebView.swift
  Views/ActivityLogView.swift  Views/SettingsView.swift
  Resources/graph/index.html  graph.js  style.css  vendor/force-graph.min.js
Sources/wgctl/main.swift
Tests/WorkGraphCoreTests/*.swift
```

---

### Task 1: 패키지 스캐폴드 + DB 마이그레이션

**Files:** `Package.swift`, `.gitignore`, `Models/JSONValue.swift`, `Models/Observation.swift`, `Models/GraphModels.swift`, `Storage/WGDatabase.swift`, `Tests/.../DatabaseTests.swift`

**Produces:**
```swift
public final class WGDatabase { public let writer: any DatabaseWriter
  public init(path: String) throws            // DatabasePool, WAL, foreign_keys ON
  public static func inMemory() throws -> WGDatabase }
public enum JSONValue: Codable, Equatable, Sendable { case string(String), number(Double), bool(Bool), null, array([JSONValue]), object([String: JSONValue]) }
```
테이블: `observations, text_snapshots, file_events, idle_spans, batches, nodes, edges` (스펙 4·5.2절 컬럼 그대로). 인덱스: `observations(batch_id, ts)`, `nodes(label)`, `edges(src)`, `edges(dst)`.

- [x] 테스트: 인메모리 DB 생성 후 7개 테이블 존재, `nodes(label,key)`·`edges(src,dst,type)` UNIQUE 위반 시 에러
- [x] 구현 → `swift build && swift test --filter DatabaseTests` 통과

### Task 2: uri 정규화 + 규칙 분류

**Files:** `Ontology/URINormalizer.swift`, `Ontology/RuleClassifier.swift`, 테스트 2개

**Produces:**
```swift
public enum URINormalizer {
  public static func normalize(url: String) -> String
  public static func normalize(filePath: String, home: String) -> String }   // "file:~/…"
public struct ClassifiedResource: Equatable, Sendable { public let key, subtype, title: String; public let projectKey: String?; public let projectTitle: String? }
public enum RuleClassifier {
  public static func classify(appBundle: String, appName: String, windowTitle: String?, url: String?, docPath: String?, home: String, fileExists: (String) -> Bool) -> ClassifiedResource? }
```
- [x] 테스트(정규화): 프래그먼트·`utm_*`·`fbclid` 제거, 호스트 소문자, 끝 슬래시 제거, `youtube.com/watch?v=X&t=1` → `v`만 유지, `arxiv.org/abs/2401.05566v2`와 `arxiv.org/pdf/2401.05566` → `arxiv:2401.05566`, `localhost:3000/a?tab=1` → `local:3000/a`, 구글 검색은 `q`만 유지, 파일 경로는 `file:~/…`
- [x] 테스트(분류): shadcn 문서 → Documentation, stackoverflow → QnA, localhost → Preview, arxiv → Paper, youtube watch → Video, chatgpt/claude → AIChat, `.tsx` 문서 경로 → CodeFile + 프로젝트 루트(`package.json`), Cursor 창 제목 `TaskCard.tsx — dashboard` → `code:dashboard/TaskCard.tsx`, `.hwp`/`.docx` → Document, URL·경로 없는 Slack → nil
- [x] 구현 → 테스트 통과

### Task 3: 그래프 저장소 + T-Box

**Files:** `Storage/GraphTx.swift`, `Ontology/TBox.swift`, 테스트

**Produces:**
```swift
public struct GraphTx { public init(_ db: Database)
  @discardableResult public func upsertNode(label: String, key: String, subtype: String?, title: String?, props: [String: JSONValue], at: Double) throws -> Int64
  @discardableResult public func upsertEdge(src: Int64, dst: Int64, type: String, props: [String: JSONValue], addWeight: Double, at: Double) throws -> Int64
  public func node(label: String, key: String) throws -> GraphNode?
  public func node(id: Int64) throws -> GraphNode?
  public func setProps(nodeId: Int64, _ props: [String: JSONValue], at: Double) throws     // json_patch 병합
  public func neighbors(of id: Int64, hops: Int) throws -> Subgraph                        // 무방향 재귀 CTE
  public func subgraph(since: Double?, includeTBox: Bool) throws -> Subgraph
  public func openTasks(limit: Int) throws -> [TaskDigest]
  public func latestSession(ofTask taskId: Int64) throws -> GraphNode?
  public func latestSession(before ts: Double, excluding id: Int64?) throws -> GraphNode? }
public enum TBox { public static let taskTypes, resourceTypes: [(name: String, parent: String?)]
  public static var leafTaskTypes: [String]; public static func seed(_ tx: GraphTx, at: Double) throws }
```
- [x] 테스트: 같은 (label,key) 두 번 upsert → 노드 1개·title 갱신·props 병합, 엣지 재upsert → weight 누적·`last_at` 갱신, 3홉 체인에서 `hops:2`는 3번째 노드 미포함, `includeTBox:false`면 TaskType/ResourceType 제외, `TBox.seed` 두 번 실행해도 노드 수 동일
- [x] 구현 → 테스트 통과

### Task 4: L0 저장소 + 압축

**Files:** `Storage/EventStore.swift`, `Ontology/EventCompressor.swift`, 테스트

**Produces:**
```swift
public struct EventStore { public init(_ db: WGDatabase)
  @discardableResult public func insert(_ o: Observation) throws -> Int64
  public func upsertText(_ text: String, source: String) throws -> Int64       // SHA256 해시 중복 제거
  public func insertFileEvent(_ e: FileEvent) throws
  public func openIdle(at: Double) throws; public func closeIdle(at: Double) throws
  public func unprocessed(limit: Int) throws -> [Observation]
  public func texts(ids: [Int64]) throws -> [Int64: String]
  public func idleSpans(from: Double, to: Double) throws -> [IdleSpan]
  public func recent(limit: Int) throws -> [Observation]
  public func recentBatches(limit: Int) throws -> [BatchRecord]
  public static func mark(_ db: Database, observationIds: [Int64], batchId: Int64) throws }
public struct ActivityRow: Codable, Equatable, Sendable { row, start, end, dwell, app, appBundle, title, uri, type, projectKey, projectTitle, snippet, observationIds }
public enum EventCompressor { public static func compress(_ obs: [Observation], idle: [IdleSpan], texts: [Int64: String], windowEnd: Double, home: String, fileExists: (String) -> Bool, maxRows: Int, snippetChars: Int, snippetTopN: Int) -> [ActivityRow] }
```
- [x] 테스트: 같은 텍스트 두 번 → 같은 id, 연속 동일 컨텍스트 병합, 2초 미만 행은 앞 행에 흡수, 유휴 구간은 dwell에서 제외, 단일 dwell 상한 300초, snippet은 dwell 상위 N개 행에만
- [x] 구현 → 테스트 통과

### Task 5: LLM 클라이언트

**Files:** `LLM/LLMClient.swift`, `LLM/OpenAICompatClient.swift`, 테스트(URLProtocol 스텁)

**Produces:**
```swift
public struct ToolSpec: Sendable { public let name, description: String; public let parameters: JSONValue }
public struct LLMResult: Sendable { public let arguments: Data; public let model: String; public let promptTokens, completionTokens: Int; public let raw: String }
public protocol LLMClient: Sendable { func callFunction(system: String, user: String, tool: ToolSpec) async throws -> LLMResult }
public enum LLMError: Error { case http(Int, String), noJSON(String), transport(String) }
public final class OpenAICompatClient: LLMClient { public init(baseURL: URL, model: String, apiKey: String?, timeout: TimeInterval, session: URLSession)
  public func ping() async -> Bool }                                          // GET {base}/models
```
요청: `tool_choice: "required"`, `stream: false`. 비-2xx면 `tool_choice` 없이 1회 재시도.
- [x] 테스트: `tool_calls[0].function.arguments` 파싱, 본문 JSON 폴백, ```json 코드펜스 폴백, 500 → 재시도 후 성공, JSON 없음 → `.noJSON`
- [x] 구현 → 테스트 통과

### Task 6: 온톨로지 패치 · 프롬프트 · 반영기

**Files:** `Ontology/OntologyPatch.swift`, `OntologyPrompt.swift`, `OntologyApplier.swift`, 테스트(프론트 개발 픽스처)

**Produces:**
```swift
public struct OntologyPatch: Codable, Equatable { public var segments: [Segment] }   // Segment: fromRow,toRow,task{match,id,title,taskType},summary,topics,problems?,laterItems?,switchKind?
public enum OntologySchema { public static let tool: ToolSpec }                       // record_activity
public enum OntologyPrompt { public static func build(rows: [ActivityRow], openTasks: [TaskDigest], now: Double) -> (system: String, user: String) }
public struct ApplyStats: Equatable { sessions, tasksCreated, resources, topics, problems, laterItems, uncoveredRows }
public struct OntologyApplier { public init(); public func apply(_ patch: OntologyPatch, rows: [ActivityRow], tx: GraphTx, now: Double) throws -> ApplyStats }
```
- [x] 테스트: 픽스처 반영 후 Task 1·Session 1·Resource 4·App 4·Topic 2·Problem 1·LaterItem 1, `RESOLVED_BY`가 SO 글을 가리킴, TOUCHED weight = 해당 행 dwell 합, 같은 Task의 다음 세그먼트(간격 5분 미만)는 Session을 늘림, 알 수 없는 task_type → `기타`, 범위 밖 row는 무시하고 `uncoveredRows` 집계, `match:"existing"`인데 id가 없으면 제목으로 기존 Task 재사용
- [x] 구현 → 테스트 통과

### Task 7: 배치 실행기

**Files:** `Ontology/OntologyBatcher.swift`, 테스트(스텁 LLM)

**Produces:**
```swift
public struct BatchConfig: Sendable { minAge: 300, maxWindow: 1800, maxRows: 150, snippetChars: 300, snippetTopN: 12 }
public enum BatchOutcome: Equatable { case skipped(String), ok(ApplyStats), failed(String) }
public actor OntologyBatcher { public init(db: WGDatabase, llm: any LLMClient, config: BatchConfig, home: String, clock: @escaping @Sendable () -> Double)
  public func runIfDue(force: Bool) async -> BatchOutcome }
```
- [x] 테스트: 미처리 없음 → skipped, 5분 미경과 → skipped(단 `force`면 실행), 성공 → 행에 batch_id·`batches.status=ok`, LLM 실패 → 행 미처리 유지·`failed` 기록·백오프 중에는 skipped, 성공 후 재실행 → 그래프 변화 없음
- [x] 구현 → `swift test` 전체 통과

### Task 8: 내보내기 + CLI + 데모 시드

**Files:** `Export/GraphJSONExporter.swift`, `Export/CypherExporter.swift`, `Demo/DemoScenarios.swift`, `Sources/wgctl/main.swift`, 테스트

**Produces:** `wgctl --db <path> (seed-demo | batch [--base-url U] [--model M] [--force] | export-graph <file> [--tbox] | export-cypher <file> | stats | neighbors <label> <key> [--hops N])`
- [x] 테스트: JSON에 `nodes[].degree`, `links[].source/target` 포함, Cypher는 `MERGE` 문이고 따옴표 이스케이프
- [x] 통합 검증: 스크래치 DB에 `seed-demo` → 실제 LLM으로 `batch --force` → `stats`에 Task/Session/Resource 생성 확인

### Task 9: 그래프 뷰 (웹)

**Files:** `Resources/graph/index.html`, `graph.js`, `style.css`, `vendor/force-graph.min.js`

**Interfaces:** `window.WG.setGraph({nodes, links})`, Swift로 보내는 메시지 `{type:"open", uri}` / `{type:"refresh"}`. 브라우저 단독 실행 시 `?data=<json url>`로 로드.
- [x] 구현: 스펙 7절 (호버 하이라이트, 라벨 줌 임계, 검색, 라벨 필터, 클래스 층 토글, 로컬 그래프 깊이, 상세 패널)
- [x] 검증: Task 8의 export JSON으로 헤드리스 브라우저 스크린샷 → 육안 확인, 콘솔 에러 0

### Task 10: 수집기

**Files:** `Sources/WorkGraphCollectors/*`

**Produces:**
```swift
public struct ContextSnapshot: Equatable, Sendable { appBundle, appName, windowTitle, url, docPath, pid }
@MainActor public final class CollectorCoordinator { public init(store: EventStore, capturesDir: URL, settings: CollectorSettings)
  public func start(); public func stop(); public var isPaused: Bool; public var onObservation: ((Observation) -> Void)? }
public enum Permissions { static func accessibility(prompt: Bool) -> Bool; static func screenRecording() -> Bool; static func requestScreenRecording(); static func openSettings(_ pane: Pane) }
```
- [x] 구현: 스펙 4절 표와 규칙 그대로. 권한 없으면 해당 수집기만 비활성
- [x] 검증: `swift build` 통과 + 앱 스모크 테스트(Task 11)에서 행 생성 확인

### Task 11: 앱 + 번들 스크립트

**Files:** `Sources/WorkGraphApp/*`, `scripts/make-app.sh`

- [x] 구현: 메뉴바(상태·오늘 기록 수·그래프 열기·지금 정리·일시정지·종료), 창 3탭, 설정(UserDefaults), 60초마다 `runIfDue`, 배치 후 그래프 갱신
- [x] `make-app.sh`: release 빌드 → `build/WorkGraph.app` (Info.plist: `LSUIElement`, 번들 ID, 권한 사용 설명) → 리소스 복사 → 서명(`SIGN_IDENTITY`, 실패·지연 시 ad-hoc)
- [x] 검증: 앱 실행 후 프로세스 생존, DB 파일 생성, observations 증가, 크래시 로그 없음

### Task 12: README + 최종 검증

- [x] README(팀원용, 짧게): 빌드·실행·권한·gpt-proxy 연결·CLI 데모·DB 열어보는 법
- [x] `swift build`, `swift test` 전체, 데모 파이프라인, 앱 스모크를 새로 실행해 결과 기록

### Task 13: 앱 안 ChatGPT 로그인 + Codex 직접 호출 (2026-09-21 추가)

**Files:** `Sources/WorkGraphCore/LLM/Codex/{CodexAuthModels,CodexAuthStore,CodexOAuthClient,CodexAuthManager,CodexResponsesClient}.swift`, 테스트 2개, `wgctl`, 앱 설정 화면

**Produces:**
```swift
public actor CodexAuthManager: CodexCredentialProviding { status(), beginDeviceLogin(), completeDeviceLogin(_:), credentials(), refreshAfterRejection(of:), logout() }
public final class CodexResponsesClient: LLMClient { init(auth:model:reasoningEffort:…); static func listModels(auth:) async throws -> [CodexModel] }
```
- [x] 테스트: JWT 클레임, 저장소 권한 600, 기기 코드 폴링·교환, 시간 초과, 만료 임박 갱신과 회전 토큰 저장, 동시 호출 시 갱신 1회, 다른 프로세스가 갱신한 토큰 재사용, 폐기된 토큰 → 재로그인 요구, 요청 형식, SSE 파싱 3경로, 401 후 재시도, tool_choice 거절 시 auto, 모델 목록
- [x] 실서버 검증: 코드 발급, `gpt-5.6-luna` 로 데모 하루치 온톨로지화

### Task 14: 로그인 필수 온보딩 + 중복 실행 방지 (2026-09-22 추가)

**Files:** `Sources/WorkGraphCore/Models/AppPhase.swift`, `Storage/InstanceLock.swift`, `Sources/WorkGraphApp/Views/OnboardingView.swift`, `AppState.swift`(단계 기반으로 변경), `MainWindow.swift`, `MenuBarView.swift`, `WorkGraphApp.swift`
- [x] 테스트: 로그인 전에는 항상 `login`, 첫 로그인 뒤 한 번만 `permissions`, `ready` 에서만 서비스 실행 / 같은 잠금은 두 번째가 못 잡음, 다른 데이터 폴더끼리는 안 막음
- [x] 확인: 로그인·권한 두 화면 캡처, 로그인 전 12초 동안 새 행 0개, 두 번째 인스턴스가 DB 를 열지 않음

### Task 15: 과분할 개선 · Dock 아이콘 · 사용량 (2026-09-22 추가)

**Files:** `Ontology/SegmentNormalizer.swift`, `OntologyBatcher.swift`, `OntologyPrompt.swift`, `GraphTx.swift`(TaskDigest 에 자료 키·앱), `LLM/Codex/CodexResponsesClient.swift`(fetchUsage), `wgctl`(rebuild-graph, codex-usage), `WorkGraphApp.swift`, `scripts/make-icon.swift`
- [x] 테스트: 짧은 구간의 기존 업무 재사용·묶음 승격·끼어들기 흡수·공용 업무·단일 구간 예외·같은 배치 내 업무 합류·실제 패턴 회귀, 사용량 응답 파싱
- [x] 확인: 실제 DB 사본으로 16개 → 5개 확인 후 원본 백업하고 적용, Dock 표시·재실행 시 창 열림, 실제 계정 사용량 조회

### Task 16: 관계 스키마 검증 + PROV-O RDF 내보내기 (2026-09-22 추가)

**Files:** `Ontology/RelationSchema.swift`(ClassSchema, RelationSchema, OntologyError), `Storage/GraphTx.swift`(upsertEdge 검증), `Export/RDFExporter.swift`, `wgctl`(schema, export-rdf)
- [x] 테스트: 모든 EdgeType 에 규칙 존재·라벨 유효, 정의역·치역 쌍 판정, 저장소가 잘못된 방향·모르는 관계·없는 노드를 거부, 어휘 선언, PROV 패턴(qualifiedUsage·wasGeneratedBy·subClassOf 계층), 리터럴 이스케이프, 문장 종결
- [x] 확인: 실제 그래프 Turtle 을 rdflib 로 파싱 + SPARQL 5종

### Task 17: 원시 데이터·LLM 입출력 열람 (2026-09-22 추가)

**Files:** `WGDatabase.swift`(v2: batches 에 system_prompt/user_prompt/llm_patch/applied_patch, v3: v_rows/v_batches/v_nodes/v_edges/v_sessions 뷰), `OntologyBatcher.swift`(저장), `ActivityLogView.swift`(선택 → 상세 패널), `wgctl`(rows, batches, batch-show, dump)
- [x] 테스트: 컬럼 존재·왕복, 성공·실패 배치 모두 프롬프트 저장, 뷰 조인
- [x] 확인: 실제 배치 #26 에 프롬프트 5,346자·응답 저장, 데모 DB 별도 인스턴스에서 상세 패널 캡처, DBeaver 연결 생성

### Task 18: AI 대화 기록 수집 + 제외 앱 설정 (2026-09-22 추가)

**Files:** `WGDatabase.swift`(v4: chat_messages, chat_cursors, v_chats), `Models/Observation.swift`(ChatMessage), `EventStore.swift`, `Ontology/ChatLogReader.swift`, `EventCompressor.swift`(merge), `OntologyBatcher.swift`, `OntologyPrompt.swift`, `OntologyApplier.swift`, `Collectors/ChatLogWatcher.swift`, `CollectorCoordinator.swift`(readChatLogs, 제외 앱 이름 유지), `PrivacyFilter.swift`(defaultNames), `Views/ExcludedAppsView.swift`, `SettingsView.swift`
- [x] 테스트: Claude/Codex 파싱(필터·자르기·cwd 조회), 저장 중복 제거·창 조회·커서, 대화 행 병합(순서·체류 0·프로젝트), 프롬프트·그래프 반영
- [x] 확인: 실제 세션 26건 자동 수집, 설정 화면 캡처

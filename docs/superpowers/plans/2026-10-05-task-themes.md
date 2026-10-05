# 업무 분야(테마)와 업무 종류 정리 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 업무 위에 넓은 분야(Theme) 클래스를 두고, 정리 뒤·앱 시작 때 도는 테마 단계가 업무마다 분야 하나와 (옛 판이면) 업무 종류를 붙인다.

**Architecture:** 온톨로지에 `Theme` 라벨과 `Task —PART_OF→ Theme` 관계를 더하고, 기본 분야·상한·이름 비교는 `ThemeCatalog`, 분야 노드 조작은 `ThemeGraph` 가 맡는다. `ThemeStep` 은 대상 읽기(load) → LLM 호출 한 번(judge) → 검증하며 반영(apply)으로 나뉘어, 정리기(OntologyBatcher)·앱 시작·wgctl 이 같은 코드를 쓴다. 업무 종류 목록에 판(`TBox.version`)을 두어 기존 업무는 첫 실행 때 한 번 종류가 다시 붙는다.

**Tech Stack:** Swift 5 (swift-tools 5.10), macOS 14, GRDB 7, XCTest, 그래프 뷰는 WKWebView 안의 force-graph(JS)

**Spec:** `docs/superpowers/specs/2026-10-05-task-themes-design.md`

## Global Constraints

- 커밋하지 않는다 — 사용자 규칙 "커밋은 요청할 때만". 계획에 커밋 단계가 없다.
- 기본 분야: 학업, 취업 준비, 프로젝트, 직장 업무, 생활 행정, 자기계발. 분야 노드는 기본 분야를 포함해 사용자당 최대 20개.
- 업무 종류 추가: 행정처리 ⊃ 신청·지원, 일정·공지확인 / 학습 ⊃ 면접·시험준비. 고를 수 있는 종류는 14개. `TBox.version` = 2.
- LLM 프롬프트에 예시를 넣지 않는다 (일반 규칙만). 기본 분야 이름은 사용자 프롬프트의 후보 목록(데이터)으로만 들어가고 시스템 프롬프트에는 없다.
- 정답·활동 데이터는 저장소 밖 `~/Library/Application Support/WorkGraph/eval/` 에 둔다.
- 실 앱 인스턴스는 자동으로 조작하지 않는다. 데이터를 바꾸는 확인은 데모 DB 와 CLI 로만 한다.
- 화면 문구는 사용자 말로 쓴다 ("분야", "업무"). 구현 용어를 화면에 쓰지 않는다.
- 한 번 붙은 분야는 테마 단계가 바꾸지 않는다.

## Review Focus

- 시간 범위를 고른 그래프 뷰: 오래전에 이어진 분야도, 보이는 업무의 분야라면 함께 보여야 한다 → Task 4 `testATimeWindowStillShowsTheThemesOfVisibleTasks`.
- 앱 시작 때 로그인이 안 됐거나 오프라인이라 테마 단계가 실패: 예외 없이 로그만 남고 앱·정리는 그대로 → Task 3 `testAssignThemesNeverThrowsWhenTheModelIsUnreachable`.
- 한 호출에서 두 업무가 같은 새 분야를 답함: 분야 노드 하나만 생기고 자리도 하나만 쓴다 → Task 2 `testApplyReusesCreatesSharesANewThemeAndSkipsBadAnswers`.
- 모델이 기본 분야를 공백만 다르게 답함("취업준비"): 기본 분야 표기("취업 준비")로 만들고, 다음 답도 같은 분야로 간다 → Task 1 `testAttachReusesTheSameNameCanonicalizesDefaultsAndRejectsLongNames`.
- 모델이 분야 이름 대신 문장을 답함(20자 초과): 받지 않고 다음 기회에 다시 묻는다 → Task 1 같은 테스트.

## File Structure

- `Sources/WorkGraphCore/Models/GraphModels.swift` — `NodeLabel.theme` 추가.
- `Sources/WorkGraphCore/Ontology/RelationSchema.swift` — `ClassSchema` 에 분야, `PART_OF` 에 업무 → 분야 쌍.
- `Sources/WorkGraphCore/Ontology/TBox.swift` — 새 종류 3개, `version`, `leafType(_:)`.
- `Sources/WorkGraphCore/Ontology/Themes/ThemeCatalog.swift` (새 파일) — `ThemeCatalog`(기본 분야·상한·이름 규칙), `ThemeGraph`(분야 노드 읽기·잇기·정리).
- `Sources/WorkGraphCore/Ontology/Themes/ThemeStep.swift` (새 파일) — 테마 단계: 프롬프트·도구·해석·대상 읽기·반영·실행.
- `Sources/WorkGraphCore/Ontology/AssignmentApplier.swift` — 새 업무에 종류 판 기록.
- `Sources/WorkGraphCore/Ontology/OntologyBatcher.swift` — `BatchConfig.themes`, `assignThemes(now:)`, 합치기 뒤 호출.
- `Sources/WorkGraphCore/Ontology/TaskMerger.swift` — 합치기·업무 외 처리 뒤 분야 정리.
- `Sources/WorkGraphCore/Storage/GraphTx.swift` — 시간 범위 그래프에 보이는 업무의 분야 포함.
- `Sources/WorkGraphApp/AppState.swift` — 앱 시작 때 테마 단계.
- `Sources/WorkGraphApp/Resources/graph/graph.js` — 분야 색·이름, 업무→분야 연결 이름.
- `Sources/wgctl/main.swift` — `themes`, `assign-themes`, `theme-eval`, `batch --demo-llm` 에서 테마 단계 끄기.
- `Tests/WorkGraphCoreTests/ThemeTests.swift` (새 파일) — 분야 관련 테스트 전부.
- `Tests/WorkGraphCoreTests/OntologyBatcherTests.swift`, `Tests/WorkGraphCoreTests/StagedPipelineTests.swift` — 정리 테스트에서 테마 단계 끄기.

---

### Task 1: 온톨로지 — 분야 클래스·관계·기본 분야, 업무 종류와 판

**Files:**
- Modify: `Sources/WorkGraphCore/Models/GraphModels.swift` (NodeLabel)
- Modify: `Sources/WorkGraphCore/Ontology/RelationSchema.swift` (ClassSchema.classes, RelationSchema.rules 의 PART_OF)
- Modify: `Sources/WorkGraphCore/Ontology/TBox.swift`
- Create: `Sources/WorkGraphCore/Ontology/Themes/ThemeCatalog.swift`
- Modify: `Sources/WorkGraphCore/Ontology/AssignmentApplier.swift` (`resolveTask` 의 새 업무 props)
- Test: `Tests/WorkGraphCoreTests/ThemeTests.swift` (새 파일, `ThemeOntologyTests`)

**Interfaces:**
- Consumes: `GraphTx.upsertNode/upsertEdge/node/nodes/edges`, `RelationPair`, `Fixtures.patch/frontendRows` (테스트)
- Produces:
  - `NodeLabel.theme = "Theme"`
  - `ThemeCatalog.defaults: [String]`, `ThemeCatalog.limit = 20`, `ThemeCatalog.nameLimit = 20`, `ThemeCatalog.normalize(_:) -> String`, `ThemeCatalog.matchKey(_:) -> String`, `ThemeCatalog.canonical(_:) -> String`
  - `ThemeGraph.theme(ofTask: Int64, _ tx: GraphTx) throws -> GraphNode?`
  - `ThemeGraph.find(_ name: String, _ tx: GraphTx) throws -> GraphNode?`
  - `ThemeGraph.attach(taskId: Int64, to name: String, _ tx: GraphTx, now: Double) throws -> (node: GraphNode, created: Bool)?` (`@discardableResult`)
  - `ThemeGraph.pruneEmpty(_ tx: GraphTx) throws -> Int` (`@discardableResult`)
  - `TBox.version = 2`, `TBox.leafType(_ name: String) -> String?`
  - 새 업무의 `props["type_version"] = TBox.version`

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `Tests/WorkGraphCoreTests/ThemeTests.swift` 를 만든다:

```swift
import XCTest
import GRDB
@testable import WorkGraphCore

final class ThemeOntologyTests: XCTestCase {
    func testTasksArePartOfAThemeAndThemeIsAClass() {
        XCTAssertTrue(RelationSchema.allows(type: EdgeType.partOf, from: NodeLabel.task, to: NodeLabel.theme))
        XCTAssertFalse(RelationSchema.allows(type: EdgeType.partOf, from: NodeLabel.theme, to: NodeLabel.task))
        XCTAssertTrue(RelationSchema.allows(type: EdgeType.partOf, from: NodeLabel.session, to: NodeLabel.task), "세션 → 업무는 그대로")
        XCTAssertEqual(ClassSchema.definition(NodeLabel.theme)?.name, "분야")
    }

    func testNewTaskTypesAndVersion() {
        for name in ["신청·지원", "일정·공지확인", "면접·시험준비"] { XCTAssertTrue(TBox.leafTaskTypes.contains(name), name) }
        XCTAssertFalse(TBox.leafTaskTypes.contains("행정처리"), "상위 종류는 고를 수 없음")
        XCTAssertEqual(TBox.leafTaskTypes.count, 14)
        XCTAssertEqual(TBox.version, 2)
        XCTAssertEqual(TBox.leafType("신청 지원"), "신청·지원", "공백·가운뎃점 차이는 같은 종류")
        XCTAssertNil(TBox.leafType("행정처리"))
    }

    func testANewTaskRecordsTheTypeVersion() throws {
        let db = try WGDatabase.inMemory()
        let patch = try Fixtures.patch(#"{"tasks":[{"ref":"A","match":"new","title":"대시보드 카드 UI 구현","task_type":"코드작성"}],"rows":[{"rows":"1-6","task":"A"}]}"#)
        let version = try db.writer.write { conn -> Double? in
            let tx = GraphTx(conn)
            try TBox.seed(tx, at: 0)
            _ = try AssignmentApplier().apply(patch, rows: Fixtures.frontendRows(), tx: tx, now: 2_000_000)
            return try tx.nodes(label: NodeLabel.task).first?.props["type_version"]?.doubleValue
        }
        XCTAssertEqual(version, Double(TBox.version))
    }

    func testAttachReusesTheSameNameCanonicalizesDefaultsAndRejectsLongNames() throws {
        let db = try WGDatabase.inMemory()
        try db.writer.write { conn in
            let tx = GraphTx(conn)
            let a = try tx.upsertNode(label: NodeLabel.task, key: "t_a", subtype: nil, title: "A", props: [:], at: 0)
            let b = try tx.upsertNode(label: NodeLabel.task, key: "t_b", subtype: nil, title: "B", props: [:], at: 0)
            let c = try tx.upsertNode(label: NodeLabel.task, key: "t_c", subtype: nil, title: "C", props: [:], at: 0)
            let first = try XCTUnwrap(ThemeGraph.attach(taskId: a, to: "취업준비", tx, now: 1))
            XCTAssertEqual(first.node.title, "취업 준비", "기본 분야의 표기로 만든다")
            XCTAssertTrue(first.created)
            let second = try XCTUnwrap(ThemeGraph.attach(taskId: b, to: " 취업  준비 ", tx, now: 1))
            XCTAssertEqual(second.node.id, first.node.id)
            XCTAssertFalse(second.created)
            XCTAssertNil(try ThemeGraph.attach(taskId: a, to: "학업", tx, now: 1), "분야가 이미 있는 업무는 그대로")
            XCTAssertNil(try ThemeGraph.attach(taskId: c, to: String(repeating: "가", count: ThemeCatalog.nameLimit + 1), tx, now: 1),
                         "너무 긴 이름은 받지 않음")
            XCTAssertEqual(try ThemeGraph.theme(ofTask: b, tx)?.title, "취업 준비")
        }
    }

    func testThemesStopAtTheLimitAndEmptyOnesArePruned() throws {
        let db = try WGDatabase.inMemory()
        try db.writer.write { conn in
            let tx = GraphTx(conn)
            for index in 0..<ThemeCatalog.limit {
                let task = try tx.upsertNode(label: NodeLabel.task, key: "t_\(index)", subtype: nil, title: "업무 \(index)", props: [:], at: 0)
                XCTAssertNotNil(try ThemeGraph.attach(taskId: task, to: "분야 \(index)", tx, now: 1))
            }
            let extra = try tx.upsertNode(label: NodeLabel.task, key: "t_extra", subtype: nil, title: "추가", props: [:], at: 0)
            XCTAssertNil(try ThemeGraph.attach(taskId: extra, to: "새 분야", tx, now: 1), "20개가 차면 새 분야는 못 만든다")
            XCTAssertNotNil(try ThemeGraph.attach(taskId: extra, to: "분야 3", tx, now: 1), "있는 분야는 쓸 수 있다")
            try conn.execute(sql: "DELETE FROM edges WHERE src = (SELECT id FROM nodes WHERE key = 't_0')")
            XCTAssertEqual(try ThemeGraph.pruneEmpty(tx), 1)
            XCTAssertEqual(try tx.nodes(label: NodeLabel.theme).count, ThemeCatalog.limit - 1)
        }
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `swift test --filter ThemeOntologyTests 2>&1 | grep -E "error:|Executed" | head -5`
Expected: 컴파일 실패 — `type 'NodeLabel' has no member 'theme'` 류

- [ ] **Step 3: 구현한다**

`GraphModels.swift` 의 `NodeLabel` 에서 `laterItem` 줄 다음에:

```swift
    /// 업무를 묶는 넓은 분야 (업무 위의 상위 분류)
    public static let theme = "Theme"
```

`RelationSchema.swift` 의 `ClassSchema.classes` 에서 `NodeLabel.task` 줄 다음에:

```swift
        .init(label: NodeLabel.theme, name: "분야", standardSuperclass: "skos:Concept", meaning: "업무를 묶는 넓은 분야. 업무는 분야 하나에 속한다"),
```

같은 파일 `RelationSchema.rules` 의 PART_OF 규칙을 바꾼다:

```swift
        .init(type: EdgeType.partOf, pairs: [RelationPair(NodeLabel.session, NodeLabel.task), RelationPair(NodeLabel.task, NodeLabel.theme)],
              meaning: "세션이 업무에, 업무가 분야에 속한다", standard: "dcterms:isPartOf"),
```

`TBox.swift` 의 `taskTypes` 를 바꾸고 `version` 과 `leafType` 을 더한다:

```swift
    public static let taskTypes: [(name: String, parent: String?)] = [
        ("정보수집", nil), ("문헌조사", "정보수집"), ("시장조사", "정보수집"),
        ("산출물작성", nil), ("문서작성", "산출물작성"), ("발표자료", "산출물작성"), ("코드작성", "산출물작성"),
        ("커뮤니케이션", nil), ("회의", "커뮤니케이션"), ("메신저대응", "커뮤니케이션"),
        ("학습", nil), ("강의수강", "학습"), ("복습", "학습"), ("면접·시험준비", "학습"),
        ("반복작업", nil), ("데이터정리", "반복작업"),
        ("행정처리", nil), ("신청·지원", "행정처리"), ("일정·공지확인", "행정처리"),
        ("기타", nil),
    ]

    /// 업무 종류 목록의 판. 목록을 바꾸면 올린다. 업무를 만들 때 props.type_version 에 남기고, 옛 판 업무는 테마 단계가 종류를 다시 붙인다
    public static let version = 2
```

(`leafTaskTypes` 다음에)

```swift
    /// 고를 수 있는 종류 이름으로 맞춘다 (공백·가운뎃점 차이는 무시). 없으면 nil
    public static func leafType(_ name: String) -> String? {
        func key(_ text: String) -> String { text.filter { !$0.isWhitespace && $0 != "·" } }
        let wanted = key(name)
        return leafTaskTypes.first { key($0) == wanted }
    }
```

`AssignmentApplier.swift` 의 `resolveTask` 에서 새 업무를 만드는 줄을 바꾼다:

```swift
        let taskId = try tx.upsertNode(label: NodeLabel.task, key: key, subtype: nil, title: title,
                                       props: ["status": "active", "started_at": .number(now), "type_version": .number(Double(TBox.version))], at: now)
```

`Sources/WorkGraphCore/Ontology/Themes/ThemeCatalog.swift` 를 만든다:

```swift
import Foundation
import GRDB

/// 업무 위의 넓은 분야(테마). 기본 분야로 시작하고, 맞는 것이 없을 때만 새로 만든다
public enum ThemeCatalog {
    public static let defaults = ["학업", "취업 준비", "프로젝트", "직장 업무", "생활 행정", "자기계발"]
    /// 분야 노드의 최대 수 (기본 분야 포함). Jev 선택지 제한과 같다
    public static let limit = 20
    /// 분야 이름의 최대 글자 수. 이보다 긴 답은 이름이 아니라 문장으로 본다
    public static let nameLimit = 20

    /// 표시 이름: 공백을 하나로
    public static func normalize(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// 같은 분야인지 비교하는 키: 공백·대소문자 무시
    public static func matchKey(_ name: String) -> String {
        name.filter { !$0.isWhitespace }.lowercased()
    }

    /// 기본 분야와 공백·대소문자만 다르면 기본 분야의 표기로
    public static func canonical(_ name: String) -> String {
        let clean = normalize(name)
        return defaults.first { matchKey($0) == matchKey(clean) } ?? clean
    }
}

/// 분야 노드와 업무 → 분야 관계 (열린 트랜잭션 안에서)
public enum ThemeGraph {
    /// 업무가 속한 분야. 없으면 nil
    public static func theme(ofTask taskId: Int64, _ tx: GraphTx) throws -> GraphNode? {
        for edge in try tx.edges(from: taskId, type: EdgeType.partOf) {
            if let node = try tx.node(id: edge.dst), node.label == NodeLabel.theme { return node }
        }
        return nil
    }

    /// 이름이 같은 분야 (공백·대소문자 무시)
    public static func find(_ name: String, _ tx: GraphTx) throws -> GraphNode? {
        let key = ThemeCatalog.matchKey(name)
        return try tx.nodes(label: NodeLabel.theme).first { ThemeCatalog.matchKey($0.title) == key }
    }

    /// 업무를 분야에 잇는다. 같은 이름의 분야가 있으면 그것을, 없으면 자리가 남을 때만 만든다.
    /// 업무에 이미 분야가 있거나, 이름이 비었거나 너무 길거나, 자리가 없으면 nil
    @discardableResult
    public static func attach(taskId: Int64, to name: String, _ tx: GraphTx, now: Double) throws -> (node: GraphNode, created: Bool)? {
        let clean = ThemeCatalog.canonical(name)
        guard !clean.isEmpty, clean.count <= ThemeCatalog.nameLimit, try theme(ofTask: taskId, tx) == nil else { return nil }
        var created = false
        let node: GraphNode
        if let existing = try find(clean, tx) {
            node = existing
        } else {
            guard try tx.nodes(label: NodeLabel.theme).count < ThemeCatalog.limit else { return nil }
            let id = try tx.upsertNode(label: NodeLabel.theme, key: clean, subtype: nil, title: clean, props: [:], at: now)
            guard let made = try tx.node(id: id) else { return nil }
            node = made
            created = true
        }
        try tx.upsertEdge(src: taskId, dst: node.id, type: EdgeType.partOf, props: [:], addWeight: 0, at: now, countHit: false)
        return (node, created)
    }

    /// 업무가 하나도 없는 분야를 지운다. 지운 수
    @discardableResult
    public static func pruneEmpty(_ tx: GraphTx) throws -> Int {
        let empty = try Int64.fetchAll(tx.db, sql: """
            SELECT id FROM nodes WHERE label = 'Theme' AND id NOT IN (SELECT dst FROM edges WHERE type = 'PART_OF')
            """)
        for id in empty {
            try tx.db.execute(sql: "DELETE FROM edges WHERE src = ? OR dst = ?", arguments: [id, id])
            try tx.db.execute(sql: "DELETE FROM nodes WHERE id = ?", arguments: [id])
        }
        return empty.count
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `swift test --filter "ThemeOntologyTests|RelationSchemaTests|GraphTxTests" 2>&1 | grep -E "error:|Executed" | tail -3`
Expected: `Executed N tests, with 0 failures`

- [ ] **Step 5: 전체 테스트**

Run: `swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -2`
Expected: 0 failures

---

### Task 2: 테마 단계 — 대상 읽기, 프롬프트, 해석, 반영, 실행

**Files:**
- Create: `Sources/WorkGraphCore/Ontology/Themes/ThemeStep.swift`
- Test: `Tests/WorkGraphCoreTests/ThemeTests.swift` (`ThemeStepTests` 추가)

**Interfaces:**
- Consumes: `ThemeCatalog`, `ThemeGraph` (Task 1), `TBox.version/leafType/leafTaskTypes`, `GraphTx.openTasks(limit:since:)`, `LLMClient.callFunction`, `ToolSpec`, `AssignmentPatch.unwrapStrings`, `OntologyPrompt.clip`, `StubLLM`(테스트)
- Produces:
  - `ThemeStep.Target(key:title:goal:taskType:recent:needsTheme:needsType:)`
  - `ThemeStep.ThemeLine(name:tasks:)`
  - `ThemeStep.Answer(theme: String?, taskType: String?)`
  - `ThemeStep.Outcome` (`themed`, `retyped`, `created: [String]`, `skipped`)
  - `ThemeStep.tool: ToolSpec` (이름 `assign_themes`), `ThemeStep.system: String`, `ThemeStep.user(targets:themes:) -> String`
  - `ThemeStep.decode(_ data: Data) -> [String: Answer]`
  - `ThemeStep.load(_ tx: GraphTx, retypeAll: Bool = false) throws -> (targets: [Target], themes: [ThemeLine])`
  - `ThemeStep.judge(targets: [Target], themes: [ThemeLine], llm: any LLMClient) async throws -> [String: Answer]`
  - `ThemeStep.apply(_ answers: [String: Answer], targets: [Target], _ tx: GraphTx, now: Double) throws -> Outcome`
  - `ThemeStep.run(db: WGDatabase, llm: any LLMClient, now: Double, retypeAll: Bool = false) async throws -> Outcome?` (대상이 없으면 호출 없이 nil)

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `ThemeTests.swift` 끝에 더한다:

```swift
final class ThemeStepTests: XCTestCase {
    /// 업무 노드 (분야·종류·판·목표는 선택)
    static func task(_ tx: GraphTx, _ key: String, _ title: String, theme: String? = nil, type: String? = nil,
                     version: Int? = nil, goal: String? = nil) throws -> Int64 {
        var props: [String: JSONValue] = ["status": "active", "last_active": .number(100)]
        if let version { props["type_version"] = .number(Double(version)) }
        if let goal { props["goal"] = .string(goal) }
        let id = try tx.upsertNode(label: NodeLabel.task, key: key, subtype: nil, title: title, props: props, at: 100)
        if let type, let typeNode = try tx.node(label: NodeLabel.taskType, key: type) {
            try tx.upsertEdge(src: id, dst: typeNode.id, type: EdgeType.instanceOf, props: [:], addWeight: 0, at: 100, countHit: false)
        }
        if let theme { try ThemeGraph.attach(taskId: id, to: theme, tx, now: 100) }
        return id
    }

    static func seeded() throws -> WGDatabase {
        let db = try WGDatabase.inMemory()
        try db.writer.write { try TBox.seed(GraphTx($0), at: 0) }
        return db
    }

    /// "종류 | 분야 | 판"
    static func summary(_ db: WGDatabase, _ key: String) throws -> String {
        try db.writer.read { conn in
            let tx = GraphTx(conn)
            guard let node = try tx.node(label: NodeLabel.task, key: key) else { return "없음" }
            let type = try tx.edges(from: node.id, type: EdgeType.instanceOf).compactMap { try tx.node(id: $0.dst)?.title }.joined(separator: ",")
            let theme = try ThemeGraph.theme(ofTask: node.id, tx)?.title ?? "-"
            let version = Int(node.props["type_version"]?.doubleValue ?? 0)
            return "\(type) | \(theme) | \(version)"
        }
    }

    func testOnlyTasksWithoutAThemeOrWithAnOldTypeAreTargets() throws {
        let db = try Self.seeded()
        let loaded = try db.writer.write { conn -> (targets: [ThemeStep.Target], themes: [ThemeStep.ThemeLine]) in
            let tx = GraphTx(conn)
            _ = try Self.task(tx, "t_done", "끝난 정리", theme: "학업", type: "복습", version: 2)
            _ = try Self.task(tx, "t_new", "새 업무", type: "코드작성", version: 2)
            _ = try Self.task(tx, "t_old", "옛 업무", theme: "프로젝트", type: "기타")
            return try ThemeStep.load(tx)
        }
        XCTAssertEqual(loaded.targets.map(\.key).sorted(), ["t_new", "t_old"])
        let byKey = Dictionary(uniqueKeysWithValues: loaded.targets.map { ($0.key, $0) })
        XCTAssertEqual(byKey["t_new"]?.needsTheme, true)
        XCTAssertEqual(byKey["t_new"]?.needsType, false)
        XCTAssertEqual(byKey["t_old"]?.needsTheme, false)
        XCTAssertEqual(byKey["t_old"]?.needsType, true)
        XCTAssertEqual(Set(loaded.themes.map(\.name)), ["학업", "프로젝트"])
        XCTAssertEqual(loaded.themes.first { $0.name == "학업" }?.tasks, ["끝난 정리"])
    }

    func testPromptCarriesThemesDefaultsSlotsAndNeedsButTheRulesHaveNoExamples() {
        let target = ThemeStep.Target(key: "t_a", title: "현대오토에버 과제테스트 지원", goal: "신입 채용에 지원한다", taskType: "기타",
                                      recent: ["과제 안내를 읽었다"], needsTheme: true, needsType: true)
        let user = ThemeStep.user(targets: [target], themes: [ThemeStep.ThemeLine(name: "취업 준비", tasks: ["AI SCM 면접 준비"])])
        XCTAssertTrue(user.contains("- 취업 준비 | tasks: AI SCM 면접 준비"))
        XCTAssertTrue(user.contains("DEFAULT_THEMES (not used yet): 학업, 프로젝트, 직장 업무, 생활 행정, 자기계발"))
        XCTAssertTrue(user.contains("SLOTS: 19"))
        XCTAssertTrue(user.contains("TASK_TYPES: "))
        XCTAssertTrue(user.contains("- id=t_a | NEEDS_THEME, NEEDS_TYPE | 현대오토에버 과제테스트 지원 | goal: 신입 채용에 지원한다 | type: 기타 | recent: 과제 안내를 읽었다"))
        for name in ThemeCatalog.defaults { XCTAssertFalse(ThemeStep.system.contains(name), "규칙에 분야 예시를 넣지 않는다: \(name)") }
        let themeOnly = ThemeStep.user(targets: [ThemeStep.Target(key: "t_b", title: "B", goal: nil, taskType: nil, recent: [],
                                                                  needsTheme: true, needsType: false)], themes: [])
        XCTAssertFalse(themeOnly.contains("TASK_TYPES:"), "종류를 다시 붙일 업무가 없으면 종류 목록을 보내지 않는다")
        XCTAssertTrue(themeOnly.contains("THEMES:\n(none)"))
    }

    func testDecodeReadsThemesAndTypesLeniently() {
        let data = Data(#"{"tasks":[{"id":"t_a","theme":" 취업  준비 ","new_theme":false,"task_type":"신청 지원"},{"id":"t_b","theme":"","task_type":"모름"},{"theme":"학업"}]}"#.utf8)
        let answers = ThemeStep.decode(data)
        XCTAssertEqual(answers["t_a"], ThemeStep.Answer(theme: "취업 준비", taskType: "신청·지원"))
        XCTAssertEqual(answers["t_b"], ThemeStep.Answer(theme: nil, taskType: nil))
        XCTAssertEqual(answers.count, 2, "id 없는 답은 버린다")
    }

    func testApplyReusesCreatesSharesANewThemeAndSkipsBadAnswers() throws {
        let db = try Self.seeded()
        let outcome = try db.writer.write { conn -> ThemeStep.Outcome in
            let tx = GraphTx(conn)
            _ = try Self.task(tx, "t_job", "AI SCM 면접 준비", theme: "취업 준비", version: 2)
            for key in ["t_a", "t_b", "t_c", "t_d", "t_e"] { _ = try Self.task(tx, key, key, version: 2) }
            let targets = try ThemeStep.load(tx).targets
            let answers: [String: ThemeStep.Answer] = [
                "t_a": .init(theme: "취업준비", taskType: nil),
                "t_b": .init(theme: "부업", taskType: nil),
                "t_c": .init(theme: "부업", taskType: nil),
                "t_d": .init(theme: nil, taskType: nil),
                "t_zz": .init(theme: "학업", taskType: nil),
            ]
            return try ThemeStep.apply(answers, targets: targets, tx, now: 200)
        }
        XCTAssertEqual(outcome.themed, 3)
        XCTAssertEqual(outcome.created, ["부업"], "같은 호출의 새 분야는 하나만 생긴다")
        XCTAssertEqual(outcome.skipped, 2, "빈 답(t_d)과 답 없음(t_e)")
        let themes = try db.writer.read { try GraphTx($0).nodes(label: NodeLabel.theme).map(\.title) }
        XCTAssertEqual(Set(themes), ["취업 준비", "부업"], "대상에 없는 id 의 답은 반영하지 않는다")
    }

    func testRetypeReplacesTheTypeAndRecordsTheVersion() throws {
        let db = try Self.seeded()
        let outcome = try db.writer.write { conn -> ThemeStep.Outcome in
            let tx = GraphTx(conn)
            _ = try Self.task(tx, "t_a", "과제테스트 지원", theme: "취업 준비", type: "기타")
            _ = try Self.task(tx, "t_b", "혜택 신청", theme: "생활 행정", type: "시장조사")
            let targets = try ThemeStep.load(tx).targets
            let answers: [String: ThemeStep.Answer] = ["t_a": .init(theme: "학업", taskType: "신청·지원"), "t_b": .init(theme: nil, taskType: nil)]
            return try ThemeStep.apply(answers, targets: targets, tx, now: 200)
        }
        XCTAssertEqual(outcome.retyped, 1)
        XCTAssertEqual(try Self.summary(db, "t_a"), "신청·지원 | 취업 준비 | 2", "분야가 있는 업무의 분야 답은 무시")
        XCTAssertEqual(try Self.summary(db, "t_b"), "시장조사 | 생활 행정 | 0", "답이 없으면 종류와 판이 그대로")
    }

    func testRunSkipsTheCallWhenNothingIsMissingAndPrunesEmptyThemes() async throws {
        let db = try Self.seeded()
        try await db.writer.write { conn in
            let tx = GraphTx(conn)
            _ = try Self.task(tx, "t_a", "A", theme: "학업", type: "복습", version: 2)
            let gone = try tx.upsertNode(label: NodeLabel.task, key: "t_gone", subtype: nil, title: "지워질 업무", props: [:], at: 0)
            try ThemeGraph.attach(taskId: gone, to: "자기계발", tx, now: 0)
            try conn.execute(sql: "DELETE FROM edges WHERE src = ?", arguments: [gone])
            try conn.execute(sql: "DELETE FROM nodes WHERE id = ?", arguments: [gone])
        }
        let llm = StubLLM([])
        let outcome = try await ThemeStep.run(db: db, llm: llm, now: 300)
        XCTAssertNil(outcome)
        XCTAssertEqual(llm.calls, 0)
        let themes = try await db.writer.read { try GraphTx($0).nodes(label: NodeLabel.theme).map(\.title) }
        XCTAssertEqual(themes, ["학업"], "업무가 없는 분야는 지운다")
    }

    func testRunSendsOneCallAndAppliesTheAnswer() async throws {
        let db = try Self.seeded()
        try await db.writer.write { conn in _ = try Self.task(GraphTx(conn), "t_a", "자료구조 강의 수강", type: "강의수강") }
        let llm = StubLLM([.success(#"{"tasks":[{"id":"t_a","theme":"학업","new_theme":false,"task_type":"강의수강"}]}"#)])
        let outcome = try await ThemeStep.run(db: db, llm: llm, now: 300)
        XCTAssertEqual(outcome?.themed, 1)
        XCTAssertEqual(outcome?.retyped, 1)
        XCTAssertEqual(outcome?.created, ["학업"])
        XCTAssertEqual(llm.calls, 1)
        XCTAssertTrue(llm.lastUser.contains("NEEDS_THEME, NEEDS_TYPE"))
        XCTAssertEqual(try Self.summary(db, "t_a"), "강의수강 | 학업 | 2")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `swift test --filter ThemeStepTests 2>&1 | grep -E "error:|Executed" | head -5`
Expected: 컴파일 실패 — `cannot find 'ThemeStep' in scope`

- [ ] **Step 3: 구현한다** — `Sources/WorkGraphCore/Ontology/Themes/ThemeStep.swift`:

```swift
import Foundation

/// 테마 단계: 분야가 없는 업무에 분야를, 종류가 옛 판으로 붙은 업무에 종류를 붙인다 (정리 뒤·앱 시작)
public enum ThemeStep {
    /// 판정할 업무
    public struct Target: Equatable, Sendable {
        public var key: String
        public var title: String
        public var goal: String?
        public var taskType: String?
        public var recent: [String]
        public var needsTheme: Bool
        public var needsType: Bool

        public init(key: String, title: String, goal: String?, taskType: String?, recent: [String], needsTheme: Bool, needsType: Bool) {
            self.key = key; self.title = title; self.goal = goal; self.taskType = taskType; self.recent = recent
            self.needsTheme = needsTheme; self.needsType = needsType
        }
    }

    /// 분야 목록의 한 줄: 이름과 거기 속한 업무 제목
    public struct ThemeLine: Equatable, Sendable {
        public var name: String
        public var tasks: [String]
        public init(name: String, tasks: [String]) { self.name = name; self.tasks = tasks }
    }

    /// 업무 하나에 대한 답 (해석한 뒤: 이름은 공백 정리, 종류는 고를 수 있는 이름)
    public struct Answer: Equatable, Sendable {
        public var theme: String?
        public var taskType: String?
        public init(theme: String?, taskType: String?) { self.theme = theme; self.taskType = taskType }
    }

    public struct Outcome: Equatable, Sendable {
        public var themed = 0
        public var retyped = 0
        public var created: [String] = []
        /// 받아들이지 않은 답 (다음 기회에 다시 묻는다)
        public var skipped = 0
        public init() {}
    }

    public static var tool: ToolSpec {
        ToolSpec(name: "assign_themes", description: "Assign a theme, and a task type when asked, to every task.", parameters: .object([
            "type": "object",
            "properties": .object(["tasks": .object(["type": "array", "description": "받은 업무를 빠짐없이", "items": .object([
                "type": "object",
                "properties": .object([
                    "id": .object(["type": "string", "description": "TASKS 의 id"]),
                    "theme": .object(["type": "string", "description": "NEEDS_THEME 일 때: 분야 이름 (짧은 한국어 명사구)"]),
                    "new_theme": .object(["type": "boolean", "description": "THEMES·DEFAULT_THEMES 에 없는 새 분야면 true"]),
                    "task_type": .object(["type": "string", "enum": .array(TBox.leafTaskTypes.map { .string($0) }), "description": "NEEDS_TYPE 일 때"]),
                ]),
                "required": .array(["id"]),
            ])])]),
            "required": .array(["tasks"]),
        ]))
    }

    public static let system = """
    You place each of the user's tasks in a broad area of their life (a theme), for a personal work graph.

    You receive:
    - THEMES: the themes the user already has, each with titles of its tasks. DEFAULT_THEMES: starting themes not used yet. SLOTS: how many more themes may be created.
    - TASKS: each task's id, what it needs (NEEDS_THEME, NEEDS_TYPE), title, what it is for (`goal:`), current type and what was done recently.
    - TASK_TYPES: the allowed task types, only when a task needs a type.

    Themes (NEEDS_THEME):
    - A theme is a broad area that holds many different goals over time. Choose the theme that the task's goal belongs to, judged from its goal and recent work, not from the app or site used.
    - Reuse a theme from THEMES whenever the task fits it. Otherwise choose a fitting theme from DEFAULT_THEMES.
    - Create a new theme only when nothing in THEMES or DEFAULT_THEMES fits, and only for a broad area that can hold several different goals; set new_theme to true. A single goal, a single company, a single course or a single project is never a theme.
    - Choosing an unused default theme or creating a new one each takes a slot. When SLOTS is 0, choose the closest theme in THEMES.
    - A theme name is a short Korean noun phrase.

    Task types (NEEDS_TYPE): choose from TASK_TYPES the kind of activity the task mostly is.

    Answer every task exactly once, by its id. Give theme only to NEEDS_THEME tasks and task_type only to NEEDS_TYPE tasks.
    Always answer by calling assign_themes. Do not write prose.
    """

    public static func user(targets: [Target], themes: [ThemeLine]) -> String {
        var lines = ["THEMES:"]
        if themes.isEmpty { lines.append("(none)") }
        for theme in themes {
            let tasks = theme.tasks.prefix(5).map { OntologyPrompt.clip($0, 60) }.joined(separator: "; ")
            lines.append(tasks.isEmpty ? "- \(theme.name)" : "- \(theme.name) | tasks: \(tasks)")
        }
        let used = Set(themes.map { ThemeCatalog.matchKey($0.name) })
        let unused = ThemeCatalog.defaults.filter { !used.contains(ThemeCatalog.matchKey($0)) }
        lines.append("DEFAULT_THEMES (not used yet): " + (unused.isEmpty ? "(none)" : unused.joined(separator: ", ")))
        lines.append("SLOTS: \(max(0, ThemeCatalog.limit - themes.count))")
        if targets.contains(where: \.needsType) { lines.append("TASK_TYPES: " + TBox.leafTaskTypes.joined(separator: ", ")) }
        lines.append("TASKS:")
        for target in targets {
            var needs: [String] = []
            if target.needsTheme { needs.append("NEEDS_THEME") }
            if target.needsType { needs.append("NEEDS_TYPE") }
            var line = "- id=\(target.key) | \(needs.joined(separator: ", ")) | \(OntologyPrompt.clip(target.title, 90))"
            if let goal = target.goal, !goal.isEmpty { line += " | goal: \(OntologyPrompt.clip(goal, 140))" }
            if let type = target.taskType { line += " | type: \(type)" }
            if !target.recent.isEmpty { line += " | recent: " + target.recent.prefix(3).map { OntologyPrompt.clip($0, 100) }.joined(separator: "; ") }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// 답 해석. 중첩 JSON 문자열을 풀고, 이름은 공백 정리, 종류는 고를 수 있는 이름으로 맞춘다 (못 맞추면 nil)
    public static func decode(_ data: Data) -> [String: Answer] {
        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let root = AssignmentPatch.unwrapStrings(parsed) as? [String: Any] else { return [:] }
        var answers: [String: Answer] = [:]
        for entry in root["tasks"] as? [[String: Any]] ?? [] {
            guard let id = (entry["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { continue }
            let theme = (entry["theme"] as? String).map(ThemeCatalog.normalize).flatMap { $0.isEmpty ? nil : $0 }
            let type = (entry["task_type"] as? String).flatMap(TBox.leafType)
            answers[id] = Answer(theme: theme, taskType: type)
        }
        return answers
    }

    /// 대상 업무와 분야 목록. retypeAll 이면 판과 상관없이 모든 활성 업무의 종류를 다시 묻는다
    public static func load(_ tx: GraphTx, retypeAll: Bool = false) throws -> (targets: [Target], themes: [ThemeLine]) {
        var targets: [Target] = [], members: [Int64: [String]] = [:]
        for digest in try tx.openTasks(limit: 10_000) {
            guard let node = try tx.node(label: NodeLabel.task, key: digest.id) else { continue }
            let theme = try ThemeGraph.theme(ofTask: node.id, tx)
            if let theme { members[theme.id, default: []].append(digest.title) }
            let version = Int(node.props["type_version"]?.doubleValue ?? 0)
            let needsType = retypeAll || version < TBox.version
            guard theme == nil || needsType else { continue }
            targets.append(Target(key: digest.id, title: digest.title, goal: digest.goal, taskType: digest.taskType,
                                  recent: digest.recentSummaries, needsTheme: theme == nil, needsType: needsType))
        }
        let themes = try tx.nodes(label: NodeLabel.theme).map { ThemeLine(name: $0.title, tasks: members[$0.id] ?? []) }
        return (targets, themes)
    }

    /// LLM 호출 한 번 (기록하지 않음)
    public static func judge(targets: [Target], themes: [ThemeLine], llm: any LLMClient) async throws -> [String: Answer] {
        let result = try await llm.callFunction(system: system, user: user(targets: targets, themes: themes), tool: tool)
        return decode(result.arguments)
    }

    /// 답을 반영한다. 받아들이지 않는 답(대상에 없는 id, 빈·긴 이름, 자리 초과, 모르는 종류, 분야가 이미 있는 업무의 분야)은 건너뛴다
    public static func apply(_ answers: [String: Answer], targets: [Target], _ tx: GraphTx, now: Double) throws -> Outcome {
        var outcome = Outcome()
        for target in targets {
            guard let node = try tx.node(label: NodeLabel.task, key: target.key) else { continue }
            let answer = answers[target.key]
            if target.needsTheme {
                if let name = answer?.theme, let attached = try ThemeGraph.attach(taskId: node.id, to: name, tx, now: now) {
                    outcome.themed += 1
                    if attached.created { outcome.created.append(attached.node.title) }
                } else {
                    outcome.skipped += 1
                }
            }
            if target.needsType {
                if let type = answer?.taskType, let typeNode = try tx.node(label: NodeLabel.taskType, key: type) {
                    for edge in try tx.edges(from: node.id, type: EdgeType.instanceOf) { try tx.deleteEdge(id: edge.id) }
                    try tx.upsertEdge(src: node.id, dst: typeNode.id, type: EdgeType.instanceOf, props: [:], addWeight: 0, at: now, countHit: false)
                    try tx.setProps(nodeId: node.id, ["type_version": .number(Double(TBox.version))], at: now)
                    outcome.retyped += 1
                } else {
                    outcome.skipped += 1
                }
            }
        }
        try ThemeGraph.pruneEmpty(tx)
        return outcome
    }

    /// 한 번 돈다. 대상이 없으면 호출하지 않고 nil
    public static func run(db: WGDatabase, llm: any LLMClient, now: Double, retypeAll: Bool = false) async throws -> Outcome? {
        let loaded = try await db.writer.write { conn -> (targets: [Target], themes: [ThemeLine]) in
            let tx = GraphTx(conn)
            // 다른 경로로 업무가 지워져 빈 분야가 남았을 수 있다
            try ThemeGraph.pruneEmpty(tx)
            return try load(tx, retypeAll: retypeAll)
        }
        guard !loaded.targets.isEmpty else { return nil }
        let answers = try await judge(targets: loaded.targets, themes: loaded.themes, llm: llm)
        return try await db.writer.write { conn in try apply(answers, targets: loaded.targets, GraphTx(conn), now: now) }
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `swift test --filter "ThemeStepTests|ThemeOntologyTests" 2>&1 | grep -E "error:|Executed" | tail -3`
Expected: 0 failures

- [ ] **Step 5: 전체 테스트**

Run: `swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -2`
Expected: 0 failures

---

### Task 3: 정리 뒤·앱 시작에 연결, 합치기·업무 외 처리 뒤 분야 정리

**Files:**
- Modify: `Sources/WorkGraphCore/Ontology/OntologyBatcher.swift` (BatchConfig, 합치기 뒤 호출, `assignThemes`)
- Modify: `Sources/WorkGraphCore/Ontology/TaskMerger.swift` (`merge`, `retire`)
- Modify: `Sources/WorkGraphApp/AppState.swift` (배처를 만든 직후)
- Modify: `Tests/WorkGraphCoreTests/OntologyBatcherTests.swift` (`BatchConfig.singleCall`)
- Modify: `Tests/WorkGraphCoreTests/StagedPipelineTests.swift` (`StagedBatcherTests.batcher`)
- Test: `Tests/WorkGraphCoreTests/ThemeTests.swift` (`ThemeHookTests` 추가)

**Interfaces:**
- Consumes: `ThemeStep.run`, `ThemeStep.tool`, `ThemeStep.Outcome` (Task 2), `ThemeGraph` (Task 1), `TaskMerger.Group(keep:merge:title:goal:)`, `TaskMerger.merge(_:conn:now:)`, `TaskMerger.retire(_:conn:now:)`, `GraphRebuilder(db:store:home:fileExists:).rebuildFromAssignments(now:)`
- Produces:
  - `BatchConfig.themes: Bool = true`
  - `OntologyBatcher.assignThemes(now: Double? = nil) async -> ThemeStep.Outcome?` (`@discardableResult`, 던지지 않음)

- [ ] **Step 1: 정리 테스트에서 테마 단계를 끈다** (이 테스트들은 호출 수를 세고, 가짜 LLM 이 분야 도구를 모른다)

`OntologyBatcherTests.swift` 의 `extension BatchConfig` 를 바꾼다:

```swift
extension BatchConfig {
    /// 한 번 호출 형식(assign_rows)으로 답하는 가짜 LLM 을 쓰는 테스트용. 테마 단계는 따로 테스트하므로 끈다
    static var singleCall: BatchConfig {
        var config = BatchConfig()
        config.pipeline = .single
        config.themes = false
        return config
    }
}
```

`StagedPipelineTests.swift` 의 `StagedBatcherTests.batcher` 에서 `config.pipeline = .staged` 다음에 `config.themes = false` 를 더한다.

- [ ] **Step 2: 실패하는 테스트를 쓴다** — `ThemeTests.swift` 끝에 더한다:

```swift
/// 정리 호출은 정해진 답을, 테마 단계 호출은 받은 업무마다 같은 분야로 답하는 가짜 LLM
final class ThemeAwareLLM: LLMClient, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Result<String, LLMError>]
    private let theme: Result<String, LLMError>
    private(set) var themeCalls = 0
    let modelName = "stub-model"

    init(_ replies: [Result<String, LLMError>], theme: Result<String, LLMError>) { self.replies = replies; self.theme = theme }

    func callFunction(system: String, user: String, tool: ToolSpec) async throws -> LLMResult {
        if tool.name == ThemeStep.tool.name {
            lock.withLock { themeCalls += 1 }
            let name = try theme.get()
            let ids = user.split(separator: "\n").compactMap { line -> String? in
                guard line.hasPrefix("- id=") else { return nil }
                return line.dropFirst(5).split(separator: " ").first.map(String.init)
            }
            var entries: [String] = []
            for id in ids { entries.append("{\"id\":\"\(id)\",\"theme\":\"\(name)\"}") }
            let json = "{\"tasks\":[\(entries.joined(separator: ","))]}"
            return LLMResult(arguments: Data(json.utf8), model: modelName, promptTokens: 10, completionTokens: 5, raw: json)
        }
        let next: Result<String, LLMError> = lock.withLock { replies.isEmpty ? .failure(.transport("no stub")) : replies.removeFirst() }
        let json = try next.get()
        return LLMResult(arguments: Data(json.utf8), model: modelName, promptTokens: 100, completionTokens: 20, raw: json)
    }
}

final class ThemeHookTests: XCTestCase {
    private let patch = """
    {"tasks":[{"ref":"A","match":"new","title":"대시보드 카드 UI 구현","task_type":"코드작성"}],"rows":[{"rows":"1-2","task":"A"}],
     "work":[{"task":"A","summary":"카드 구현","topics":["React"]}]}
    """

    private func seedRows(_ db: WGDatabase) throws {
        let store = EventStore(db)
        _ = try store.insert(Observation(ts: 100, trigger: "app_activate", appBundle: "com.todesktop.230313mzl4w4u92", appName: "Cursor", windowTitle: "TaskCard.tsx — dashboard"))
        _ = try store.insert(Observation(ts: 160, trigger: "app_activate", appBundle: "com.google.Chrome", appName: "Google Chrome",
                                         windowTitle: "Card - shadcn/ui - Google Chrome", url: "https://ui.shadcn.com/docs/components/card"))
    }

    private func batcher(_ db: WGDatabase, _ llm: ThemeAwareLLM) -> OntologyBatcher {
        var config = BatchConfig.singleCall
        config.themes = true
        return OntologyBatcher(db: db, llm: llm, config: config, home: "/Users/me", fileExists: { _ in false }, clock: { 450 })
    }

    func testABatchThatCreatesATaskGivesItATheme() async throws {
        let db = try WGDatabase.inMemory()
        try seedRows(db)
        let llm = ThemeAwareLLM([.success(patch)], theme: .success("프로젝트"))
        guard case .ok = await batcher(db, llm).runIfDue(force: true) else { return XCTFail("배치 성공해야 함") }
        XCTAssertEqual(llm.themeCalls, 1)
        let themes = try await db.writer.read { try GraphTx($0).nodes(label: NodeLabel.theme).map(\.title) }
        XCTAssertEqual(themes, ["프로젝트"])
    }

    func testAThemeFailureLeavesTheBatchApplied() async throws {
        let db = try WGDatabase.inMemory()
        try seedRows(db)
        let llm = ThemeAwareLLM([.success(patch)], theme: .failure(.http(429, "rate")))
        guard case .ok = await batcher(db, llm).runIfDue(force: true) else { return XCTFail("테마 단계가 실패해도 정리는 성공") }
        let counts = try await db.writer.read { conn -> [Int] in
            let tx = GraphTx(conn)
            let tasks = try tx.nodes(label: NodeLabel.task).count
            let themes = try tx.nodes(label: NodeLabel.theme).count
            return [tasks, themes]
        }
        XCTAssertEqual(counts, [1, 0])
    }

    func testAssignThemesNeverThrowsWhenTheModelIsUnreachable() async throws {
        let db = try WGDatabase.inMemory()
        try await db.writer.write { conn in
            let tx = GraphTx(conn)
            try TBox.seed(tx, at: 0)
            try tx.upsertNode(label: NodeLabel.task, key: "t_a", subtype: nil, title: "자료구조 강의 수강",
                              props: ["status": "active", "last_active": .number(100)], at: 100)
        }
        let llm = ThemeAwareLLM([], theme: .failure(.transport("offline")))
        let outcome = await batcher(db, llm).assignThemes(now: 500)
        XCTAssertNil(outcome)
        XCTAssertEqual(llm.themeCalls, 1)
    }

    func testMergingGivesTheSurvivorTheVictimsThemeWhenItHasNone() throws {
        let db = try WGDatabase.inMemory()
        try db.writer.write { conn in
            let tx = GraphTx(conn)
            let keep = try tx.upsertNode(label: NodeLabel.task, key: "t_keep", subtype: nil, title: "남는 업무", props: ["status": "active"], at: 0)
            let victim = try tx.upsertNode(label: NodeLabel.task, key: "t_victim", subtype: nil, title: "사라지는 업무", props: ["status": "active"], at: 0)
            try ThemeGraph.attach(taskId: victim, to: "학업", tx, now: 0)
            _ = try TaskMerger.merge(TaskMerger.Group(keep: "t_keep", merge: ["t_victim"]), conn: conn, now: 10)
            XCTAssertEqual(try ThemeGraph.theme(ofTask: keep, tx)?.title, "학업")
        }
    }

    func testMergingKeepsTheSurvivorsOwnThemeAndDropsTheEmptyOne() throws {
        let db = try WGDatabase.inMemory()
        try db.writer.write { conn in
            let tx = GraphTx(conn)
            let keep = try tx.upsertNode(label: NodeLabel.task, key: "t_keep", subtype: nil, title: "남는 업무", props: ["status": "active"], at: 0)
            let victim = try tx.upsertNode(label: NodeLabel.task, key: "t_victim", subtype: nil, title: "사라지는 업무", props: ["status": "active"], at: 0)
            try ThemeGraph.attach(taskId: keep, to: "프로젝트", tx, now: 0)
            try ThemeGraph.attach(taskId: victim, to: "학업", tx, now: 0)
            _ = try TaskMerger.merge(TaskMerger.Group(keep: "t_keep", merge: ["t_victim"]), conn: conn, now: 10)
            XCTAssertEqual(try ThemeGraph.theme(ofTask: keep, tx)?.title, "프로젝트")
            XCTAssertEqual(try tx.nodes(label: NodeLabel.theme).map(\.title), ["프로젝트"], "업무가 없는 분야는 지운다")
        }
    }

    func testRetiringATaskDropsItsNowEmptyTheme() throws {
        let db = try WGDatabase.inMemory()
        try db.writer.write { conn in
            let tx = GraphTx(conn)
            let task = try tx.upsertNode(label: NodeLabel.task, key: "t_game", subtype: nil, title: "게임 리그", props: ["status": "active"], at: 0)
            try ThemeGraph.attach(taskId: task, to: "자기계발", tx, now: 0)
            XCTAssertTrue(try TaskMerger.retire("t_game", conn: conn, now: 10))
            XCTAssertTrue(try tx.nodes(label: NodeLabel.theme).isEmpty)
        }
    }

    func testRebuildKeepsTaskThemes() throws {
        let db = try WGDatabase.inMemory()
        try db.writer.write { conn in
            let tx = GraphTx(conn)
            let task = try tx.upsertNode(label: NodeLabel.task, key: "t_a", subtype: nil, title: "A", props: ["status": "active"], at: 0)
            try ThemeGraph.attach(taskId: task, to: "학업", tx, now: 0)
        }
        _ = try GraphRebuilder(db: db, store: EventStore(db), home: "/Users/me", fileExists: { _ in false }).rebuildFromAssignments(now: 100)
        let theme = try db.writer.read { conn -> String? in
            let tx = GraphTx(conn)
            guard let task = try tx.node(label: NodeLabel.task, key: "t_a") else { return nil }
            return try ThemeGraph.theme(ofTask: task.id, tx)?.title
        }
        XCTAssertEqual(theme, "학업")
    }
}
```

- [ ] **Step 3: 실패를 확인한다**

Run: `swift test --filter ThemeHookTests 2>&1 | grep -E "error:|Executed" | head -6`
Expected: 컴파일 실패 — `value of type 'BatchConfig' has no member 'themes'` / `value of type 'OntologyBatcher' has no member 'assignThemes'`

- [ ] **Step 4: 구현한다**

`OntologyBatcher.swift` 의 `BatchConfig` 에서 `pipeline` 다음에:

```swift
    /// 정리에서 새 업무가 생기면 업무 합치기 뒤에 테마 단계(분야·종류 붙이기)를 돈다
    public var themes: Bool = true
```

같은 파일 `run` 의 합치기 블록을 바꾼다:

```swift
        if stats.tasksCreated > 0 {
            var merged = stats
            if let outcome = try? await TaskMerger.run(db: db, llm: llm, since: now - 7 * 86_400, now: now) {
                merged.tasksMerged = outcome.merged
                if outcome.retired > 0 { AppLog.write("목표가 아닌 업무 \(outcome.retired)개를 업무 외로 돌림") }
            }
            if config.themes { await assignThemes(now: now) }
            return .ok(merged)
        }
```

같은 파일 `OntologyBatcher` 안 (`judge` 함수 앞)에:

```swift
    /// 테마 단계: 분야가 없거나 종류가 옛 판인 업무에 분야·종류를 붙인다. 실패해도 정리에는 영향이 없다 (로그만 남긴다)
    @discardableResult
    public func assignThemes(now: Double? = nil) async -> ThemeStep.Outcome? {
        do {
            guard let outcome = try await ThemeStep.run(db: db, llm: llm, now: now ?? clock()) else { return nil }
            var message = "분야: 업무 \(outcome.themed)개에 붙임, 종류 \(outcome.retyped)개 다시 붙임"
            if !outcome.created.isEmpty { message += ", 새 분야 \(outcome.created.joined(separator: ", "))" }
            if outcome.skipped > 0 { message += ", 다음에 다시 \(outcome.skipped)개" }
            AppLog.write(message)
            return outcome
        } catch {
            AppLog.write("분야 붙이기 실패: \((error as? LLMError)?.description ?? "\(error)")")
            return nil
        }
    }
```

`TaskMerger.swift` 의 `merge` 에서 `try ProjectStore.mergeTask(victim.id, into: keep.id, conn)` 바로 앞에:

```swift
            // 분야: 남는 업무에 없으면 사라지는 업무의 것을 받는다
            if try ThemeGraph.theme(ofTask: keep.id, tx) == nil, let theme = try ThemeGraph.theme(ofTask: victim.id, tx) {
                try ThemeGraph.attach(taskId: keep.id, to: theme.title, tx, now: now)
            }
```

같은 함수 끝의 `if merged > 0 { try tx.rebindProjects(at: now) }` 를 바꾼다:

```swift
        if merged > 0 {
            try tx.rebindProjects(at: now)
            try ThemeGraph.pruneEmpty(tx)
        }
```

`retire` 에서 `_ = try tx.pruneOrphanResources()` 바로 앞에:

```swift
        try ThemeGraph.pruneEmpty(tx)
```

`AppState.swift` 에서 `Task { await batcher.setScreenCards(cardsOn) }` 다음 줄에:

```swift
            // 앱을 시작할 때 분야가 없거나 종류가 옛 판인 업무를 정리한다 (처음 한 번은 기존 업무 전부)
            Task { await batcher.assignThemes() }
```

- [ ] **Step 5: 통과를 확인한다**

Run: `swift test --filter "ThemeHookTests|OntologyBatcherTests|StagedBatcherTests|TaskMerger" 2>&1 | grep -E "error:|Executed" | tail -3`
Expected: 0 failures

- [ ] **Step 6: 전체 빌드와 테스트**

Run: `swift build 2>&1 | grep -E "error|complete" | tail -2 && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -2`
Expected: `Build complete!`, 0 failures

---

### Task 4: 그래프 뷰·RDF — 분야가 보이고, 시간 범위에서도 사라지지 않게

**Files:**
- Modify: `Sources/WorkGraphCore/Storage/GraphTx.swift` (`subgraph(since:includeTBox:)`)
- Modify: `Sources/WorkGraphApp/Resources/graph/graph.js` (GROUPS, LABEL_NAMES, 연결 이름)
- Test: `Tests/WorkGraphCoreTests/ThemeTests.swift` (`ThemeViewTests` 추가)

**Interfaces:**
- Consumes: `ThemeGraph.attach` (Task 1), `NodeLabel.theme`, `ClassSchema` 의 분야 (Task 1), `RDFExporter.export(_:)`
- Produces: `GraphTx.subgraph(since:includeTBox:)` 가 보이는 업무의 분야와 그 연결을 시간과 상관없이 포함

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `ThemeTests.swift` 끝에:

```swift
final class ThemeViewTests: XCTestCase {
    func testATimeWindowStillShowsTheThemesOfVisibleTasks() throws {
        let db = try WGDatabase.inMemory()
        let graph = try db.writer.write { conn -> Subgraph in
            let tx = GraphTx(conn)
            let task = try tx.upsertNode(label: NodeLabel.task, key: "t_a", subtype: nil, title: "A", props: [:], at: 1_000)
            try ThemeGraph.attach(taskId: task, to: "학업", tx, now: 10)
            try conn.execute(sql: "UPDATE nodes SET updated_at = 10 WHERE label = 'Theme'")
            return try tx.subgraph(since: 500, includeTBox: false)
        }
        XCTAssertEqual(Set(graph.nodes.map(\.label)), [NodeLabel.task, NodeLabel.theme])
        XCTAssertEqual(graph.edges.map(\.type), [EdgeType.partOf])
    }

    func testRDFExportDeclaresThemeAndLinksTasksToIt() throws {
        let db = try WGDatabase.inMemory()
        let graph = try db.writer.write { conn -> Subgraph in
            let tx = GraphTx(conn)
            let task = try tx.upsertNode(label: NodeLabel.task, key: "t_a", subtype: nil, title: "A", props: [:], at: 0)
            try ThemeGraph.attach(taskId: task, to: "학업", tx, now: 0)
            return try tx.subgraph(since: nil, includeTBox: false)
        }
        let turtle = RDFExporter.export(graph)
        XCTAssertTrue(turtle.contains("wg:Theme a rdfs:Class ;\n    rdfs:subClassOf skos:Concept"))
        XCTAssertTrue(turtle.contains("a wg:Theme, skos:Concept"))
        XCTAssertTrue(turtle.contains("dcterms:isPartOf"))
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `swift test --filter ThemeViewTests 2>&1 | grep -E "error:|Executed" | head -4`
Expected: `testATimeWindowStillShowsTheThemesOfVisibleTasks` 실패 (분야 노드·연결 없음). RDF 테스트는 Task 1 의 ClassSchema 덕에 통과할 수 있다 — 통과하면 그대로 둔다 (Task 1 의 산출물을 지키는 회귀 테스트).

- [ ] **Step 3: 구현한다** — `GraphTx.swift` 의 `subgraph(since:includeTBox:)` 를 바꾼다:

```swift
    /// since 이후 갱신된 노드 + 그 시각 이후 엣지의 양 끝점. 보이는 업무의 분야는 언제 이어졌든 함께 넣는다
    public func subgraph(since: Double?, includeTBox: Bool) throws -> Subgraph {
        var ids: [Int64]
        if let since {
            ids = try Int64.fetchAll(db, sql: """
                SELECT id FROM nodes WHERE updated_at >= ?
                UNION SELECT src FROM edges WHERE last_at >= ?
                UNION SELECT dst FROM edges WHERE last_at >= ?
                """, arguments: [since, since, since])
            if !ids.isEmpty {
                let list = ids.map(String.init).joined(separator: ",")   // 정수만 들어가므로 SQL 주입 위험 없음
                ids += try Int64.fetchAll(db, sql: """
                    SELECT e.dst FROM edges e JOIN nodes t ON t.id = e.dst AND t.label = 'Theme'
                    WHERE e.type = 'PART_OF' AND e.src IN (\(list))
                    """)
            }
        } else {
            ids = try Int64.fetchAll(db, sql: "SELECT id FROM nodes")
        }
        var result = try subgraph(ids: Array(Set(ids)), includeTBox: includeTBox)
        if let since {
            let themes = Set(result.nodes.filter { $0.label == NodeLabel.theme }.map(\.id))
            result.edges.removeAll { $0.lastAt < since && !($0.type == EdgeType.partOf && themes.contains($0.dst)) }
        }
        return result
    }
```

`graph.js` 의 `GROUPS` 맨 앞에 분야를 더한다:

```js
    Theme:       { name: '분야',        color: '#7c4dff' },
```

`LABEL_NAMES` 에 `Theme: '분야', ` 를 더한다 (`Task: '업무',` 앞).

`EDGE_NAMES` 정의 다음에 함수를 더한다:

```js
  // 업무 → 분야 의 PART_OF 는 세션 → 업무 와 이름이 다르다
  function edgeTitle(link, outgoing) {
    if (link.type === 'PART_OF' && state.byId.get(link.target)?.label === 'Theme') return outgoing ? '분야' : '이 분야의 업무';
    return (EDGE_NAMES[link.type] || [link.type, link.type])[outgoing ? 0 : 1];
  }
```

상세 패널의 연결 목록에서 `const title = (EDGE_NAMES[l.type] || [l.type, l.type])[outgoing ? 0 : 1];` 를 `const title = edgeTitle(l, outgoing);` 로 바꾼다.

주의: `edgeTitle` 은 `state` 를 쓰므로 `state` 선언 뒤에서 호출된다 (함수 선언은 끌어올려지므로 위치는 `EDGE_NAMES` 다음이어도 된다).

- [ ] **Step 4: 통과를 확인한다**

Run: `swift test --filter ThemeViewTests 2>&1 | grep -E "error:|Executed" | tail -2 && node --check Sources/WorkGraphApp/Resources/graph/graph.js && echo js-ok`
Expected: 0 failures, `js-ok`

- [ ] **Step 5: 전체 테스트**

Run: `swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -2`
Expected: 0 failures

---

### Task 5: wgctl — `themes`, `assign-themes`, 데모 정리에서 테마 단계 끄기

**Files:**
- Modify: `Sources/wgctl/main.swift` (usage, `batch`, 새 명령 두 개)

**Interfaces:**
- Consumes: `ThemeStep.load/judge/run`, `ThemeGraph.theme(ofTask:_:)`, `InstanceLock`, `makeClient()`, `flag(_:)`, `fail(_:)`
- Produces: 명령 `themes`, `assign-themes [--retype] [--dry-run]`

- [ ] **Step 1: 데모 정리에서 테마 단계를 끈다** — `case "batch":` 의 데모 줄을 바꾼다:

```swift
        // 데모 LLM 은 한 번 호출 형식으로만 답하고 분야 도구는 모른다
        if demo { batchConfig.pipeline = .single; batchConfig.themes = false }
```

- [ ] **Step 2: 새 명령** — `case "pipeline-graph":` 앞에:

```swift
    case "themes":
        let rows = try db.writer.read { conn -> [(theme: String, tasks: [String])] in
            let tx = GraphTx(conn)
            var byTheme: [String: [String]] = [:], none: [String] = []
            for task in try tx.nodes(label: NodeLabel.task) {
                if let theme = try ThemeGraph.theme(ofTask: task.id, tx) { byTheme[theme.title, default: []].append(task.title) } else { none.append(task.title) }
            }
            var rows = byTheme.sorted { $0.key < $1.key }.map { (theme: $0.key, tasks: $0.value) }
            if !none.isEmpty { rows.append((theme: "(분야 없음)", tasks: none)) }
            return rows
        }
        if rows.isEmpty { print("업무가 없습니다") }
        for row in rows {
            print("\(row.theme) (\(row.tasks.count))")
            for title in row.tasks { print("  - \(title)") }
        }

    case "assign-themes":
        let retype = flag("--retype"), dryRun = flag("--dry-run")
        let client = makeClient().client
        if dryRun {
            let loaded = try db.writer.read { try ThemeStep.load(GraphTx($0), retypeAll: retype) }
            guard !loaded.targets.isEmpty else { print("분야·종류를 붙일 업무가 없습니다"); break }
            print("업무 \(loaded.targets.count)개를 판정만 합니다 (기록하지 않음)")
            let answers = try await ThemeStep.judge(targets: loaded.targets, themes: loaded.themes, llm: client)
            for target in loaded.targets {
                let answer = answers[target.key]
                let theme = target.needsTheme ? (answer?.theme ?? "(답 없음)") : "(그대로)"
                let type = target.needsType ? (answer?.taskType ?? "(답 없음)") : "(그대로)"
                print("  \(target.title) → 분야 \(theme), 종류 \(type)")
            }
            break
        }
        let instance = InstanceLock(databasePath: dbPath)
        guard instance.acquire() else { fail("이 DB 를 쓰는 Sillog 앱이 실행 중입니다. 앱이 직접 분야를 붙이므로 앱을 종료한 뒤 다시 실행하세요.") }
        defer { instance.release() }
        guard let outcome = try await ThemeStep.run(db: db, llm: client, now: Date().timeIntervalSince1970, retypeAll: retype) else {
            print("분야·종류를 붙일 업무가 없습니다"); break
        }
        var line = "분야 \(outcome.themed)개, 종류 \(outcome.retyped)개"
        if !outcome.created.isEmpty { line += ", 새 분야 \(outcome.created.joined(separator: ", "))" }
        if outcome.skipped > 0 { line += ", 건너뜀 \(outcome.skipped)개" }
        print(line)

```

usage 의 `pipeline-graph` 줄 다음에:

```
  themes                                분야별 업무 목록
  assign-themes [--retype] [--dry-run]  분야가 없거나 종류가 옛 판인 업무에 분야·종류를 붙인다 (앱을 끄고 실행.
                                        --retype: 모든 업무의 종류를 다시, --dry-run: 판정만 보고 기록 안 함)
```

- [ ] **Step 3: 빌드와 데모 DB 확인** (`$SCRATCH` 는 세션 스크래치 폴더. 실제 DB 는 건드리지 않는다)

Run: `swift build --product wgctl 2>&1 | grep -E "error|complete" | tail -1`
Expected: `Build of product 'wgctl' complete!`

Run:
```bash
D="$SCRATCH/theme-demo.sqlite"; rm -f "$D"*
.build/debug/wgctl --db "$D" seed-demo && .build/debug/wgctl --db "$D" batch --demo-llm --all --force | tail -2
.build/debug/wgctl --db "$D" themes
.build/debug/wgctl --db "$D" assign-themes --dry-run --model gpt-6-luna --reasoning medium
.build/debug/wgctl --db "$D" assign-themes --model gpt-6-luna --reasoning medium
.build/debug/wgctl --db "$D" themes
```
Expected: 처음 `themes` 는 데모 업무가 모두 `(분야 없음)`, dry-run 은 업무마다 `→ 분야 …, 종류 …` 를 출력, 실제 실행은 `분야 N개, 종류 N개`, 마지막 `themes` 는 분야별로 묶인 목록 (데모 업무는 모두 판이 2라 종류는 `(그대로)`·0개가 정상)

- [ ] **Step 4: 전체 테스트**

Run: `swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -2`
Expected: 0 failures

---

### Task 6: 정답 비교 (`theme-eval`)와 측정

**설계서와의 대응:** 설계서의 "빈 그래프에 옮겨 처음부터"는, 분야 목록을 비운 채(`themes: []`) 판정만 받는 것으로 같은 조건을 만든다. 반영하지 않으므로 실제 DB 에 기록이 없다.

**전제:** 실행 전에 사용자가 확정한 정답 파일 `~/Library/Application Support/WorkGraph/eval/themes-gold.json` 이 있다. 형식:

```json
{"created": 1791200000, "tasks": [{"key": "t_xxxxxxxx", "title": "현대오토에버 신입 채용 과제테스트 지원", "theme": "취업 준비", "type": "신청·지원"}]}
```

**Files:**
- Modify: `Sources/wgctl/main.swift` (도우미 함수, `theme-eval`, usage)
- Modify: `docs/superpowers/specs/2026-10-05-task-themes-design.md` (끝에 "측정 결과")

**Interfaces:**
- Consumes: `ThemeStep.Target/judge`, `ThemeCatalog.matchKey/canonical/defaults`, `TBox.leafType`, `GraphTx.openTasks`, `evalDirectory`
- Produces: 명령 `theme-eval [--gold FILE] [--runs N]`

- [ ] **Step 1: 명령을 더한다** — `main.swift` 위쪽 도우미들(`loadGoldRows` 다음)에:

```swift
/// 분야 이름 비교용 키 (기본 분야 표기로 맞춘 뒤 공백·대소문자 무시)
func themeKey(_ name: String?) -> String { ThemeCatalog.matchKey(ThemeCatalog.canonical(name ?? "")) }
```

`case "pipeline-graph":` 앞에:

```swift
    case "theme-eval":
        let path = option("--gold") ?? evalDirectory + "/themes-gold.json"
        let runs = max(1, option("--runs").flatMap(Int.init) ?? 2)
        guard let raw = FileManager.default.contents(atPath: path),
              let file = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let gold = file["tasks"] as? [[String: String]] else { fail("정답 파일을 읽을 수 없음: \(path)") }
        let digests = try db.writer.read { try GraphTx($0).openTasks(limit: 10_000) }
        let byKey = Dictionary(digests.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let targets = gold.compactMap { item -> ThemeStep.Target? in
            guard let key = item["key"], let digest = byKey[key] else { return nil }
            return ThemeStep.Target(key: key, title: digest.title, goal: digest.goal, taskType: digest.taskType,
                                    recent: digest.recentSummaries, needsTheme: true, needsType: true)
        }
        guard targets.count == gold.count else { fail("정답의 업무 \(gold.count - targets.count)개를 DB 에서 찾지 못함") }
        let client = makeClient().client
        let defaultKeys = Set(ThemeCatalog.defaults.map(ThemeCatalog.matchKey))
        print("업무 \(targets.count)개 — 빈 분야 목록에서 \(runs)번 판정 (기록하지 않음)")
        var results: [[String: ThemeStep.Answer]] = []
        for run in 1...runs {
            let answers = try await ThemeStep.judge(targets: targets, themes: [], llm: client)
            results.append(answers)
            var themeOK = 0, typeOK = 0, misses: [String] = []
            for item in gold {
                let answer = answers[item["key"] ?? ""]
                let themeHit = themeKey(answer?.theme) == themeKey(item["theme"])
                let typeHit = answer?.taskType != nil && answer?.taskType == TBox.leafType(item["type"] ?? "")
                if themeHit { themeOK += 1 }
                if typeHit { typeOK += 1 }
                if !themeHit || !typeHit {
                    misses.append("    \(item["title"] ?? "") — 정답 \(item["theme"] ?? "")/\(item["type"] ?? ""), 답 \(answer?.theme ?? "-")/\(answer?.taskType ?? "-")")
                }
            }
            let created = Set(answers.values.compactMap(\.theme).map { ThemeCatalog.canonical($0) }.filter { !defaultKeys.contains(ThemeCatalog.matchKey($0)) })
            print("  \(run)회: 분야 \(themeOK)/\(gold.count), 종류 \(typeOK)/\(gold.count), 새 분야 \(created.count)" + (created.isEmpty ? "" : " (\(created.sorted().joined(separator: ", ")))"))
            for line in misses { print(line) }
        }
        if results.count >= 2 {
            let flipped = gold.filter { item in
                let key = item["key"] ?? ""
                return themeKey(results[0][key]?.theme) != themeKey(results[1][key]?.theme) || results[0][key]?.taskType != results[1][key]?.taskType
            }.count
            print("  흔들림: 두 번의 결과가 다른 업무 \(flipped)/\(gold.count)")
        }

```

usage 의 `assign-themes` 설명 다음에:

```
  theme-eval [--gold FILE] [--runs N]   정답 세트 업무를 빈 분야 목록에서 판정만 받아(기록 안 함) 분야·종류 정확도, 새 분야 수, 흔들림을 낸다
```

- [ ] **Step 2: 빌드**

Run: `swift build --product wgctl 2>&1 | grep -E "error|complete" | tail -1`
Expected: `Build of product 'wgctl' complete!`

- [ ] **Step 3: 측정한다** (실제 DB 는 읽기만 한다)

Run: `.build/debug/wgctl theme-eval --runs 2 --model gpt-6-luna --reasoning medium`
Expected: `1회:`·`2회:` 줄과 `흔들림:` 줄. 성공 기준 — 분야 12/13 이상(두 번 모두), 흔들림 1 이하, 새 분야 2 이하, 종류 11/13 이상

- [ ] **Step 4: 결과를 설계서에 남긴다** — 설계서 끝에:

```markdown
## 측정 결과 (2026-10-05, 업무 13개, gpt-6-luna medium)

| | 분야 (1회 / 2회) | 종류 (1회 / 2회) | 새 분야 | 흔들림 |
|---|---|---|---|---|
| 테마 단계 | (Step 3 값) | (값) | (값) | (값) |

틀린 업무: (Step 3 의 목록 그대로)

결정: (기준 네 가지를 모두 넘으면 "기준 통과", 아니면 "기준 미달 — 어느 기준이 왜 모자랐는지". 프롬프트에 예시를 넣어 맞추지 않는다)
```

---

### Task 7: 앱 빌드

**Files:** 없음 (빌드만)

- [ ] **Step 1: 전체 테스트**

Run: `swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -2`
Expected: 0 failures

- [ ] **Step 2: 앱을 빌드해 설치한다** (실행 중인 앱은 건드리지 않는다)

Run: `scripts/make-app.sh 2>&1 | grep -E "error|서명|설치|완성" | tail -4`
Expected: `서명: Capstone Prototype Dev`, `설치: …/Applications/Sillog.app`

재시작은 사용자가 정한다. 재시작하면 첫 테마 단계가 기존 업무 전부에 분야와 새 종류를 붙인다 (LLM 호출 한 번).

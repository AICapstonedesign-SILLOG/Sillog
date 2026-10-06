# 3단계 판정 파이프라인 (LangGraph) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 업무 판정을 ① 업무 여부 → ② 업무 대입 → ③ 클래스 부여 세 번의 단순한 LLM 호출로 나누고, LangGraph-Swift 로 잇고, 정답 세트로 지금의 한 번 호출과 비교한다.

**Architecture:** 단계 코드(프롬프트·도구·응답 해석·상태 전이)는 타입이 있는 Swift 로 짜고, 그래프 정의(노드·간선·경로 고르기)는 데이터로 한 곳에 둔다. `LangGraphRunner` 만 LangGraph 를 알고, 그래프 정의를 LangGraph `StateGraph` 로 옮겨 돌린다. 세 단계 결과는 지금의 `AssignmentPatch` 로 합쳐 기존 `AssignmentApplier` 에 넘기므로 저장 쪽은 바뀌지 않는다.

**Tech Stack:** Swift 5.10 (SwiftPM), GRDB, LangGraph-Swift (커밋 고정), XCTest, 기존 `LLMClient`/`CodexResponsesClient`.

**Spec:** `docs/superpowers/specs/2026-10-05-staged-judgment-pipeline-design.md`

## Global Constraints

- 플랫폼 macOS 14, swift-tools-version 5.10, Swift 5 언어 모드 (기존 그대로).
- LangGraph 의존성은 정확히 `.package(url: "https://github.com/bsorrentino/LangGraph-Swift.git", revision: "d91c62aaa25e818f2667482c6edbe635a375ec45")`, 제품 이름 `LangGraph`.
- LangChain 은 쓰지 않는다. LLM 호출은 기존 `LLMClient` 로만.
- `BatchConfig.pipeline` 기본값은 `.single`. `.single` 일 때 배치 동작·기록은 지금과 같아야 한다.
- 앱 화면에 새 문구를 넣지 않는다. 앱 전환은 숨은 설정값 `UserDefaults` 키 `batchPipeline` (`single` | `staged`).
- 모든 단계가 원래 행 번호를 쓴다.
- 정답 세트와 측정 결과는 `~/Library/Application Support/WorkGraph/eval/` 에만 둔다 (개인 기록, 커밋 금지).
- 측정 조건: 모델 `gpt-6-luna`, 추론 강도 `medium`, 기간 `--from 2026-10-04`.
- 커밋은 사용자가 요청할 때만 한다 (사용자 규칙). 이 계획에는 커밋 단계가 없다.

## Review Focus

- ②가 받지 않은 행까지 덮는 범위("1-6", 6행은 ①에서 없음)를 답하면, 6행은 ①의 판정을 그대로 가져야 한다 → Task 3 테스트.
- ①이 kind 를 대문자("Work")나 모르는 값("task")으로 답하면, 대문자는 받아들이고 모르는 값은 빠진 행으로 보고 다시 물어야 한다 → Task 2 테스트.
- ③이 일부 행의 resource 를 빼먹으면, 그 행은 resource 가 비어(nil) 적용기의 기본값 규칙을 따라야 한다 → Task 3 테스트.
- ② 호출이 전송 오류로 실패하면, 배치는 실패로 기록되고 행은 미처리로 남아야 한다 (일부만 반영 금지) → Task 5 테스트.
- ②를 다시 물을 때 모델이 앞 시도와 같은 ref("A")로 다른 새 업무를 정의하면, 두 업무가 섞이지 않아야 한다 → Task 4 테스트.

---

### Task 1: OntologyPrompt 를 조각 함수로 나누기 (동작 그대로)

**Files:**
- Modify: `Sources/WorkGraphCore/Ontology/OntologyPrompt.swift:35-83` (`build`)
- Test: `Tests/WorkGraphCoreTests/StagedPipelineTests.swift` (새 파일)

**Interfaces:**
- Produces:
  - `OntologyPrompt.nowLine(_ now: Double, timeZone: TimeZone) -> String` — `"NOW: yyyy-MM-dd HH:mm"`
  - `OntologyPrompt.taskLines(_ openTasks: [TaskDigest], brief: Bool = false) -> [String]` — 비면 `["(none)"]`, brief 면 `"- id=… | 제목 | goal: …"`
  - `OntologyPrompt.rowLines(_ rows: [ActivityRow], cards: [Int: [ScreenCard]], timeZone: TimeZone) -> [String]` — 행 줄과 그 아래 `screen:`/`text:`, 같은 카드는 이 목록 안에서 처음 한 번만 전문

- [ ] **Step 1: 실패하는 테스트**

`Tests/WorkGraphCoreTests/StagedPipelineTests.swift`:

```swift
import XCTest
import GRDB
@testable import WorkGraphCore

final class PromptPiecesTests: XCTestCase {
    private let digest = TaskDigest(id: "t_a", title: "대시보드 카드 UI 구현", taskType: "코드작성", topics: ["React"], recentResources: ["TaskCard.tsx"],
                                    lastActive: 0, recentSummaries: ["카드를 만들었다"], goal: "대시보드 카드 UI 를 만든다")

    func testBuildIsTheSumOfItsPieces() {
        let rows = Fixtures.frontendRows()
        let built = OntologyPrompt.build(rows: rows, openTasks: [digest], now: 1_000_000, timeZone: TimeZone(identifier: "Asia/Seoul")!)
        let pieces = [OntologyPrompt.nowLine(1_000_000, timeZone: TimeZone(identifier: "Asia/Seoul")!),
                      "TASK_TYPES: \(TBox.leafTaskTypes.joined(separator: ", "))", "OPEN_TASKS:"]
            + OntologyPrompt.taskLines([digest])
            + ["ROWS (row | time | dwell | app | type | title | uri) — assign every row:"]
            + OntologyPrompt.rowLines(rows, cards: [:], timeZone: TimeZone(identifier: "Asia/Seoul")!)
        XCTAssertEqual(built.user, pieces.joined(separator: "\n"))
        XCTAssertTrue(built.user.contains("- id=t_a | 대시보드 카드 UI 구현 | 코드작성 | goal: 대시보드 카드 UI 를 만든다 | topics: React | recent work: 카드를 만들었다 | recent: TaskCard.tsx"))
    }

    func testBriefTaskLinesKeepOnlyIdTitleAndGoal() {
        XCTAssertEqual(OntologyPrompt.taskLines([digest], brief: true), ["- id=t_a | 대시보드 카드 UI 구현 | goal: 대시보드 카드 UI 를 만든다"])
        XCTAssertEqual(OntologyPrompt.taskLines([], brief: true), ["(none)"])
    }

    func testASubsetShowsItsFirstCardInFull() {
        let rows = Fixtures.frontendRows()
        let card = ScreenCard(id: 7, tsStart: 0, tsEnd: 10, screenHash: 0, screenshotPath: nil, appBundle: "b", appName: "Cursor", windowTitle: nil, uri: nil,
                              activity: "TaskCard 를 고치고 있다", content: "줄 1", kind: "code", createdAt: 0)
        let lines = OntologyPrompt.rowLines(Array(rows[1...2]), cards: [2: [card], 3: [card]], timeZone: .current)
        XCTAssertTrue(lines.contains("    screen: TaskCard 를 고치고 있다"), "부분 목록에서는 2행이 처음이라 전문")
        XCTAssertTrue(lines.contains("    screen: (same screen as row 2)"))
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter PromptPiecesTests`
Expected: FAIL — `nowLine`, `taskLines`, `rowLines` 가 없음 (컴파일 오류)

- [ ] **Step 3: 구현** — `OntologyPrompt.swift` 의 `build` 를 아래로 바꾼다 (`cardLines`, `clip` 은 그대로):

```swift
    /// cards: 행 번호 → 그 행을 덮는 화면 기억 카드 (있으면 text: 대신 screen: 으로 넣는다)
    public static func build(rows: [ActivityRow], openTasks: [TaskDigest], now: Double, timeZone: TimeZone = .current,
                             cards: [Int: [ScreenCard]] = [:]) -> (system: String, user: String) {
        var lines = [nowLine(now, timeZone: timeZone), "TASK_TYPES: \(TBox.leafTaskTypes.joined(separator: ", "))", "OPEN_TASKS:"]
        lines += taskLines(openTasks)
        lines.append("ROWS (row | time | dwell | app | type | title | uri) — assign every row:")
        lines += rowLines(rows, cards: cards, timeZone: timeZone)
        return (system, lines.joined(separator: "\n"))
    }

    public static func nowLine(_ now: Double, timeZone: TimeZone) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = timeZone
        day.dateFormat = "yyyy-MM-dd HH:mm"
        return "NOW: \(day.string(from: Date(timeIntervalSince1970: now)))"
    }

    /// 후보 업무 줄. brief 면 id·제목·목표만 (① 업무 여부용)
    public static func taskLines(_ openTasks: [TaskDigest], brief: Bool = false) -> [String] {
        guard !openTasks.isEmpty else { return ["(none)"] }
        return openTasks.map { task in
            if brief { return "- id=\(task.id) | \(task.title)" + (task.goal.map { " | goal: \(clip($0, 140))" } ?? "") }
            var line = "- id=\(task.id) | \(task.title) | \(task.taskType ?? "기타")"
            if let goal = task.goal { line += " | goal: \(clip(goal, 140))" }
            if !task.topics.isEmpty { line += " | topics: \(task.topics.joined(separator: ", "))" }
            if !task.recentSummaries.isEmpty { line += " | recent work: \(task.recentSummaries.map { clip($0, 140) }.joined(separator: " / "))" }
            if !task.recentResources.isEmpty { line += " | recent: \(task.recentResources.prefix(3).map { clip($0, 50) }.joined(separator: "; "))" }
            return line
        }
    }

    /// 행 줄과 그 아래 screen:/text:. 같은 카드가 여러 행에 걸치면 이 목록 안에서 처음 한 번만 전문
    public static func rowLines(_ rows: [ActivityRow], cards: [Int: [ScreenCard]], timeZone: TimeZone) -> [String] {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = timeZone
        clock.dateFormat = "HH:mm"
        var lines: [String] = []
        var shown: [Int64: Int] = [:]                       // 카드 id → 처음 보인 행
        for row in rows {
            let time = "\(clock.string(from: Date(timeIntervalSince1970: row.start)))-\(clock.string(from: Date(timeIntervalSince1970: row.end)))"
            let fields = ["\(row.row)", time, "\(row.dwell)s", row.app, row.type ?? "-", clip(row.title ?? "-", 90), clip(row.uri ?? "-", 140)]
            lines.append(fields.joined(separator: " | "))
            let rowCards = cards[row.row] ?? []
            if rowCards.isEmpty || row.isChat {
                if let snippet = row.snippet, !snippet.isEmpty { lines.append("    text: \(snippet)") }
                continue
            }
            for card in rowCards {
                guard let id = card.id else { continue }
                if let first = shown[id] { lines.append("    screen: (same screen as row \(first))"); continue }
                shown[id] = row.row
                lines.append("    screen: \(clip(card.activity, 200))")
                for line in cardLines(card) { lines.append("      · \(clip(line, 160))") }
            }
        }
        return lines
    }
```

- [ ] **Step 4: 통과 확인**

Run: `swift test`
Expected: PASS (새 테스트 3개 + 기존 테스트 전부)

---

### Task 2: 단계별 프롬프트·도구·응답 해석

**Files:**
- Create: `Sources/WorkGraphCore/Ontology/Staged/StageSchemas.swift`
- Create: `Sources/WorkGraphCore/Ontology/Staged/StagePrompts.swift`
- Test: `Tests/WorkGraphCoreTests/StagedPipelineTests.swift`

**Interfaces:**
- Consumes: Task 1 의 `nowLine`, `taskLines`, `rowLines`, `clip`; `AssignmentPatch.unwrapStrings`, `AssignmentPatch.RowRef(rows:task:).numbers`
- Produces:
  - `enum RowKind: String { case work, off, none }`, `struct RowVerdict { kind: RowKind; reason: String }`
  - `struct TaskChoice { task: String; reason: String }`, `struct AssignResult { tasks: [AssignmentPatch.TaskDef]; rows: [Int: TaskChoice] }`
  - `struct DescribeResult { resources: [Int: Bool]; work: [AssignmentPatch.Work]; taskTypes: [String: String]; problems: [AssignmentPatch.ProblemRef]; laterItems: [AssignmentPatch.LaterRef] }`
  - `enum StageTool { static var classify, assign, describe: ToolSpec }` (이름 `classify_rows`, `assign_tasks`, `describe_work`)
  - `enum StageDecode { static func classify(_ data: Data) -> [Int: RowVerdict]; static func assign(_ data: Data) -> AssignResult; static func describe(_ data: Data) -> DescribeResult }`
  - `enum StagePrompt { struct Group { ref, isNew, title, goal, rows }; static let classifySystem, assignSystem, describeSystem: String; static func classify(rows:openTasks:cards:now:timeZone:) -> String; static func assign(rows:openTasks:cards:now:timeZone:) -> String; static func describe(groups:cards:now:timeZone:) -> String }`

- [ ] **Step 1: 실패하는 테스트** — `StagedPipelineTests.swift` 에 추가:

```swift
final class StageDecodeTests: XCTestCase {
    func testClassifyReadsRangesCaseAndSkipsUnknownKinds() {
        let data = Data(#"{"rows":[{"rows":"1-3","kind":"Work","reason":"카드 구현"},{"rows":4,"kind":"off","reason":"게임"},{"rows":"5","kind":"task","reason":"?"}]}"#.utf8)
        let verdicts = StageDecode.classify(data)
        XCTAssertEqual(verdicts[1], RowVerdict(kind: .work, reason: "카드 구현"))
        XCTAssertEqual(verdicts[3]?.kind, .work)
        XCTAssertEqual(verdicts[4]?.kind, .off)
        XCTAssertNil(verdicts[5], "모르는 kind 는 빠진 행으로 남는다")
    }

    func testAssignReadsTasksAndOff() {
        let data = Data(#"{"tasks":[{"ref":"A","match":"new","title":"카드 UI","goal":"카드를 만든다"}],"rows":[{"rows":"1-2","task":"A","reason":"구현"},{"rows":"3","task":"OFF","reason":"무관"}]}"#.utf8)
        let result = StageDecode.assign(data)
        XCTAssertEqual(result.tasks.map(\.ref), ["A"])
        XCTAssertEqual(result.rows[2], TaskChoice(task: "A", reason: "구현"))
        XCTAssertEqual(result.rows[3]?.task, AssignmentPatch.offTask)
    }

    func testDescribeReadsResourcesWorkTypesProblemsAndLaterItems() {
        let data = Data(#"{"resources":[{"rows":"1-2","resource":true},{"rows":"3","resource":false}],"work":[{"task":"A","summary":"카드를 만들었다","topics":["React"],"task_type":"코드작성"}],"problems":[{"row":2,"kind":"build","message":"key 경고","resolved_by_row":3}],"later_items":[{"row":3,"text":"간격 조정"}]}"#.utf8)
        let result = StageDecode.describe(data)
        XCTAssertEqual(result.resources, [1: true, 2: true, 3: false])
        XCTAssertEqual(result.work.first?.summary, "카드를 만들었다")
        XCTAssertEqual(result.taskTypes["A"], "코드작성")
        XCTAssertEqual(result.problems.first?.resolvedByRow, 3)
        XCTAssertEqual(result.laterItems.first?.text, "간격 조정")
    }

    func testStagePromptsCarryTheRulesAndOnlyTheirRows() {
        XCTAssertTrue(StagePrompt.classifySystem.contains("Hobbies and entertainment are not goals"))
        XCTAssertTrue(StagePrompt.classifySystem.contains("rows whose app is Sillog"))
        XCTAssertTrue(StagePrompt.classifySystem.contains("choose work"))
        XCTAssertTrue(StagePrompt.assignSystem.contains("managing the account, subscription or billing"))
        XCTAssertTrue(StagePrompt.describeSystem.contains("task_type"))
        let rows = Fixtures.frontendRows()
        let user = StagePrompt.assign(rows: Array(rows[0...1]), openTasks: [], cards: [:], now: 1_000_000, timeZone: .current)
        XCTAssertTrue(user.contains("TaskCard.tsx"))
        XCTAssertFalse(user.contains("디자인팀"), "받은 행만 들어간다")
        let groups = [StagePrompt.Group(ref: "A", isNew: true, title: "카드 UI", goal: "카드를 만든다", rows: Array(rows[0...1]))]
        let describe = StagePrompt.describe(groups: groups, cards: [:], now: 1_000_000, timeZone: .current)
        XCTAssertTrue(describe.contains("## A | NEW | 카드 UI | goal: 카드를 만든다"))
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter StageDecodeTests`
Expected: FAIL — `StageDecode`, `StagePrompt` 가 없음

- [ ] **Step 3: 구현** — `Sources/WorkGraphCore/Ontology/Staged/StageSchemas.swift`:

```swift
import Foundation

/// ① 업무 여부의 판정
public enum RowKind: String, Sendable { case work, off, none }

public struct RowVerdict: Equatable, Sendable {
    public var kind: RowKind
    public var reason: String
    public init(kind: RowKind, reason: String) { self.kind = kind; self.reason = reason }
}

/// ② 업무 대입: 행 → 업무 ref 또는 "off"
public struct TaskChoice: Equatable, Sendable {
    public var task: String
    public var reason: String
    public init(task: String, reason: String) { self.task = task; self.reason = reason }
}

public struct AssignResult: Equatable, Sendable {
    public var tasks: [AssignmentPatch.TaskDef] = []
    public var rows: [Int: TaskChoice] = [:]
    public init() {}
}

/// ③ 클래스 부여: 자료 여부, 업무별 요약·주제, 새 업무의 종류, 문제, 나중에 할 일
public struct DescribeResult: Equatable, Sendable {
    public var resources: [Int: Bool] = [:]
    public var work: [AssignmentPatch.Work] = []
    public var taskTypes: [String: String] = [:]
    public var problems: [AssignmentPatch.ProblemRef] = []
    public var laterItems: [AssignmentPatch.LaterRef] = []
    public init() {}
}

/// 세 단계의 도구 정의
public enum StageTool {
    static let rowRange: JSONValue = .object(["type": "string", "description": "행 번호 \"7\" 또는 범위 \"5-12\""])
    static let rowNumber: JSONValue = .object(["type": "integer", "description": "행 번호"])

    public static var classify: ToolSpec {
        ToolSpec(name: "classify_rows", description: "For every activity row: work toward a goal, off-task, or no content.", parameters: .object([
            "type": "object",
            "properties": .object(["rows": .object(["type": "array", "description": "모든 행을 빠짐없이. 연속 행이 같은 판정·같은 이유면 \"5-12\" 처럼 범위로", "items": .object([
                "type": "object",
                "properties": .object([
                    "rows": rowRange,
                    "kind": .object(["type": "string", "enum": .array(["work", "off", "none"])]),
                    "reason": .object(["type": "string", "description": "한국어 몇 단어: 업무면 무엇에 쓰였는지, 업무 외면 왜 어떤 목표에도 안 쓰이는지, 없음이면 '내용 없음'"]),
                ]),
                "required": .array(["rows", "kind", "reason"]),
            ])])]),
            "required": .array(["rows"]),
        ]))
    }

    public static var assign: ToolSpec {
        ToolSpec(name: "assign_tasks", description: "Assign every work row to the goal (task) it serves.", parameters: .object([
            "type": "object",
            "properties": .object([
                "tasks": .object(["type": "array", "description": "이번 답에서 쓰는 업무들. rows 는 ref 로 가리킨다", "items": .object([
                    "type": "object",
                    "properties": .object([
                        "ref": .object(["type": "string", "description": "이 답 안에서만 쓰는 짧은 이름 (A, B, …). \"off\" 는 쓰지 않는다"]),
                        "match": .object(["type": "string", "enum": .array(["existing", "new"])]),
                        "id": .object(["type": "string", "description": "match=existing 일 때 OPEN_TASKS 의 id"]),
                        "title": .object(["type": "string", "description": "match=new 일 때: 과목·프로젝트와 목표를 담은 짧은 한국어 제목"]),
                        "goal": .object(["type": "string", "description": "match=new 일 때 필수: 무엇을 위한 업무인지 한국어 한 문장 (회사·과목·프로젝트, 행사·마감 등 맥락 포함)"]),
                    ]),
                    "required": .array(["ref", "match"]),
                ])]),
                "rows": .object(["type": "array", "description": "받은 행을 빠짐없이", "items": .object([
                    "type": "object",
                    "properties": .object([
                        "rows": rowRange,
                        "task": .object(["type": "string", "description": "tasks 의 ref, 또는 어느 목표에도 안 맞으면 \"off\""]),
                        "reason": .object(["type": "string", "description": "이 행이 그 목표에 무엇으로 기여하는지 한국어 몇 단어"]),
                    ]),
                    "required": .array(["rows", "task", "reason"]),
                ])]),
            ]),
            "required": .array(["tasks", "rows"]),
        ]))
    }

    public static var describe: ToolSpec {
        ToolSpec(name: "describe_work", description: "Mark resources and describe the work done per task.", parameters: .object([
            "type": "object",
            "properties": .object([
                "resources": .object(["type": "array", "description": "모든 행을 빠짐없이", "items": .object([
                    "type": "object",
                    "properties": .object(["rows": rowRange, "resource": .object(["type": "boolean"])]),
                    "required": .array(["rows", "resource"]),
                ])]),
                "work": .object(["type": "array", "description": "업무마다 하나", "items": .object([
                    "type": "object",
                    "properties": .object([
                        "task": .object(["type": "string", "description": "TASKS 의 ref"]),
                        "summary": .object(["type": "string", "description": "이 행들에서 그 업무로 한 일, 한국어 한 문장"]),
                        "topics": .object(["type": "array", "items": .object(["type": "string"]), "description": "무엇에 관한 일인지 1~4개 (개념·기술·과목·문제 영역). 앱·사이트·플랫폼·프로젝트 이름과 채움말은 아님"]),
                        "task_type": .object(["type": "string", "enum": .array(TBox.leafTaskTypes.map { .string($0) }), "description": "NEW 업무일 때 필수"]),
                    ]),
                    "required": .array(["task", "summary", "topics"]),
                ])]),
                "problems": .object(["type": "array", "items": .object([
                    "type": "object",
                    "properties": .object(["row": rowNumber, "kind": .object(["type": "string", "description": "build, runtime, network, config 등"]),
                                           "message": .object(["type": "string"]), "resolved_by_row": rowNumber]),
                    "required": .array(["row", "kind", "message"]),
                ])]),
                "later_items": .object(["type": "array", "items": .object([
                    "type": "object",
                    "properties": .object(["row": rowNumber, "text": .object(["type": "string"])]),
                    "required": .array(["row", "text"]),
                ])]),
            ]),
            "required": .array(["resources", "work"]),
        ]))
    }
}

/// 단계 응답 해석. 작은 모델의 흔들림(중첩 JSON 문자열, 숫자 행 번호, 대소문자)을 받아 준다
public enum StageDecode {
    static func object(_ data: Data) -> [String: Any]? {
        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return AssignmentPatch.unwrapStrings(parsed) as? [String: Any]
    }

    static func numbers(_ value: Any?) -> [Int] {
        if let number = value as? Int { return [number] }
        if let text = value as? String { return AssignmentPatch.RowRef(rows: text, task: nil).numbers }
        return []
    }

    static func text(_ value: Any?) -> String? {
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? Int { return String(number) }
        return nil
    }

    static func decode<T: Decodable>(_ type: T.Type, _ value: Any?) -> T? {
        guard let value, JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public static func classify(_ data: Data) -> [Int: RowVerdict] {
        var result: [Int: RowVerdict] = [:]
        for entry in object(data)?["rows"] as? [[String: Any]] ?? [] {
            guard let raw = text(entry["kind"])?.lowercased(), let kind = RowKind(rawValue: raw) else { continue }
            let reason = text(entry["reason"]) ?? ""
            for number in numbers(entry["rows"]) { result[number] = RowVerdict(kind: kind, reason: reason) }
        }
        return result
    }

    public static func assign(_ data: Data) -> AssignResult {
        var result = AssignResult()
        guard let root = object(data) else { return result }
        result.tasks = decode([AssignmentPatch.TaskDef].self, root["tasks"]) ?? []
        for entry in root["rows"] as? [[String: Any]] ?? [] {
            guard let task = text(entry["task"]), !task.isEmpty, task.lowercased() != "null" else { continue }
            let choice = TaskChoice(task: task.lowercased() == AssignmentPatch.offTask ? AssignmentPatch.offTask : task, reason: text(entry["reason"]) ?? "")
            for number in numbers(entry["rows"]) { result.rows[number] = choice }
        }
        return result
    }

    public static func describe(_ data: Data) -> DescribeResult {
        var result = DescribeResult()
        guard let root = object(data) else { return result }
        for entry in root["resources"] as? [[String: Any]] ?? [] {
            guard let flag = entry["resource"] as? Bool else { continue }
            for number in numbers(entry["rows"]) { result.resources[number] = flag }
        }
        for entry in root["work"] as? [[String: Any]] ?? [] {
            guard let task = text(entry["task"]), !task.isEmpty else { continue }
            result.work.append(AssignmentPatch.Work(task: task, summary: text(entry["summary"]) ?? "", topics: entry["topics"] as? [String] ?? []))
            if let type = text(entry["task_type"]), !type.isEmpty { result.taskTypes[task] = type }
        }
        result.problems = decode([AssignmentPatch.ProblemRef].self, root["problems"]) ?? []
        result.laterItems = decode([AssignmentPatch.LaterRef].self, root["later_items"]) ?? []
        return result
    }
}
```

`Sources/WorkGraphCore/Ontology/Staged/StagePrompts.swift`:

```swift
import Foundation

/// 3단계 판정의 프롬프트. 규칙은 OntologyPrompt.system 에서 단계별로 나눠 옮겼다
public enum StagePrompt {
    /// ③에 넘기는 업무 묶음
    public struct Group: Sendable {
        public var ref: String
        public var isNew: Bool
        public var title: String
        public var goal: String?
        public var rows: [ActivityRow]
        public init(ref: String, isNew: Bool, title: String, goal: String?, rows: [ActivityRow]) {
            self.ref = ref; self.isNew = isNew; self.title = title; self.goal = goal; self.rows = rows
        }
    }

    static let rowsHeader = "ROWS (row | time | dwell | app | type | title | uri)"

    static let rowsGuide = """
    - ROWS: time-ordered activity rows. One row = one app/window context with its dwell seconds. `type` and `uri` were assigned by rules and are reliable.
      Under a row, `screen:` comes from a model that looked at the screenshot of that moment: its first line is that model's one-sentence reading of the front window, and the `·` lines below it are what was visible, quoted as written (messages with their sender). The quoted lines are the evidence; the first line is only a reading and can be wrong. When the first line does not fit the quoted lines, or a quoted word could mean more than one thing, decide from the quoted lines read together with the user's goals. `text:` is raw text read from the window when no screenshot description exists; it may include menus and sidebars.
      Rows whose app is "Claude Code" or "Codex CLI" (type AIChat, dwell 0) are the user's own messages to an AI coding assistant, quoted in `text:`. They say in the user's own words what they are trying to do: use them as the strongest evidence for what the surrounding rows are about.
    """

    public static let classifySystem = """
    You decide, for each raw desktop activity row, whether the user was working toward one of their goals, for a personal work graph.

    You receive:
    - GOALS: the user's current tasks from the last days: id, title and what the task is for (`goal:`). They show what the user is working toward; you do not assign rows to them here.
    \(rowsGuide)

    For EVERY row decide one kind:
    - none: the row has no content the user engaged with — a system screen, a transition between apps, an empty or loading page, the recorder's own window (rows whose app is Sillog). Nothing to read or do. Documents, pages or chats about a project named Sillog or 실록 are content like any other.
    - off: the user engaged with content, but it serves none of the user's goals: entertainment, hobbies, idle browsing, things unrelated to any goal. Hobbies and entertainment are not goals even when the user takes part regularly or with a team (games and game leagues, sports, fan communities), even when GOALS lists a task for them.
    - work: the content serves a goal, listed in GOALS or not yet listed. A goal is a project or one of its deliverables, a course being studied (its lectures, labs, notices), an errand with an outcome (an application, a payment, an interview), or a recurring routine that serves the user's work or study (a project team's channel, a class). Sub-steps are work for the goal they serve: reading documentation for it, checking the settings or usage of a tool used for it, signing in to or managing the account, subscription or billing of a tool or service used for it, installing a tool for it, looking at examples or references for it.
    Weigh the evidence in this order: what the user typed or read (the quoted `screen:` lines, chat messages, then `text:`) > the window title > the file or page name. A row is never judged by its neighbours; the rows arrive together only because they happened in the same minutes. Judge by content, not by the app or site.
    When a row could be work or off and the evidence does not settle it, choose work; the next step can still decide that it fits no goal.
    State in `reason`, in a few Korean words, what the row is used for (work), why it serves no goal (off), or '내용 없음' (none).

    Cover every row exactly once. Use ranges like "5-12" only when every row in the range has the same kind and reason.
    Always answer by calling classify_rows. Do not write prose.
    """

    public static let assignSystem = """
    You assign activity rows to the user's goals (tasks), for a personal work graph. Every row you receive was already judged to be work toward some goal.

    You receive:
    - OPEN_TASKS: the user's current tasks (goals) from the last days: id, title, type, what the task is for (`goal:`), topics, what was done in its recent sessions (`recent work:`), recent resources. Match rows against the goal, not only the title: a row serving the same goal belongs to that task even when it uses different words.
    \(rowsGuide)

    For each row decide which goal it serves:
    - an existing task (match="existing", its id): reuse it whenever the row serves that goal, judged by comparing the row's content with the task's title, goal, `recent work:` and resources. Sub-steps belong to the goal they serve: reading documentation for it, checking the settings or usage of a tool used for it, signing in to or managing the account, subscription or billing of a tool or service used for it, installing a tool for it, looking at examples or references for it, understanding its design.
    - a new task (match="new"): only for a goal that is not in OPEN_TASKS: a different course, a different project or deliverable, a different errand, a different routine. Two goals stay separate even when they share an app or a tool. A new task gets a short, specific Korean title that names the course/project and the goal, and a `goal` sentence saying what it is for with its context (company, course, project, event or deadline). Never an app name alone, never a catch-all title, never a bare category name. The goal names an outcome the user is working toward.
    - "off": the row turns out to serve no goal (the purpose is unclear, or it is entertainment, a hobby or browsing). Hobbies and entertainment are never goals, even when OPEN_TASKS lists a task for them. Do not list "off" in tasks.
    There is no minimum duration: a 10-second row about a distinct goal is that goal's row. A row is never assigned because neighbouring rows are.
    State in `reason`, in a few Korean words, what the row contributes to the goal.

    Assign every row you receive exactly once, by its row number. Use a range like "5-12" only when every number in it is a row you received and they share the task and reason.
    Always answer by calling assign_tasks. Do not write prose.
    """

    public static let describeSystem = """
    You describe the work the user did on their tasks, for a personal work graph. Every row you receive was already assigned to a task.

    You receive:
    - TASK_TYPES: the only allowed values for task_type.
    - TASKS: each task with its ref, whether it is NEW or existing, its title and goal, followed by the rows assigned to it.
    \(rowsGuide)

    Do this:
    1. resources (every row): true only when the row's file or page is a real reference or artifact of its task — something the user read, used or produced for it and would want to find again: a document, code file, notebook, design, note, docs page, paper, Q&A thread, video, AI chat, a page whose content the user actually read. false for everything else: a page merely visible while the user worked elsewhere, search results, blank or new tabs, login, redirect, account and billing pages, listings, profiles and navigation pages passed through, notification or inbox checks, tool settings and usage pages, a chat channel merely glanced at. When in doubt, false.
    2. work (every task): one Korean sentence about what was done in these rows, and 1-4 topics: what the work is ABOUT (a concept, technique, technology, course subject or problem domain). NOT the app, website or platform used, not the project name, no filler. For a NEW task also give task_type, one of TASK_TYPES.
    3. problems: only when the rows show an error or blocker (build error, failed command, searching an error message). Set resolved_by_row to the row of the page that solved it when that is evident.
    4. later_items: requests or todos that arrived in these rows but were not handled.

    Cover every row exactly once in resources. Use ranges like "5-12" only for consecutive rows of one task with the same value.
    Always answer by calling describe_work. Do not write prose.
    """

    public static func classify(rows: [ActivityRow], openTasks: [TaskDigest], cards: [Int: [ScreenCard]], now: Double, timeZone: TimeZone) -> String {
        ([OntologyPrompt.nowLine(now, timeZone: timeZone), "GOALS:"] + OntologyPrompt.taskLines(openTasks, brief: true)
            + ["\(rowsHeader) — judge every row:"] + OntologyPrompt.rowLines(rows, cards: cards, timeZone: timeZone)).joined(separator: "\n")
    }

    public static func assign(rows: [ActivityRow], openTasks: [TaskDigest], cards: [Int: [ScreenCard]], now: Double, timeZone: TimeZone) -> String {
        ([OntologyPrompt.nowLine(now, timeZone: timeZone), "OPEN_TASKS:"] + OntologyPrompt.taskLines(openTasks)
            + ["\(rowsHeader) — assign every row:"] + OntologyPrompt.rowLines(rows, cards: cards, timeZone: timeZone)).joined(separator: "\n")
    }

    public static func describe(groups: [Group], cards: [Int: [ScreenCard]], now: Double, timeZone: TimeZone) -> String {
        var lines = [OntologyPrompt.nowLine(now, timeZone: timeZone), "TASK_TYPES: \(TBox.leafTaskTypes.joined(separator: ", "))",
                     "TASKS (each followed by its rows: \(rowsHeader.dropFirst(5))):"]
        for group in groups {
            var head = "## \(group.ref) | \(group.isNew ? "NEW" : "existing") | \(OntologyPrompt.clip(group.title, 90))"
            if let goal = group.goal { head += " | goal: \(OntologyPrompt.clip(goal, 140))" }
            lines.append(head)
            lines += OntologyPrompt.rowLines(group.rows, cards: cards, timeZone: timeZone)
        }
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter StageDecodeTests` 다음 `swift test`
Expected: PASS

---

### Task 3: 상태·그래프 정의·단계 함수·합치기·흐름도

**Files:**
- Create: `Sources/WorkGraphCore/Ontology/Staged/StagedPipeline.swift`
- Test: `Tests/WorkGraphCoreTests/StagedPipelineTests.swift`, `Tests/WorkGraphCoreTests/OntologyBatcherTests.swift` (StubLLM 에 `users` 기록 추가)

**Interfaces:**
- Consumes: Task 2 전부, `AssignmentPatch`, `LLMClient`, `LLMResult`
- Produces:
  - `struct JudgeInput { rows: [ActivityRow]; openTasks: [TaskDigest]; cards: [Int: [ScreenCard]]; now: Double; timeZone: TimeZone }` (`init(rows:openTasks:cards:now:timeZone:)`)
  - `struct StageCall { stage, system, user, raw, model: String; promptTokens, completionTokens: Int }`
  - `struct JudgeState { input; verdicts: [Int: RowVerdict]; classifyAttempts: Int; assignment: AssignResult; assignAttempts: Int; description: DescribeResult; calls: [StageCall]; unclassified, workRows, unassigned, assignedRows: [ActivityRow] }`
  - `enum PipelineError: Error { case incomplete(stage: String, missing: [Int], calls: [StageCall]); case lostState; var calls: [StageCall] }`
  - `struct PipelineGraph { struct Edge { label, target }; struct Node { id, title, run: (JudgeState, any LLMClient) async throws -> JudgeState, route: (JudgeState) -> String, edges: [Edge] }; static let end = "end"; entry: String; nodes: [Node]; func mermaid() -> String }`
  - `enum StagedPipeline { static let maxAttempts = 2; static var graph: PipelineGraph; static func classify/assign/describe(_:_:) async throws -> JudgeState; static func taskGroups(_:) -> [StagePrompt.Group]; static func patch(from: JudgeState) -> AssignmentPatch }`

- [ ] **Step 1: StubLLM 이 모든 호출의 사용자 프롬프트를 남기게** — `OntologyBatcherTests.swift` 의 `StubLLM` 에 `private(set) var users: [String] = []` 를 추가하고, `callFunction` 의 잠금 블록에서 `lastUser = user` 다음 줄에 `users.append(user)` 를 넣는다.

- [ ] **Step 2: 실패하는 테스트** — `StagedPipelineTests.swift` 에 추가:

```swift
enum StageReplies {
    static let classifyAll = #"{"rows":[{"rows":"1-5","kind":"work","reason":"카드 구현"},{"rows":"6","kind":"none","reason":"내용 없음"}]}"#
    static let assignA = #"{"tasks":[{"ref":"A","match":"new","title":"대시보드 카드 UI 구현","goal":"대시보드 카드 UI 를 만든다"}],"rows":[{"rows":"1-5","task":"A","reason":"카드 구현"}]}"#
    static let describeA = #"{"resources":[{"rows":"1-2","resource":true},{"rows":"3-4","resource":false},{"rows":"5","resource":true}],"work":[{"task":"A","summary":"TaskCard 를 구현했다","topics":["React"],"task_type":"코드작성"}],"problems":[{"row":4,"kind":"build","message":"React key prop warning","resolved_by_row":5}],"later_items":[]}"#
}

final class StagedMergeTests: XCTestCase {
    private func state(_ rows: [ActivityRow]) -> JudgeState { JudgeState(input: JudgeInput(rows: rows, openTasks: [], now: 1_000_000)) }

    func testStageFunctionsFillTheStateAndMergeIntoOnePatch() async throws {
        let rows = Fixtures.frontendRows()
        let llm = StubLLM([.success(StageReplies.classifyAll), .success(StageReplies.assignA), .success(StageReplies.describeA)])
        var current = try await StagedPipeline.classify(state(rows), llm)
        XCTAssertEqual(current.workRows.map(\.row), [1, 2, 3, 4, 5])
        current = try await StagedPipeline.assign(current, llm)
        XCTAssertFalse(llm.users[1].contains("디자인팀"), "②에는 업무 행만")
        current = try await StagedPipeline.describe(current, llm)
        XCTAssertTrue(llm.users[2].contains("## A | NEW | 대시보드 카드 UI 구현"))
        let patch = StagedPipeline.patch(from: current)
        XCTAssertEqual(patch.tasks.map(\.ref), ["A"])
        XCTAssertEqual(patch.tasks.first?.taskType, "코드작성", "새 업무의 종류는 ③의 것")
        let byRow = patch.byRow()
        XCTAssertEqual(byRow[3]?.task, "A")
        XCTAssertEqual(byRow[3]?.resource, false)
        XCTAssertNil(byRow[6]?.task, "①에서 없음")
        XCTAssertEqual(patch.problems?.first?.resolvedByRow, 5)
        XCTAssertEqual(current.calls.map(\.stage), ["classify", "assign", "describe"])
    }

    func testAssignRangeOverRowsItDidNotReceiveIsIgnored() async throws {
        let rows = Fixtures.frontendRows()
        let llm = StubLLM([.success(StageReplies.classifyAll),
                           .success(#"{"tasks":[{"ref":"A","match":"new","title":"대시보드 카드 UI 구현","goal":"카드"}],"rows":[{"rows":"1-6","task":"A","reason":"카드 구현"}]}"#)])
        var current = try await StagedPipeline.classify(state(rows), llm)
        current = try await StagedPipeline.assign(current, llm)
        XCTAssertNil(current.assignment.rows[6], "6행은 ②가 받지 않았다")
        XCTAssertNil(StagedPipeline.patch(from: current).byRow()[6]?.task, "①의 없음 그대로")
    }

    func testMissingResourceLeavesTheDefaultToTheApplier() async throws {
        let rows = Fixtures.frontendRows()
        let llm = StubLLM([.success(StageReplies.classifyAll), .success(StageReplies.assignA),
                           .success(#"{"resources":[{"rows":"1","resource":true}],"work":[{"task":"A","summary":"s","topics":[],"task_type":"코드작성"}]}"#)])
        var current = try await StagedPipeline.classify(state(rows), llm)
        current = try await StagedPipeline.assign(current, llm)
        current = try await StagedPipeline.describe(current, llm)
        XCTAssertNil(StagedPipeline.patch(from: current).byRow()[2]?.resource, "빠진 resource 는 비워 둔다")
    }

    func testStagedPatchBuildsTheSameGraphAsTheEquivalentSingleCall() async throws {
        let rows = Fixtures.frontendRows()
        let llm = StubLLM([.success(StageReplies.classifyAll), .success(StageReplies.assignA), .success(StageReplies.describeA)])
        var current = try await StagedPipeline.classify(state(rows), llm)
        current = try await StagedPipeline.assign(current, llm)
        current = try await StagedPipeline.describe(current, llm)
        let staged = StagedPipeline.patch(from: current)
        let single = try Fixtures.patch("""
        {"tasks":[{"ref":"A","match":"new","title":"대시보드 카드 UI 구현","goal":"대시보드 카드 UI 를 만든다","task_type":"코드작성"}],
         "rows":[{"rows":"1-2","task":"A","resource":true,"reason":"카드 구현"},{"rows":"3-4","task":"A","resource":false,"reason":"카드 구현"},
                 {"rows":"5","task":"A","resource":true,"reason":"카드 구현"},{"rows":"6","task":null,"resource":false,"reason":"내용 없음"}],
         "work":[{"task":"A","summary":"TaskCard 를 구현했다","topics":["React"]}],
         "problems":[{"row":4,"kind":"build","message":"React key prop warning","resolved_by_row":5}],"later_items":[]}
        """)
        func graph(_ patch: AssignmentPatch) throws -> [String] {
            let db = try WGDatabase.inMemory()
            return try db.writer.write { conn in
                let tx = GraphTx(conn)
                try TBox.seed(tx, at: 0)
                _ = try AssignmentApplier().apply(patch, rows: rows, tx: tx, now: 2_000_000, requireComplete: true)
                let nodes = try String.fetchAll(conn, sql: "SELECT label || ':' || title FROM nodes WHERE label NOT IN ('TaskType', 'ResourceType') ORDER BY 1")
                let edges = try String.fetchAll(conn, sql: "SELECT type || ':' || COUNT(*) FROM edges GROUP BY type ORDER BY 1")
                return nodes + edges
            }
        }
        XCTAssertEqual(try graph(staged), try graph(single))
    }

    func testMermaidListsEveryNodeAndEdge() {
        let text = StagedPipeline.graph.mermaid()
        for piece in ["flowchart TD", "classify[\"① 업무 여부\"]", "assign[\"② 업무 대입\"]", "describe[\"③ 클래스 부여\"]",
                      "classify -->|빠진 행| classify", "classify -->|업무 행 없음| save", "assign -->|업무 있음| describe", "describe -->|끝| save"] {
            XCTAssertTrue(text.contains(piece), piece)
        }
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `swift test --filter StagedMergeTests`
Expected: FAIL — `JudgeState`, `StagedPipeline` 이 없음

- [ ] **Step 4: 구현** — `Sources/WorkGraphCore/Ontology/Staged/StagedPipeline.swift`:

```swift
import Foundation

/// 3단계 판정의 입력: 그래프 밖에서 준비한 행·후보 업무·화면 카드
public struct JudgeInput: Sendable {
    public var rows: [ActivityRow]
    public var openTasks: [TaskDigest]
    public var cards: [Int: [ScreenCard]]
    public var now: Double
    public var timeZone: TimeZone

    public init(rows: [ActivityRow], openTasks: [TaskDigest], cards: [Int: [ScreenCard]] = [:], now: Double, timeZone: TimeZone = .current) {
        self.rows = rows; self.openTasks = openTasks; self.cards = cards; self.now = now; self.timeZone = timeZone
    }
}

/// 단계 호출 하나의 기록 (배치 기록에 남긴다)
public struct StageCall: Sendable {
    public var stage: String
    public var system: String
    public var user: String
    public var raw: String
    public var model: String
    public var promptTokens: Int
    public var completionTokens: Int
}

/// 단계 사이를 오가는 상태. LangGraph 에는 이 값 하나를 통째로 넘긴다
public struct JudgeState: Sendable {
    public var input: JudgeInput
    public var verdicts: [Int: RowVerdict] = [:]
    public var classifyAttempts = 0
    public var assignment = AssignResult()
    public var assignAttempts = 0
    public var description = DescribeResult()
    public var calls: [StageCall] = []

    public init(input: JudgeInput) { self.input = input }

    /// ①이 아직 판정하지 않은 행
    public var unclassified: [ActivityRow] { input.rows.filter { verdicts[$0.row] == nil } }
    /// ①이 업무로 본 행
    public var workRows: [ActivityRow] { input.rows.filter { verdicts[$0.row]?.kind == .work } }
    /// 업무 행 중 ②가 아직 배정하지 않은 행
    public var unassigned: [ActivityRow] { workRows.filter { assignment.rows[$0.row] == nil } }
    /// ②가 업무에 붙인 행 (off 제외)
    public var assignedRows: [ActivityRow] {
        workRows.filter { row in assignment.rows[row.row].map { $0.task != AssignmentPatch.offTask } ?? false }
    }
}

public enum PipelineError: Error, CustomStringConvertible {
    case incomplete(stage: String, missing: [Int], calls: [StageCall])
    case lostState

    public var description: String {
        switch self {
        case .incomplete(let stage, let missing, _):
            return "\(stage) 단계가 행 \(missing.count)개를 판정하지 못함 (\(missing.prefix(10).map(String.init).joined(separator: ", ")))"
        case .lostState:
            return "단계 사이에서 상태를 잃음"
        }
    }

    public var calls: [StageCall] {
        if case .incomplete(_, _, let calls) = self { return calls }
        return []
    }
}

/// 그래프 정의: 실행기와 흐름도가 같은 정의를 읽는다
public struct PipelineGraph: Sendable {
    public struct Edge: Sendable {
        public var label: String
        public var target: String
    }

    public struct Node: Sendable {
        public var id: String
        public var title: String
        public var run: @Sendable (JudgeState, any LLMClient) async throws -> JudgeState
        /// 다음으로 갈 간선의 이름
        public var route: @Sendable (JudgeState) -> String
        public var edges: [Edge]
    }

    /// 끝 (저장)
    public static let end = "end"
    public var entry: String
    public var nodes: [Node]

    /// Mermaid 흐름도. LangGraph-Swift 는 그래프 그리기를 지원하지 않아 직접 만든다
    public func mermaid() -> String {
        var lines = ["flowchart TD", "    start([준비]) --> \(entry)"]
        for node in nodes { lines.append("    \(node.id)[\"\(node.title)\"]") }
        lines.append("    save([저장])")
        for node in nodes {
            for edge in node.edges { lines.append("    \(node.id) -->|\(edge.label)| \(edge.target == Self.end ? "save" : edge.target)") }
        }
        return lines.joined(separator: "\n")
    }
}

/// ① 업무 여부 → ② 업무 대입 → ③ 클래스 부여
public enum StagedPipeline {
    /// 빠진 행을 다시 묻는 것까지 포함한 단계별 최대 시도
    public static let maxAttempts = 2

    public static var graph: PipelineGraph {
        PipelineGraph(entry: "classify", nodes: [
            .init(id: "classify", title: "① 업무 여부", run: classify, route: { state in
                if !state.unclassified.isEmpty { return state.classifyAttempts < maxAttempts ? "빠진 행" : "실패" }
                return state.workRows.isEmpty ? "업무 행 없음" : "업무 행 있음"
            }, edges: [.init(label: "빠진 행", target: "classify"), .init(label: "업무 행 있음", target: "assign"),
                       .init(label: "업무 행 없음", target: PipelineGraph.end), .init(label: "실패", target: PipelineGraph.end)]),
            .init(id: "assign", title: "② 업무 대입", run: assign, route: { state in
                if !state.unassigned.isEmpty { return state.assignAttempts < maxAttempts ? "빠진 행" : "실패" }
                return state.assignedRows.isEmpty ? "업무 없음" : "업무 있음"
            }, edges: [.init(label: "빠진 행", target: "assign"), .init(label: "업무 있음", target: "describe"),
                       .init(label: "업무 없음", target: PipelineGraph.end), .init(label: "실패", target: PipelineGraph.end)]),
            .init(id: "describe", title: "③ 클래스 부여", run: describe, route: { _ in "끝" },
                  edges: [.init(label: "끝", target: PipelineGraph.end)]),
        ])
    }

    static func record(_ stage: String, system: String, user: String, _ result: LLMResult) -> StageCall {
        StageCall(stage: stage, system: system, user: user, raw: result.raw, model: result.model,
                  promptTokens: result.promptTokens, completionTokens: result.completionTokens)
    }

    /// ① 아직 판정하지 않은 행만 묻는다 (첫 시도는 전부)
    public static func classify(_ state: JudgeState, _ llm: any LLMClient) async throws -> JudgeState {
        var next = state
        let pending = state.unclassified
        let user = StagePrompt.classify(rows: pending, openTasks: state.input.openTasks, cards: state.input.cards, now: state.input.now, timeZone: state.input.timeZone)
        let result = try await llm.callFunction(system: StagePrompt.classifySystem, user: user, tool: StageTool.classify)
        let wanted = Set(pending.map(\.row))
        for (row, verdict) in StageDecode.classify(result.arguments) where wanted.contains(row) { next.verdicts[row] = verdict }
        next.classifyAttempts += 1
        next.calls.append(record("classify", system: StagePrompt.classifySystem, user: user, result))
        return next
    }

    /// ② 업무 행 중 아직 배정하지 않은 행만. 다시 물을 때 정의한 ref 는 앞 시도와 겹치지 않게 접두어를 붙인다
    public static func assign(_ state: JudgeState, _ llm: any LLMClient) async throws -> JudgeState {
        var next = state
        let pending = state.unassigned
        let user = StagePrompt.assign(rows: pending, openTasks: state.input.openTasks, cards: state.input.cards, now: state.input.now, timeZone: state.input.timeZone)
        let result = try await llm.callFunction(system: StagePrompt.assignSystem, user: user, tool: StageTool.assign)
        let answer = StageDecode.assign(result.arguments)
        let prefix = state.assignAttempts == 0 ? "" : "r\(state.assignAttempts + 1)-"
        func renamed(_ ref: String) -> String { ref == AssignmentPatch.offTask ? ref : prefix + ref }
        let wanted = Set(pending.map(\.row))
        var used = Set<String>()
        for (row, choice) in answer.rows where wanted.contains(row) {
            next.assignment.rows[row] = TaskChoice(task: renamed(choice.task), reason: choice.reason)
            used.insert(renamed(choice.task))
        }
        for var definition in answer.tasks where used.contains(renamed(definition.ref)) {
            definition.ref = renamed(definition.ref)
            next.assignment.tasks.append(definition)
        }
        next.assignAttempts += 1
        next.calls.append(record("assign", system: StagePrompt.assignSystem, user: user, result))
        return next
    }

    /// ③ 업무별로 묶은 행
    public static func describe(_ state: JudgeState, _ llm: any LLMClient) async throws -> JudgeState {
        var next = state
        let user = StagePrompt.describe(groups: taskGroups(state), cards: state.input.cards, now: state.input.now, timeZone: state.input.timeZone)
        let result = try await llm.callFunction(system: StagePrompt.describeSystem, user: user, tool: StageTool.describe)
        next.description = StageDecode.describe(result.arguments)
        next.calls.append(record("describe", system: StagePrompt.describeSystem, user: user, result))
        return next
    }

    /// ②의 업무별로 행을 묶는다. 머리줄은 기존 업무면 후보 목록의 제목·목표, 새 업무면 ②가 쓴 것
    public static func taskGroups(_ state: JudgeState) -> [StagePrompt.Group] {
        let byId = Dictionary(state.input.openTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var order: [String] = [], rowsByRef: [String: [ActivityRow]] = [:]
        for row in state.assignedRows {
            guard let ref = state.assignment.rows[row.row]?.task else { continue }
            if rowsByRef[ref] == nil { order.append(ref) }
            rowsByRef[ref, default: []].append(row)
        }
        return order.map { ref in
            let definition = state.assignment.tasks.first { $0.ref == ref }
            let existing = definition?.match == "existing" ? definition?.id.flatMap { byId[$0] } : nil
            return StagePrompt.Group(ref: ref, isNew: existing == nil, title: existing?.title ?? definition?.title ?? ref,
                                     goal: existing?.goal ?? definition?.goal, rows: rowsByRef[ref] ?? [])
        }
    }

    /// 세 단계 결과를 지금과 같은 AssignmentPatch 로 합친다
    public static func patch(from state: JudgeState) -> AssignmentPatch {
        var rows: [AssignmentPatch.RowRef] = []
        for row in state.input.rows {
            guard let verdict = state.verdicts[row.row] else { continue }
            let number = "\(row.row)"
            switch verdict.kind {
            case .none:
                rows.append(.init(rows: number, task: nil, resource: false, reason: verdict.reason))
            case .off:
                rows.append(.init(rows: number, task: AssignmentPatch.offTask, resource: false, reason: verdict.reason))
            case .work:
                guard let choice = state.assignment.rows[row.row] else { continue }
                if choice.task == AssignmentPatch.offTask {
                    rows.append(.init(rows: number, task: AssignmentPatch.offTask, resource: false, reason: choice.reason))
                } else {
                    rows.append(.init(rows: number, task: choice.task, resource: state.description.resources[row.row], reason: choice.reason))
                }
            }
        }
        let used = Set(rows.compactMap(\.task))
        var tasks = state.assignment.tasks.filter { used.contains($0.ref) }
        for index in tasks.indices where tasks[index].taskType == nil {
            tasks[index].taskType = state.description.taskTypes[tasks[index].ref]
        }
        return AssignmentPatch(tasks: tasks, rows: rows, work: state.description.work,
                               problems: state.description.problems, laterItems: state.description.laterItems)
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `swift test --filter StagedMergeTests` 다음 `swift test`
Expected: PASS

---

### Task 4: LangGraph 실행기와 흐름

**Files:**
- Modify: `Package.swift` (의존성, `WorkGraphCore` 대상)
- Create: `Sources/WorkGraphCore/Ontology/Staged/LangGraphRunner.swift`
- Modify: `Sources/WorkGraphCore/Ontology/Staged/StagedPipeline.swift` (`run` 추가)
- Test: `Tests/WorkGraphCoreTests/StagedPipelineTests.swift`

**Interfaces:**
- Consumes: Task 3 의 `PipelineGraph`, `JudgeState`, `PipelineError`, `StagedPipeline.graph/patch`
- Produces:
  - `protocol PipelineRunner: Sendable { func run(_ graph: PipelineGraph, _ state: JudgeState, llm: any LLMClient) async throws -> JudgeState }`
  - `struct LangGraphRunner: PipelineRunner { init() }`
  - `StagedPipeline.run(_ input: JudgeInput, llm: any LLMClient, runner: any PipelineRunner = LangGraphRunner()) async throws -> (patch: AssignmentPatch, calls: [StageCall])`

- [ ] **Step 1: 의존성 추가** — `Package.swift`:

```swift
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // LangGraph for Swift: 문서 플러그인을 브랜치로 물고 있어 버전이 아니라 커밋으로 고정 (마지막 커밋 2025-08-01)
        .package(url: "https://github.com/bsorrentino/LangGraph-Swift.git", revision: "d91c62aaa25e818f2667482c6edbe635a375ec45"),
    ],
```

`WorkGraphCore` 대상의 dependencies 를 `[.product(name: "GRDB", package: "GRDB.swift"), .product(name: "LangGraph", package: "LangGraph-Swift")]` 로.

Run: `swift package resolve && swift build`
Expected: `Build complete!` (LangGraph-Swift, swift-docc-plugin 을 받음)

- [ ] **Step 2: 실패하는 테스트** — `StagedPipelineTests.swift` 에 추가:

```swift
final class StagedFlowTests: XCTestCase {
    func testThreeCallsWhenThereIsWork() async throws {
        let llm = StubLLM([.success(StageReplies.classifyAll), .success(StageReplies.assignA), .success(StageReplies.describeA)])
        let (patch, calls) = try await StagedPipeline.run(JudgeInput(rows: Fixtures.frontendRows(), openTasks: [], now: 1_000_000), llm: llm)
        XCTAssertEqual(llm.calls, 3)
        XCTAssertEqual(calls.map(\.stage), ["classify", "assign", "describe"])
        XCTAssertEqual(patch.rows.count, 6)
    }

    func testOneCallWhenNoRowIsWork() async throws {
        let llm = StubLLM([.success(#"{"rows":[{"rows":"1-5","kind":"off","reason":"게임"},{"rows":"6","kind":"none","reason":"내용 없음"}]}"#)])
        let (patch, _) = try await StagedPipeline.run(JudgeInput(rows: Fixtures.frontendRows(), openTasks: [], now: 1_000_000), llm: llm)
        XCTAssertEqual(llm.calls, 1)
        XCTAssertTrue(patch.tasks.isEmpty)
        XCTAssertEqual(patch.byRow()[1]?.task, AssignmentPatch.offTask)
    }

    func testMissingRowsAreAskedAgainAlone() async throws {
        let llm = StubLLM([.success(#"{"rows":[{"rows":"1-5","kind":"work","reason":"카드 구현"}]}"#),
                           .success(#"{"rows":[{"rows":"6","kind":"none","reason":"내용 없음"}]}"#),
                           .success(StageReplies.assignA), .success(StageReplies.describeA)])
        _ = try await StagedPipeline.run(JudgeInput(rows: Fixtures.frontendRows(), openTasks: [], now: 1_000_000), llm: llm)
        XCTAssertEqual(llm.calls, 4)
        XCTAssertTrue(llm.users[1].contains("디자인팀"))
        XCTAssertFalse(llm.users[1].contains("TaskCard.tsx"), "다시 물을 때는 빠진 행만")
    }

    func testStillMissingAfterRetryFails() async throws {
        let partial = #"{"rows":[{"rows":"1-5","kind":"work","reason":"카드 구현"}]}"#
        let llm = StubLLM([.success(partial), .success(#"{"rows":[]}"#)])
        do {
            _ = try await StagedPipeline.run(JudgeInput(rows: Fixtures.frontendRows(), openTasks: [], now: 1_000_000), llm: llm)
            XCTFail("빠진 행이 남으면 실패해야 함")
        } catch let error as PipelineError {
            XCTAssertEqual(error.calls.count, 2)
            guard case .incomplete(_, let missing, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(missing, [6])
        }
    }

    func testRetryRefsDoNotCollideWithTheFirstAttempt() async throws {
        let llm = StubLLM([.success(StageReplies.classifyAll),
                           .success(#"{"tasks":[{"ref":"A","match":"new","title":"대시보드 카드 UI 구현","goal":"카드"}],"rows":[{"rows":"1-3","task":"A","reason":"카드"}]}"#),
                           .success(#"{"tasks":[{"ref":"A","match":"new","title":"오류 해결 조사","goal":"오류를 고친다"}],"rows":[{"rows":"4-5","task":"A","reason":"오류"}]}"#),
                           .success(#"{"resources":[],"work":[{"task":"A","summary":"s","topics":[],"task_type":"코드작성"},{"task":"r2-A","summary":"s","topics":[],"task_type":"코드작성"}]}"#)])
        let (patch, _) = try await StagedPipeline.run(JudgeInput(rows: Fixtures.frontendRows(), openTasks: [], now: 1_000_000), llm: llm)
        XCTAssertEqual(Set(patch.tasks.map(\.ref)), ["A", "r2-A"])
        XCTAssertEqual(patch.byRow()[4]?.task, "r2-A")
        XCTAssertEqual(patch.tasks.first { $0.ref == "r2-A" }?.title, "오류 해결 조사")
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `swift test --filter StagedFlowTests`
Expected: FAIL — `StagedPipeline.run` 이 없음

- [ ] **Step 4: 구현** — `Sources/WorkGraphCore/Ontology/Staged/LangGraphRunner.swift`:

```swift
import Foundation
import LangGraph

/// 그래프 정의를 돌리는 실행기. 라이브러리를 바꿔도 단계 코드는 그대로 둔다
public protocol PipelineRunner: Sendable {
    func run(_ graph: PipelineGraph, _ state: JudgeState, llm: any LLMClient) async throws -> JudgeState
}

/// LangGraph-Swift 로 돌린다. LangGraph 는 상태를 [String: Any] 로 다루므로, 타입 있는 JudgeState 하나를 "judge" 키에 넣고 꺼낸다
public struct LangGraphRunner: PipelineRunner {
    struct Carrier: AgentState {
        var data: [String: Any]
        init(_ initState: [String: Any]) { data = initState }
        var judge: JudgeState? { data["judge"] as? JudgeState }
    }

    public init() {}

    public func run(_ graph: PipelineGraph, _ state: JudgeState, llm: any LLMClient) async throws -> JudgeState {
        let workflow = StateGraph { Carrier($0) }
        for node in graph.nodes {
            try workflow.addNode(node.id) { carrier in
                guard let current = carrier.judge else { throw PipelineError.lostState }
                return ["judge": try await node.run(current, llm)]
            }
        }
        try workflow.addEdge(sourceId: START, targetId: graph.entry)
        for node in graph.nodes {
            let mapping = Dictionary(node.edges.map { ($0.label, $0.target == PipelineGraph.end ? END : $0.target) }, uniquingKeysWith: { first, _ in first })
            try workflow.addConditionalEdge(sourceId: node.id, condition: { carrier in
                guard let current = carrier.judge else { throw PipelineError.lostState }
                return node.route(current)
            }, edgeMapping: mapping)
        }
        let result = try await workflow.compile().invoke(.args(["judge": state]))
        guard let final = result.judge else { throw PipelineError.lostState }
        return final
    }
}
```

`StagedPipeline` 에 추가:

```swift
    /// 판정 전체: 그래프를 돌리고 합친 patch 와 단계 호출 기록을 돌려준다. 빠진 행이 남으면 PipelineError.incomplete
    public static func run(_ input: JudgeInput, llm: any LLMClient, runner: any PipelineRunner = LangGraphRunner()) async throws -> (patch: AssignmentPatch, calls: [StageCall]) {
        let final = try await runner.run(graph, JudgeState(input: input), llm: llm)
        if !final.unclassified.isEmpty {
            throw PipelineError.incomplete(stage: "① 업무 여부", missing: final.unclassified.map(\.row), calls: final.calls)
        }
        if !final.unassigned.isEmpty {
            throw PipelineError.incomplete(stage: "② 업무 대입", missing: final.unassigned.map(\.row), calls: final.calls)
        }
        return (patch(from: final), final.calls)
    }
```

- [ ] **Step 5: 통과 확인**

Run: `swift test --filter StagedFlowTests` 다음 `swift test`
Expected: PASS

---

### Task 5: 배치에 연결 (숨은 설정으로 전환)

**Files:**
- Modify: `Sources/WorkGraphCore/Ontology/OntologyBatcher.swift` (`BatchConfig`, `run` 의 판정·기록 부분)
- Modify: `Sources/WorkGraphApp/AppState.swift:84` (배치 생성)
- Test: `Tests/WorkGraphCoreTests/StagedPipelineTests.swift`

**Interfaces:**
- Consumes: Task 4 의 `StagedPipeline.run`, `PipelineError`
- Produces:
  - `public enum BatchPipeline: String, Sendable { case single, staged }`
  - `BatchConfig.pipeline: BatchPipeline` (기본 `.single`)
  - `OntologyBatcher.Judgment` (내부): `patch, failure, model, promptTokens, completionTokens, raw, prompt`

- [ ] **Step 1: 실패하는 테스트**:

```swift
final class StagedBatcherTests: XCTestCase {
    private func seed(_ db: WGDatabase) throws {
        let store = EventStore(db)
        _ = try store.insert(Observation(ts: 100, trigger: "app_activate", appBundle: "com.todesktop.230313mzl4w4u92", appName: "Cursor", windowTitle: "TaskCard.tsx — dashboard"))
        _ = try store.insert(Observation(ts: 160, trigger: "app_activate", appBundle: "com.google.Chrome", appName: "Google Chrome",
                                         windowTitle: "Card - shadcn/ui - Google Chrome", url: "https://ui.shadcn.com/docs/components/card"))
    }

    private func batcher(_ db: WGDatabase, _ llm: StubLLM) -> OntologyBatcher {
        var config = BatchConfig()
        config.pipeline = .staged
        return OntologyBatcher(db: db, llm: llm, config: config, home: "/Users/me", fileExists: { _ in false }, clock: { 450 })
    }

    func testStagedBatchAppliesAndRecordsEveryStage() async throws {
        let db = try WGDatabase.inMemory()
        try seed(db)
        let llm = StubLLM([.success(#"{"rows":[{"rows":"1-2","kind":"work","reason":"카드 구현"}]}"#),
                           .success(#"{"tasks":[{"ref":"A","match":"new","title":"대시보드 카드 UI 구현","goal":"카드를 만든다"}],"rows":[{"rows":"1-2","task":"A","reason":"카드 구현"}]}"#),
                           .success(#"{"resources":[{"rows":"1-2","resource":true}],"work":[{"task":"A","summary":"카드를 만들었다","topics":["React"],"task_type":"코드작성"}]}"#)])
        guard case .ok(let stats) = await batcher(db, llm).runIfDue(force: true) else { return XCTFail("배치 성공해야 함") }
        XCTAssertEqual(stats.tasksCreated, 1)
        XCTAssertEqual(llm.calls, 3, "업무가 하나뿐이라 업무 합치기 호출은 없음")
        let batch = try XCTUnwrap(EventStore(db).recentBatches(limit: 1).first)
        XCTAssertEqual(batch.status, "ok")
        XCTAssertEqual(batch.promptTokens, 300, "단계 토큰 합계")
        XCTAssertTrue(batch.rawResponse?.contains("\"classify\"") ?? false)
        XCTAssertTrue(batch.userPrompt?.contains("[assign]") ?? false)
        XCTAssertTrue(try EventStore(db).unprocessed(limit: 10).isEmpty)
    }

    func testAFailedLaterStageAppliesNothing() async throws {
        let db = try WGDatabase.inMemory()
        try seed(db)
        let llm = StubLLM([.success(#"{"rows":[{"rows":"1-2","kind":"work","reason":"카드 구현"}]}"#), .failure(.http(500, "server"))])
        guard case .failed = await batcher(db, llm).runIfDue(force: true) else { return XCTFail("실패해야 함") }
        XCTAssertEqual(try EventStore(db).unprocessed(limit: 10).count, 2, "행은 미처리로 남는다")
        XCTAssertEqual(try EventStore(db).recentBatches(limit: 1).first?.status, "failed")
        XCTAssertTrue(try db.writer.read { try GraphTx($0).nodes(label: NodeLabel.task) }.isEmpty)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter StagedBatcherTests`
Expected: FAIL — `BatchConfig.pipeline` 이 없음

- [ ] **Step 3: 구현** — `OntologyBatcher.swift`:

`BatchConfig` 안 (`cardReuseWindow` 다음):

```swift
    /// 판정 방식: 한 번 호출(지금) 또는 3단계(업무 여부 → 업무 대입 → 클래스 부여)
    public var pipeline: BatchPipeline = .single
```

파일 위쪽 (`BatchOutcome` 앞):

```swift
public enum BatchPipeline: String, Sendable { case single, staged }
```

`run` 에서 `let prompt = OntologyPrompt.build(...)` 부터 `guard let patch, !patch.rows.isEmpty else { ... }` 블록 끝까지를 바꾼다:

```swift
        let model = llm.modelName
        let judgment: Judgment
        do {
            judgment = try await judge(rows: rows, openTasks: openTasks, cards: cards, now: now)
        } catch {
            // 서버가 죽었거나 토큰이 만료된 경우: 데이터는 그대로 두고 기다린다. 건너뛰지 않는다.
            let message = (error as? LLMError)?.description ?? "\(error)"
            let sent = config.pipeline == .single ? OntologyPrompt.build(rows: rows, openTasks: openTasks, now: now, cards: cards) : nil
            try recordFailure(message: message, model: model, first: first, last: last, rowCount: rows.count, raw: nil, now: now, prompt: sent)
            scheduleBackoff(now: now)
            return .failed(message)
        }

        guard let patch = judgment.patch, !patch.rows.isEmpty else {
            let message = judgment.failure ?? "LLM 응답에 행 배정이 없음"
            try recordFailure(message: message, model: judgment.model, first: first, last: last, rowCount: rows.count, raw: judgment.raw, now: now,
                              tokens: (judgment.promptTokens, judgment.completionTokens), prompt: judgment.prompt)
            scheduleBackoff(now: now)
            return .failed(message)
        }
```

그 아래 반영 블록과 `catch` 블록에서 `result.model` → `judgment.model`, `result.promptTokens` → `judgment.promptTokens`, `result.completionTokens` → `judgment.completionTokens`, `result.raw` → `judgment.raw`, `prompt.system` → `judgment.prompt.system`, `prompt.user` → `judgment.prompt.user`, `tokens: (result.promptTokens, result.completionTokens)` → `tokens: (judgment.promptTokens, judgment.completionTokens)`, `prompt: prompt` → `prompt: judgment.prompt` 로 바꾼다.

액터 안 (`makeCards` 앞):

```swift
    /// 판정 한 번의 결과와 기록용 원문. 한 번 호출이든 3단계든 같은 모양
    struct Judgment {
        var patch: AssignmentPatch?
        var failure: String?
        var model: String
        var promptTokens: Int
        var completionTokens: Int
        var raw: String
        var prompt: (system: String, user: String)

        init(single result: LLMResult, prompt: (system: String, user: String)) {
            patch = AssignmentPatch.decodeLenient(from: result.arguments)
            failure = nil
            model = result.model; promptTokens = result.promptTokens; completionTokens = result.completionTokens
            raw = result.raw; self.prompt = prompt
        }

        init(patch: AssignmentPatch?, calls: [StageCall], failure: String?, fallbackModel: String) {
            self.patch = patch; self.failure = failure
            model = calls.last?.model ?? fallbackModel
            promptTokens = calls.reduce(0) { $0 + $1.promptTokens }
            completionTokens = calls.reduce(0) { $0 + $1.completionTokens }
            let raws = calls.map { ["stage": $0.stage, "raw": $0.raw] }
            raw = (try? JSONSerialization.data(withJSONObject: raws, options: [.prettyPrinted, .withoutEscapingSlashes]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            prompt = (calls.map { "[\($0.stage)]\n\($0.system)" }.joined(separator: "\n\n"),
                      calls.map { "[\($0.stage)]\n\($0.user)" }.joined(separator: "\n\n"))
        }
    }

    private func judge(rows: [ActivityRow], openTasks: [TaskDigest], cards: [Int: [ScreenCard]], now: Double) async throws -> Judgment {
        switch config.pipeline {
        case .single:
            let prompt = OntologyPrompt.build(rows: rows, openTasks: openTasks, now: now, cards: cards)
            let result = try await llm.callFunction(system: prompt.system, user: prompt.user, tool: AssignmentSchema.tool)
            return Judgment(single: result, prompt: prompt)
        case .staged:
            do {
                let (patch, calls) = try await StagedPipeline.run(JudgeInput(rows: rows, openTasks: openTasks, cards: cards, now: now), llm: llm)
                return Judgment(patch: patch, calls: calls, failure: nil, fallbackModel: llm.modelName)
            } catch let error as PipelineError {
                return Judgment(patch: nil, calls: error.calls, failure: error.description, fallbackModel: llm.modelName)
            }
        }
    }
```

`AppState.swift:84` 의 `let batcher = OntologyBatcher(db: database, llm: makeClient())` 를:

```swift
            var batchConfig = BatchConfig()
            // 숨은 설정: defaults write com.capstone.workgraph batchPipeline staged
            batchConfig.pipeline = BatchPipeline(rawValue: UserDefaults.standard.string(forKey: "batchPipeline") ?? "") ?? .single
            let batcher = OntologyBatcher(db: database, llm: makeClient(), config: batchConfig)
```

- [ ] **Step 4: 통과 확인**

Run: `swift test` 다음 `swift build`
Expected: PASS, `Build complete!` (앱 대상 포함)

---

### Task 6: 측정 명령 (`gold-run`, `pipeline-graph`)

**Files:**
- Modify: `Sources/wgctl/main.swift` (usage, `GoldJob`, `gold-candidates`, `gold-score`, 새 명령 두 개)

**Interfaces:**
- Consumes: `StagedPipeline.run`, `StagedPipeline.graph.mermaid()`, `JudgeInput`, `BatchPipeline`
- Produces (wgctl 안):
  - `struct GoldJob { batchId: Int64; input: JudgeInput; current: [Int: (label: String, reason: String)]; evidence: [Int: String] }`
  - `struct GoldLabels { init(tasks: [GraphNode]); func name(_:) -> String; func label(_ patch: AssignmentPatch, decided:, row:) -> (label: String, reason: String) }`
  - `func goldJobs(from: Double, until: Double, limit: Int) throws -> [GoldJob]`
  - `func judgeGold(_ jobs: [GoldJob], pipeline: BatchPipeline, client: any LLMClient) async -> (patches: [Int64: AssignmentPatch], failed: [Int64], calls: Int)`
  - `func goldTaskLevel(_ label: String?) -> String?`, `func printGoldScore(_ title: String, graded: [[String: Any]], predict: ([String: Any]) -> String?)`

- [ ] **Step 1: 재구성·이름표·판정·채점을 함수로 뺀다** — `main.swift` 위쪽의 `GoldJob` 정의를 아래로 바꾸고 함수들을 추가한다 (`gold-candidates` 의 1~3단계 코드와 `gold-score` 의 채점 코드를 그대로 옮긴 것):

```swift
/// 정답 세트 재료: 배치 하나를 앱이 보낸 것과 같은 방식으로 다시 만든 것
struct GoldJob {
    let batchId: Int64
    let input: JudgeInput
    let current: [Int: (label: String, reason: String)]
    let evidence: [Int: String]
    var rows: [ActivityRow] { input.rows }
}

/// 판정 이름표: task:키 / new:제목 / off / none
struct GoldLabels {
    let titleByKey: [String: String]
    let keyByTitle: [String: String]

    init(tasks: [GraphNode]) {
        titleByKey = Dictionary(tasks.map { ($0.key, $0.title) }, uniquingKeysWith: { first, _ in first })
        keyByTitle = Dictionary(tasks.map { (AssignmentApplier.normalizeTitle($0.title).lowercased(), $0.key) }, uniquingKeysWith: { first, _ in first })
    }

    func name(_ label: String) -> String {
        if label.hasPrefix("task:") { return titleByKey[String(label.dropFirst(5))] ?? label }
        if label.hasPrefix("new:") { return "새 업무: " + label.dropFirst(4) }
        return label == "off" ? "업무 외" : label == "none" ? "없음" : label
    }

    func label(_ patch: AssignmentPatch, decided: [Int: (task: String?, resource: Bool?, reason: String?)], row: Int) -> (label: String, reason: String) {
        guard let decision = decided[row] else { return ("missing", "") }
        let reason = decision.reason ?? ""
        guard let ref = decision.task else { return ("none", reason) }
        if ref == AssignmentPatch.offTask { return ("off", reason) }
        guard let definition = patch.tasks.first(where: { $0.ref == ref }) else { return ("missing", reason) }
        let title = AssignmentApplier.normalizeTitle(definition.title ?? "")
        if definition.match == "existing", let id = definition.id, titleByKey[id] != nil { return ("task:\(id)", reason) }
        if let key = keyByTitle[title.lowercased()] { return ("task:\(key)", reason) }
        if AssignmentApplier.isCategory(title) { return ("off", reason) }
        return ("new:\(title)", reason)
    }
}

/// 정답 세트용: 그 기간의 배치를 앱이 보낸 것과 같은 방식으로 다시 만든다 (행·카드·후보 업무·지금 판정)
func goldJobs(from: Double, until: Double, limit: Int) throws -> [GoldJob] {
    let config = BatchConfig(), home = NSHomeDirectory()
    let exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    let observations = try store.assignedObservations()
    let chats = try store.assignedChatMessages()
    let byBatch = Dictionary(grouping: observations, by: { $0.batchId ?? -1 })
    let chatsByBatch = Dictionary(grouping: chats, by: { $0.batchId ?? -1 })
    let batches = try store.recentBatches(limit: 100_000).filter { batch in
        guard batch.status == "ok", let id = batch.id, let first = byBatch[id]?.first else { return false }
        return first.ts >= from && first.ts < until
    }.sorted { ($0.id ?? 0) < ($1.id ?? 0) }.prefix(limit)
    let taskNodes = try db.writer.read { try GraphTx($0).nodes(label: NodeLabel.task) }
    let keyById = Dictionary(taskNodes.map { ($0.id, $0.key) }, uniquingKeysWith: { first, _ in first })
    var jobs: [GoldJob] = []
    for batch in batches {
        guard let batchId = batch.id, let window = byBatch[batchId], let first = window.first, let last = window.last else { continue }
        let windowEnd = try store.nextObservationTs(after: last) ?? (last.ts + config.maxGap)
        let idle = try store.idleSpans(from: first.ts, to: windowEnd)
        let texts = try store.texts(ids: window.compactMap(\.textId))
        let rows = EventCompressor.merge(
            EventCompressor.compress(window, idle: idle, texts: texts, windowEnd: windowEnd, home: home, fileExists: exists,
                                     maxRows: config.maxRows, maxGap: config.maxGap, snippetChars: config.snippetChars, snippetTopN: config.snippetTopN),
            chats: chatsByBatch[batchId] ?? [], home: home, fileExists: exists, snippetChars: config.snippetChars)
        let cardOf = Dictionary(window.compactMap { obs in obs.id.flatMap { id in obs.cardId.map { (id, $0) } } }, uniquingKeysWith: { first, _ in first })
        let cards: [Int: [ScreenCard]] = try db.writer.read { conn in
            var result: [Int: [ScreenCard]] = [:]
            for row in rows where !row.isChat {
                let ids = Array(Set(row.observationIds.compactMap { cardOf[$0] }))
                let found = try ScreenCard.fetchAll(conn, keys: ids).sorted { $0.tsStart < $1.tsStart }
                if !found.isEmpty { result[row.row] = found }
            }
            return result
        }
        let openTasks = try db.writer.read { try GraphTx($0).openTasks(limit: 40, since: first.ts - 7 * 86_400) }
        let decided = Dictionary(window.compactMap { obs in obs.id.map { ($0, obs) } }, uniquingKeysWith: { first, _ in first })
        let chatTask = Dictionary((chatsByBatch[batchId] ?? []).compactMap { chat in chat.id.map { ($0, chat.taskId) } }, uniquingKeysWith: { first, _ in first })
        var current: [Int: (label: String, reason: String)] = [:], evidence: [Int: String] = [:]
        for row in rows {
            var votes: [String: Int] = [:], reason = ""
            if row.isChat {
                let task = row.chatMessageIds.compactMap { chatTask[$0] ?? nil }.first.flatMap { keyById[$0] }
                votes[task.map { "task:\($0)" } ?? "none", default: 0] += 1
            } else {
                for id in row.observationIds {
                    guard let obs = decided[id] else { continue }
                    votes[obs.taskId.flatMap { keyById[$0] }.map { "task:\($0)" } ?? (obs.offTask ? "off" : "none"), default: 0] += 1
                    if reason.isEmpty, let text = obs.taskReason { reason = text }
                }
            }
            current[row.row] = (votes.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? "none", reason)
            var lines: [String] = []
            if let rowCards = cards[row.row] {
                for card in rowCards { lines.append("screen: \(card.activity)"); lines += OntologyPrompt.cardLines(card).map { "· \($0)" } }
            } else if let snippet = row.snippet, !snippet.isEmpty {
                lines.append("text: \(OntologyPrompt.clip(snippet, 300))")
            }
            evidence[row.row] = lines.joined(separator: "\n")
        }
        jobs.append(GoldJob(batchId: batchId, input: JudgeInput(rows: rows, openTasks: openTasks, cards: cards, now: batch.startedAt),
                            current: current, evidence: evidence))
    }
    return jobs
}

/// 배치들을 고른 방식으로 판정만 받는다 (3개씩 동시에, 기록 안 함)
func judgeGold(_ jobs: [GoldJob], pipeline: BatchPipeline, client: any LLMClient) async -> (patches: [Int64: AssignmentPatch], failed: [Int64], calls: Int) {
    var patches: [Int64: AssignmentPatch] = [:], failed: [Int64] = [], calls = 0
    await withTaskGroup(of: (Int64, AssignmentPatch?, Int).self) { group in
        var next = 0
        func add() {
            guard next < jobs.count else { return }
            let id = jobs[next].batchId, input = jobs[next].input
            next += 1
            group.addTask {
                switch pipeline {
                case .single:
                    let prompt = OntologyPrompt.build(rows: input.rows, openTasks: input.openTasks, now: input.now, cards: input.cards)
                    let result = try? await client.callFunction(system: prompt.system, user: prompt.user, tool: AssignmentSchema.tool)
                    return (id, result.flatMap { AssignmentPatch.decodeLenient(from: $0.arguments) }, 1)
                case .staged:
                    do {
                        let (patch, stageCalls) = try await StagedPipeline.run(input, llm: client)
                        return (id, patch, stageCalls.count)
                    } catch let error as PipelineError {
                        return (id, nil, error.calls.count)
                    } catch {
                        return (id, nil, 0)
                    }
                }
            }
        }
        for _ in 0..<3 { add() }
        while let (id, patch, count) = await group.next() {
            calls += count
            if let patch { patches[id] = patch } else { failed.append(id) }
            print("  \(patches.count + failed.count)/\(jobs.count)")
            add()
        }
    }
    return (patches, failed, calls)
}

/// 업무 기준 이름표: 없음·업무 외는 "업무 아님" 하나로, 새 업무는 제목과 상관없이 "new"
func goldTaskLevel(_ label: String?) -> String? {
    guard let label else { return nil }
    if label == "none" || label == "off" || label == "not-task" || label == "missing" { return "not-task" }
    return label.hasPrefix("new:") ? "new" : label
}

/// 정답 세트로 채점해 한 줄 출력 (업무 기준 + 없음·업무 외까지 구분한 엄격 점수)
func printGoldScore(_ title: String, graded: [[String: Any]], predict: ([String: Any]) -> String?) {
    func strict(_ label: String?) -> String? { label.map { $0.hasPrefix("new:") ? "new" : $0 } }
    func kind(_ label: String) -> String { label.hasPrefix("task:") ? "업무" : label.hasPrefix("new:") ? "새 업무" : "업무 아님" }
    var correct = 0, strictCorrect = 0, strictTotal = 0, perKind: [String: (ok: Int, total: Int)] = [:]
    for row in graded {
        let gold = row["gold"] as! String, guess = predict(row)
        let ok = goldTaskLevel(guess) == goldTaskLevel(gold)
        if ok { correct += 1 }
        perKind[kind(gold), default: (0, 0)].total += 1
        if ok { perKind[kind(gold), default: (0, 0)].ok += 1 }
        if gold != "not-task" { strictTotal += 1; if strict(guess) == strict(gold) { strictCorrect += 1 } }
    }
    let detail = perKind.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.ok)/\($0.value.total)" }.joined(separator: ", ")
    print(String(format: "  %@: 업무 기준 %d/%d (%.1f%%) — %@ | 없음·업무 외까지 구분 %d/%d (%.1f%%)", title, correct, graded.count,
                 100.0 * Double(correct) / Double(max(1, graded.count)), detail, strictCorrect, strictTotal,
                 100.0 * Double(strictCorrect) / Double(max(1, strictTotal))))
}

/// 정답 세트 (사람이 확정한 행만)
func loadGoldRows(_ path: String) -> [[String: Any]]? {
    guard let data = FileManager.default.contents(atPath: path),
          let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = file["rows"] as? [[String: Any]] else { return nil }
    return rows.filter { $0["gold"] is String }
}
```

`case "gold-candidates":` 본문을 함수들로 다시 쓴다 (출력 파일 형식은 그대로):

```swift
    case "gold-candidates":
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"; day.timeZone = .current
        guard let fromText = option("--from"), let from = day.date(from: fromText)?.timeIntervalSince1970 else {
            fail("사용법: gold-candidates --from YYYY-MM-DD [--to YYYY-MM-DD] [--limit N] [--model M] [--reasoning high] [--out FILE]")
        }
        let until = option("--to").flatMap { day.date(from: $0)?.timeIntervalSince1970 }.map { $0 + 86_400 } ?? .infinity
        let limit = option("--limit").flatMap(Int.init) ?? Int.max
        let out = option("--out") ?? evalDirectory + "/gold-candidates.json"
        let model = option("--model") ?? CodexResponsesClient.defaultModel
        let client = makeClient().client
        let jobs = try goldJobs(from: from, until: until, limit: limit)
        let labels = GoldLabels(tasks: try db.writer.read { try GraphTx($0).nodes(label: NodeLabel.task) })
        print("배치 \(jobs.count)개, 행 \(jobs.reduce(0) { $0 + $1.rows.count })개를 다시 판정합니다 (모델 \(model), 기록하지 않음)")
        let (patches, failedBatches, _) = await judgeGold(jobs, pipeline: .single, client: client)
        var items: [[String: Any]] = [], disagree = 0
        for job in jobs {
            guard let patch = patches[job.batchId] else { continue }
            let decided = patch.byRow()
            for row in job.rows {
                guard let current = job.current[row.row] else { continue }
                let judge = labels.label(patch, decided: decided, row: row.row)
                let agree = judge.label == current.label
                if !agree { disagree += 1 }
                items.append([
                    "batch": job.batchId, "row": row.row, "start": row.start, "dwell": row.dwell, "app": row.app,
                    "title": row.title ?? "", "uri": row.uri ?? "", "evidence": job.evidence[row.row] ?? "",
                    "current": ["label": current.label, "name": labels.name(current.label), "reason": current.reason],
                    "judge": ["label": judge.label, "name": labels.name(judge.label), "reason": judge.reason],
                    "agree": agree, "gold": agree ? current.label as Any : NSNull(),
                ])
            }
        }
        try FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let payload: [String: Any] = ["from": fromText, "model": model, "created": Date().timeIntervalSince1970, "failed_batches": failedBatches, "rows": items]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: URL(fileURLWithPath: out))
        print("행 \(items.count)개 중 갈린 행 \(disagree)개\(failedBatches.isEmpty ? "" : ", 실패한 배치 \(failedBatches)") → \(out)")
```

`case "gold-score":` 본문의 채점 부분을 `printGoldScore` 로 바꾼다:

```swift
    case "gold-score":
        let path = option("--gold") ?? evalDirectory + "/gold.json"
        guard let graded = loadGoldRows(path) else { fail("정답 세트를 읽을 수 없음: \(path)") }
        var predictions: [String: String] = [:]
        if let predictionPath = option("--predictions") {
            guard let raw = FileManager.default.contents(atPath: predictionPath), let map = try? JSONSerialization.jsonObject(with: raw) as? [String: String] else {
                fail("예측 파일을 읽을 수 없음: \(predictionPath)")
            }
            predictions = map
        }
        print("정답 세트 \(graded.count)행 (사람이 고른 행 \(graded.filter { ($0["source"] as? String) == "human" }.count)개) — \(path)")
        printGoldScore("지금 판정", graded: graded) { ($0["current"] as? [String: Any])?["label"] as? String }
        printGoldScore("다시 판정", graded: graded) { ($0["judge"] as? [String: Any])?["label"] as? String }
        if !predictions.isEmpty { printGoldScore("예측", graded: graded) { predictions["\($0["batch"] ?? ""):\($0["row"] ?? "")"] } }
```

- [ ] **Step 2: 새 명령** — `case "replay-batch":` 앞에:

```swift
    case "gold-run":
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"; day.timeZone = .current
        guard let fromText = option("--from"), let from = day.date(from: fromText)?.timeIntervalSince1970,
              let pipeline = BatchPipeline(rawValue: option("--pipeline") ?? "staged") else {
            fail("사용법: gold-run --from YYYY-MM-DD [--to YYYY-MM-DD] [--pipeline single|staged] [--runs N] [--limit N] [--model M] [--reasoning R] [--out FILE]")
        }
        let until = option("--to").flatMap { day.date(from: $0)?.timeIntervalSince1970 }.map { $0 + 86_400 } ?? .infinity
        let limit = option("--limit").flatMap(Int.init) ?? Int.max
        let runs = max(1, option("--runs").flatMap(Int.init) ?? 1)
        let out = option("--out") ?? evalDirectory + "/gold-run-\(pipeline.rawValue).json"
        let client = makeClient().client
        let jobs = try goldJobs(from: from, until: until, limit: limit)
        let labels = GoldLabels(tasks: try db.writer.read { try GraphTx($0).nodes(label: NodeLabel.task) })
        print("배치 \(jobs.count)개, 행 \(jobs.reduce(0) { $0 + $1.rows.count })개 — \(pipeline.rawValue) × \(runs)회 (기록하지 않음)")
        var predictionRuns: [[String: String]] = []
        for run in 1...runs {
            let started = Date()
            let (patches, failed, calls) = await judgeGold(jobs, pipeline: pipeline, client: client)
            var predictions: [String: String] = [:]
            for job in jobs {
                guard let patch = patches[job.batchId] else { continue }
                let decided = patch.byRow()
                for row in job.rows { predictions["\(job.batchId):\(row.row)"] = labels.label(patch, decided: decided, row: row.row).label }
            }
            predictionRuns.append(predictions)
            print(String(format: "  %d회: 호출 %d번 (배치당 %.1f), 실패 배치 %d개, %d초", run, calls, Double(calls) / Double(max(1, jobs.count)),
                         failed.count, Int(Date().timeIntervalSince(started))))
        }
        try FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let payload: [String: Any] = ["from": fromText, "pipeline": pipeline.rawValue, "created": Date().timeIntervalSince1970, "runs": predictionRuns]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: out))
        print("→ \(out)")
        if let graded = loadGoldRows(evalDirectory + "/gold.json") {
            for (index, predictions) in predictionRuns.enumerated() {
                printGoldScore("\(pipeline.rawValue) \(index + 1)회", graded: graded) { predictions["\($0["batch"] ?? ""):\($0["row"] ?? "")"] }
            }
        }
        if predictionRuns.count >= 2 {
            let first = predictionRuns[0], second = predictionRuns[1]
            let shared = Set(first.keys).intersection(second.keys)
            let flipped = shared.filter { goldTaskLevel(first[$0]) != goldTaskLevel(second[$0]) }.count
            print(String(format: "  흔들림: 두 실행에서 업무 기준 판정이 달라진 행 %d/%d (%.1f%%)", flipped, shared.count, 100.0 * Double(flipped) / Double(max(1, shared.count))))
        }

    case "pipeline-graph":
        print(StagedPipeline.graph.mermaid())

```

usage 에서 `gold-score` 설명 다음 줄에:

```
  gold-run --from YYYY-MM-DD [--pipeline single|staged] [--runs N] [--model M] [--reasoning R] [--out FILE]
                                        정답 세트 배치를 고른 판정 방식으로 다시 판정만 받아(기록 안 함) 채점하고, 두 번 이상이면 흔들림도 낸다
  pipeline-graph                        3단계 판정 흐름도를 Mermaid 로 출력
```

- [ ] **Step 3: 빌드와 확인**

Run: `swift build --product wgctl && .build/debug/wgctl pipeline-graph`
Expected: `flowchart TD` 로 시작하는 Mermaid, `classify -->|빠진 행| classify` 포함

Run (`$SCRATCH` 는 세션 스크래치 폴더): `.build/debug/wgctl gold-run --from 2026-10-05 --limit 2 --pipeline staged --model gpt-6-luna --reasoning medium --out "$SCRATCH/gold-run-smoke.json"`
Expected: `1회: 호출 N번` 과 정답 세트 채점 줄이 출력됨 (배치 2개뿐이라 숫자는 의미 없음)

Run: `swift test`
Expected: PASS

---

### Task 7: 측정과 결정

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-staged-judgment-pipeline-design.md` (맨 끝에 "측정 결과" 절)
- Modify (조건부): `Sources/WorkGraphCore/Ontology/OntologyBatcher.swift` (`pipeline` 기본값)

- [ ] **Step 1: 한 번 호출 측정**

Run: `.build/debug/wgctl gold-run --from 2026-10-04 --pipeline single --runs 2 --model gpt-6-luna --reasoning medium`
Expected: 두 실행의 업무 기준 정확도, 흔들림 비율, 배치당 호출 1.0

- [ ] **Step 2: 3단계 측정**

Run: `.build/debug/wgctl gold-run --from 2026-10-04 --pipeline staged --runs 2 --model gpt-6-luna --reasoning medium`
Expected: 두 실행의 업무 기준 정확도, 흔들림 비율, 배치당 호출 ≤ 3 (재시도 포함 평균)

- [ ] **Step 3: 결과를 설계서에 남긴다** — 설계서 끝에:

```markdown
## 측정 결과 (2026-10-05, 정답 세트 664행, gpt-6-luna medium)

| | 업무 기준 정확도 (1회 / 2회) | 흔들림 | 배치당 호출 |
|---|---|---|---|
| 한 번 호출 | (Step 1 값) | (값) | 1.0 |
| 3단계 | (Step 2 값) | (값) | (값) |

결정: (성공 기준 세 가지를 모두 넘으면 "기본값을 .staged 로 바꿈", 아니면 "기본값은 .single 유지, 이유")
```

- [ ] **Step 4: 기준을 넘었을 때만** — `BatchConfig.pipeline` 기본값을 `.staged` 로 바꾸고 `swift test` 와 `scripts/make-app.sh` 로 앱을 다시 빌드한다. 기준을 못 넘으면 바꾸지 않는다.

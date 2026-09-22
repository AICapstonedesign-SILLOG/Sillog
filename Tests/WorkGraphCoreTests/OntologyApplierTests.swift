import XCTest
import GRDB
@testable import WorkGraphCore

enum Fixtures {
    /// 회의 문서의 프론트 개발 예시 (14:02 ~ 15:30). base = 14:02 의 Unix 초.
    static func frontendRows(base: Double = 1_000_000) -> [ActivityRow] {
        func row(_ n: Int, _ startMin: Double, _ endMin: Double, app: String, bundle: String, title: String,
                 uri: String? = nil, type: String? = nil, projectKey: String? = nil, projectTitle: String? = nil) -> ActivityRow {
            ActivityRow(row: n, start: base + startMin * 60, end: base + endMin * 60, dwell: Int((endMin - startMin) * 60),
                        app: app, appBundle: bundle, title: title, uri: uri, type: type,
                        projectKey: projectKey, projectTitle: projectTitle, snippet: nil, observationIds: [Int64(n)])
        }
        return [
            row(1, 0, 9, app: "Cursor", bundle: "com.todesktop.230313mzl4w4u92", title: "TaskCard.tsx",
                uri: "code:dashboard/TaskCard.tsx", type: "CodeFile", projectKey: "project:dashboard", projectTitle: "dashboard"),
            row(2, 9, 22, app: "Google Chrome", bundle: "com.google.Chrome", title: "Card - shadcn/ui",
                uri: "https://ui.shadcn.com/docs/components/card", type: "Documentation"),
            row(3, 22, 36, app: "Google Chrome", bundle: "com.google.Chrome", title: "localhost:3000", uri: "local:3000/", type: "Preview"),
            row(4, 36, 50, app: "Terminal", bundle: "com.apple.Terminal", title: "npm run dev"),
            row(5, 50, 78, app: "Google Chrome", bundle: "com.google.Chrome", title: "React key prop warning - Stack Overflow",
                uri: "https://stackoverflow.com/questions/28329382", type: "QnA"),
            row(6, 78, 88, app: "Slack", bundle: "com.tinyspeck.slackmacgap", title: "디자인팀"),
        ]
    }

    static let frontendPatchJSON = """
    {"segments":[{"from_row":1,"to_row":6,
      "task":{"match":"new","title":"대시보드 카드 UI 구현","task_type":"코드작성"},
      "summary":"TaskCard 컴포넌트 구현, key prop 경고 해결",
      "topics":["React","shadcn/ui"],
      "problems":[{"row":4,"kind":"build","message":"React key prop warning","resolved_by_row":5}],
      "later_items":[{"row":6,"text":"카드 간격 16px로 조정"}],
      "switch_kind":null}]}
    """

    static func patch(_ json: String) throws -> OntologyPatch {
        try JSONDecoder().decode(OntologyPatch.self, from: Data(json.utf8))
    }
}

final class OntologyApplierTests: XCTestCase {
    private func makeDB() throws -> WGDatabase {
        let db = try WGDatabase.inMemory()
        try db.writer.write { conn in try TBox.seed(GraphTx(conn), at: 0) }
        return db
    }

    func testFrontendScenarioBuildsExpectedGraph() throws {
        let db = try makeDB()
        let rows = Fixtures.frontendRows()
        try db.writer.write { conn in
            let tx = GraphTx(conn)
            let stats = try OntologyApplier().apply(try Fixtures.patch(Fixtures.frontendPatchJSON), rows: rows, tx: tx, now: 2_000_000)
            XCTAssertEqual(stats.sessions, 1)
            XCTAssertEqual(stats.tasksCreated, 1)
            XCTAssertEqual(stats.resources, 4)
            XCTAssertEqual(stats.topics, 2)
            XCTAssertEqual(stats.problems, 1)
            XCTAssertEqual(stats.laterItems, 1)
            XCTAssertEqual(stats.uncoveredRows, 0)

            let counts = try tx.counts().nodesByLabel
            XCTAssertEqual(counts["Task"], 1)
            XCTAssertEqual(counts["Session"], 1)
            XCTAssertEqual(counts["Resource"], 4)
            XCTAssertEqual(counts["App"], 4)
            XCTAssertEqual(counts["Topic"], 2)
            XCTAssertEqual(counts["Problem"], 1)
            XCTAssertEqual(counts["LaterItem"], 1)
            XCTAssertEqual(counts["Project"], 1)

            let task = try XCTUnwrap(tx.nodes(label: "Task").first)
            XCTAssertEqual(task.title, "대시보드 카드 UI 구현")
            XCTAssertEqual(task.props["status"], "active")
            XCTAssertEqual(task.props["active_seconds"], 5280)
            let typeEdge = try XCTUnwrap(tx.edges(from: task.id, type: "INSTANCE_OF").first)
            XCTAssertEqual(try tx.node(id: typeEdge.dst)?.key, "코드작성")

            let session = try XCTUnwrap(tx.nodes(label: "Session").first)
            XCTAssertEqual(session.props["start"], .number(rows[0].start))
            XCTAssertEqual(session.props["end"], .number(rows[5].end))
            XCTAssertEqual(session.props["summary"], "TaskCard 컴포넌트 구현, key prop 경고 해결")
            XCTAssertEqual(try tx.edges(from: session.id, type: "PART_OF").first?.dst, task.id)

            // 같은 앱(Chrome) 세 행의 USED 는 한 엣지에 누적된다.
            let chrome = try XCTUnwrap(tx.node(label: "App", key: "com.google.Chrome"))
            let used = try XCTUnwrap(tx.edges(from: session.id, type: "USED").first { $0.dst == chrome.id })
            XCTAssertEqual(used.weight, Double(rows[1].dwell + rows[2].dwell + rows[4].dwell))

            let docs = try XCTUnwrap(tx.node(label: "Resource", key: "https://ui.shadcn.com/docs/components/card"))
            XCTAssertEqual(docs.subtype, "Documentation")
            let touched = try XCTUnwrap(tx.edges(from: session.id, type: "TOUCHED").first { $0.dst == docs.id })
            XCTAssertEqual(touched.weight, 780)
            let docType = try XCTUnwrap(tx.edges(from: docs.id, type: "INSTANCE_OF").first)
            XCTAssertEqual(try tx.node(id: docType.dst)?.key, "Documentation")

            let problem = try XCTUnwrap(tx.nodes(label: "Problem").first)
            XCTAssertEqual(problem.title, "React key prop warning")
            let so = try XCTUnwrap(tx.node(label: "Resource", key: "https://stackoverflow.com/questions/28329382"))
            XCTAssertEqual(try tx.edges(from: problem.id, type: "RESOLVED_BY").first?.dst, so.id)
            XCTAssertEqual(try tx.edges(from: session.id, type: "HIT").first?.dst, problem.id)

            let later = try XCTUnwrap(tx.nodes(label: "LaterItem").first)
            XCTAssertEqual(later.title, "카드 간격 16px로 조정")
            XCTAssertEqual(try tx.edges(from: later.id, type: "FOR").first?.dst, task.id)

            let code = try XCTUnwrap(tx.node(label: "Resource", key: "code:dashboard/TaskCard.tsx"))
            let project = try XCTUnwrap(tx.node(label: "Project", key: "project:dashboard"))
            XCTAssertEqual(try tx.edges(from: code.id, type: "BELONGS_TO").first?.dst, project.id)
            XCTAssertEqual(try tx.edges(from: task.id, type: "ON").first?.dst, project.id)
        }
    }

    func testFollowUpSegmentExtendsSessionWhenGapIsShort() throws {
        let db = try makeDB()
        let rows = Fixtures.frontendRows()
        try db.writer.write { conn in
            let tx = GraphTx(conn)
            let applier = OntologyApplier()
            _ = try applier.apply(try Fixtures.patch(Fixtures.frontendPatchJSON), rows: rows, tx: tx, now: 2_000_000)
            let taskKey = try XCTUnwrap(tx.nodes(label: "Task").first).key

            var next = rows[0]
            next.row = 1; next.start = rows[5].end + 100; next.end = next.start + 200; next.dwell = 200
            let followUp = try Fixtures.patch("""
            {"segments":[{"from_row":1,"to_row":1,"task":{"match":"existing","id":"\(taskKey)","title":"무시됨","task_type":"코드작성"},
              "summary":"카드 간격 조정","topics":["React"]}]}
            """)
            let stats = try applier.apply(followUp, rows: [next], tx: tx, now: 2_000_100)
            XCTAssertEqual(stats.sessions, 0)
            XCTAssertEqual(stats.sessionsExtended, 1)
            XCTAssertEqual(stats.tasksCreated, 0)

            let sessions = try tx.nodes(label: "Session")
            XCTAssertEqual(sessions.count, 1)
            XCTAssertEqual(sessions[0].props["end"], .number(next.end))
            XCTAssertEqual(sessions[0].props["active_seconds"], 5480)
            XCTAssertEqual(sessions[0].props["summary"], "카드 간격 조정")
            let task = try XCTUnwrap(tx.nodes(label: "Task").first)
            XCTAssertEqual(task.title, "대시보드 카드 UI 구현")          // 기존 제목 유지
            XCTAssertEqual(task.props["active_seconds"], 5480)

            // 간격이 5분 이상이면 새 세션
            var later = next
            later.start = next.end + 600; later.end = later.start + 60; later.dwell = 60
            let third = try applier.apply(followUp, rows: [later], tx: tx, now: 2_000_200)
            XCTAssertEqual(third.sessions, 1)
            XCTAssertEqual(try tx.nodes(label: "Session").count, 2)
        }
    }

    func testUnknownTaskTypeFallsBackAndTitleMatchReusesTask() throws {
        let db = try makeDB()
        let rows = Fixtures.frontendRows()
        try db.writer.write { conn in
            let tx = GraphTx(conn)
            let applier = OntologyApplier()
            let first = try Fixtures.patch("""
            {"segments":[{"from_row":1,"to_row":2,"task":{"match":"new","title":"논문 읽기","task_type":"없는종류"},"summary":"s","topics":[]}]}
            """)
            _ = try applier.apply(first, rows: rows, tx: tx, now: 1)
            let task = try XCTUnwrap(tx.nodes(label: "Task").first)
            let typeEdge = try XCTUnwrap(tx.edges(from: task.id, type: "INSTANCE_OF").first)
            XCTAssertEqual(try tx.node(id: typeEdge.dst)?.key, "기타")

            // id 없이 existing 이라고 하거나 같은 제목으로 new 라고 해도 같은 Task 를 쓴다.
            let second = try Fixtures.patch("""
            {"segments":[{"from_row":3,"to_row":4,"task":{"match":"existing","id":"t_nope","title":" 논문  읽기 ","task_type":"문헌조사"},"summary":"s","topics":[]}]}
            """)
            let stats = try applier.apply(second, rows: rows, tx: tx, now: 2)
            XCTAssertEqual(stats.tasksCreated, 0)
            XCTAssertEqual(try tx.nodes(label: "Task").count, 1)
        }
    }

    func testOutOfRangeAndOverlappingRowsAreHandled() throws {
        let db = try makeDB()
        let rows = Fixtures.frontendRows()
        try db.writer.write { conn in
            let tx = GraphTx(conn)
            let patch = try Fixtures.patch("""
            {"segments":[
              {"from_row":1,"to_row":3,"task":{"match":"new","title":"A","task_type":"코드작성"},"summary":"a","topics":[]},
              {"from_row":3,"to_row":4,"task":{"match":"new","title":"B","task_type":"코드작성"},"summary":"b","topics":[]},
              {"from_row":40,"to_row":50,"task":{"match":"new","title":"C","task_type":"코드작성"},"summary":"c","topics":[]}
            ]}
            """)
            let stats = try OntologyApplier().apply(patch, rows: rows, tx: tx, now: 1)
            XCTAssertEqual(stats.sessions, 2)               // C 는 범위 밖이라 무시
            XCTAssertEqual(stats.uncoveredRows, 2)          // 5, 6 행은 어느 세그먼트에도 없음
            XCTAssertEqual(try tx.nodes(label: "Task").map(\.title).sorted(), ["A", "B"])
            // 3행은 A 가 먼저 가져갔으므로 B 세션에는 4행(Terminal)만 들어간다.
            let b = try XCTUnwrap(tx.nodes(label: "Session").last)
            XCTAssertEqual(b.props["active_seconds"], .number(Double(rows[3].dwell)))
        }
    }

    func testTaskSwitchCreatesSwitchedToEdge() throws {
        let db = try makeDB()
        let rows = Fixtures.frontendRows()
        try db.writer.write { conn in
            let tx = GraphTx(conn)
            let patch = try Fixtures.patch("""
            {"segments":[
              {"from_row":1,"to_row":4,"task":{"match":"new","title":"카드 UI","task_type":"코드작성"},"summary":"a","topics":[]},
              {"from_row":5,"to_row":6,"task":{"match":"new","title":"유튜브 시청","task_type":"기타"},"summary":"b","topics":[],"switch_kind":"drift"}
            ]}
            """)
            _ = try OntologyApplier().apply(patch, rows: rows, tx: tx, now: 1)
            let sessions = try tx.nodes(label: "Session")
            XCTAssertEqual(sessions.count, 2)
            let edge = try XCTUnwrap(tx.edges(from: sessions[0].id, type: "SWITCHED_TO").first)
            XCTAssertEqual(edge.dst, sessions[1].id)
            XCTAssertEqual(edge.props["kind"], "drift")
        }
    }

    func testPatchDecodingIsLenient() throws {
        let patch = try Fixtures.patch("""
        {"segments":[{"from_row":"1","to_row":2.0,"task":{"title":"T"},"topics":null,"problems":[{"row":"2","message":"에러"}]}]}
        """)
        XCTAssertEqual(patch.segments[0].fromRow, 1)
        XCTAssertEqual(patch.segments[0].toRow, 2)
        XCTAssertEqual(patch.segments[0].task.match, "new")
        XCTAssertEqual(patch.segments[0].task.taskType, "기타")
        XCTAssertEqual(patch.segments[0].topics, [])
        XCTAssertEqual(patch.segments[0].problems?.first?.kind, "error")
        XCTAssertNil(patch.segments[0].switchKind)
    }

    func testLenientDecodeHandlesSmallModelQuirks() throws {
        // qwen3.5:2b 가 실제로 돌려준 형태: segments 래퍼 없음 + 중첩 값이 JSON 문자열
        let quirky = #"""
        {"from_row":"1","to_row":"3","task":"{\"id\": \"\", \"match\": \"new\", \"title\": \"선형대수 3주차 학습\", \"task_type\": \"복습\"}",
         "summary":"고유값 분해 학습","topics":"[\"선형대수학\", \"고유값\"]"}
        """#
        let patch = try XCTUnwrap(OntologyPatch.decodeLenient(from: Data(quirky.utf8)))
        XCTAssertEqual(patch.segments.count, 1)
        XCTAssertEqual(patch.segments[0].fromRow, 1)
        XCTAssertEqual(patch.segments[0].toRow, 3)
        XCTAssertEqual(patch.segments[0].task.title, "선형대수 3주차 학습")
        XCTAssertEqual(patch.segments[0].task.taskType, "복습")
        XCTAssertEqual(patch.segments[0].topics, ["선형대수학", "고유값"])

        let array = #"[{"from_row":1,"to_row":2,"task":{"title":"A"},"topics":[]}]"#
        XCTAssertEqual(OntologyPatch.decodeLenient(from: Data(array.utf8))?.segments.count, 1)
        let normal = try XCTUnwrap(OntologyPatch.decodeLenient(from: Data(Fixtures.frontendPatchJSON.utf8)))
        XCTAssertEqual(normal, try Fixtures.patch(Fixtures.frontendPatchJSON))
        XCTAssertNil(OntologyPatch.decodeLenient(from: Data("not json".utf8)))
    }

    func testPromptContainsRowsTasksAndTypes() {
        let rows = Fixtures.frontendRows()
        let digest = TaskDigest(id: "t_ab12", title: "대시보드 카드 UI 구현", taskType: "코드작성", topics: ["React"],
                                recentResources: ["TaskCard.tsx"], lastActive: 1)
        let prompt = OntologyPrompt.build(rows: rows, openTasks: [digest], now: 1_005_280)
        XCTAssertTrue(prompt.system.contains("record_activity"))
        XCTAssertTrue(prompt.user.contains("id=t_ab12"))
        XCTAssertTrue(prompt.user.contains("코드작성"))
        XCTAssertTrue(prompt.user.contains("https://ui.shadcn.com/docs/components/card"))
        XCTAssertTrue(prompt.user.contains("| 540s |"))
        XCTAssertEqual(OntologySchema.tool.name, "record_activity")
    }
}

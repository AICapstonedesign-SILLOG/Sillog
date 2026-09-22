import XCTest
import GRDB
@testable import WorkGraphCore

/// 시드 → 배치(가짜 LLM) → 그래프까지 한 번에 도는지 확인하는 통합 테스트.
final class DemoPipelineTests: XCTestCase {
    func testWholeDayBecomesOneSharedGraph() async throws {
        let db = try WGDatabase.inMemory()
        try await db.writer.write { try TBox.seed(GraphTx($0), at: 0) }
        let dayStart = 1_790_000_000.0
        let seeded = try DemoScenarios.seed(into: EventStore(db), dayStart: dayStart, home: "/Users/me")
        let batcher = OntologyBatcher(db: db, llm: DemoLLM(), home: "/Users/me", fileExists: { _ in false },
                                      clock: { dayStart + 20 * 3600 })
        var rounds = 0
        while rounds < 40, case .ok = await batcher.runIfDue(force: true) { rounds += 1 }
        XCTAssertGreaterThan(rounds, 3)
        XCTAssertTrue(try EventStore(db).unprocessed(limit: 10).isEmpty, "\(seeded)개 행이 모두 처리되어야 함")

        try await db.writer.read { conn in
            let tx = GraphTx(conn)
            XCTAssertEqual(Set(try tx.nodes(label: "Task").map(\.title)),
                           ["AI기초수학 3주차 복습", "캡스톤 중간보고서 작성", "대시보드 카드 UI 구현", "대시보드 필터 UI 구현", "유튜브 시청"])

            // 같은 문서를 두 업무가 봤어도 노드는 하나 — 업무끼리 노드를 공유할 때 그래프의 값이 생긴다.
            let card = try XCTUnwrap(tx.node(label: "Resource", key: "https://ui.shadcn.com/docs/components/card"))
            let tasks = try Set(tx.edges(to: card.id, type: "TOUCHED").compactMap { try tx.edges(from: $0.src, type: "PART_OF").first?.dst })
            XCTAssertEqual(tasks.count, 2)
            let react = try XCTUnwrap(tx.node(label: "Topic", key: "react"))
            XCTAssertEqual(try tx.edges(to: react.id, type: "ABOUT").count, 2)

            // localhost 는 쿼리가 달라도 한 노드
            XCTAssertNotNil(try tx.node(label: "Resource", key: "local:3000/dashboard"))
            XCTAssertEqual(try tx.nodes(label: "Resource").filter { $0.key.hasPrefix("local:") }.count, 1)

            // 업무 5개에 세션 6개: 카드 UI 업무만 유튜브로 끊겨 두 세션이 된다. 배치 경계는 세션을 쪼개지 않는다.
            XCTAssertEqual(try tx.nodes(label: "Session").count, 6)

            let problems = try tx.nodes(label: "Problem")
            XCTAssertEqual(problems.count, 2)
            for problem in problems { XCTAssertEqual(try tx.edges(from: problem.id, type: "RESOLVED_BY").count, 1, problem.title) }
            XCTAssertEqual(try tx.nodes(label: "LaterItem").count, 2)

            let switches = try Row.fetchAll(conn, sql: "SELECT props FROM edges WHERE type = 'SWITCHED_TO'").map { JSONValue.decodeObject($0["props"] as String?) }
            XCTAssertTrue(switches.contains { $0["kind"] == "drift" })

            // 작업 시간 합은 시나리오 길이 합(70+51+86+32 = 239분)과 같아야 한다 — 시간이 새거나 두 번 세이지 않는다.
            // 시나리오마다 마지막 행은 다음 행이 없어 간격 상한(90초)까지 잡히므로 최대 30초 × 4 가 더해진다.
            let total = try tx.nodes(label: "Task").reduce(0.0) { $0 + ($1.props["active_seconds"]?.doubleValue ?? 0) }
            XCTAssertEqual(total / 60, 239, accuracy: 2.5)
        }
    }
}

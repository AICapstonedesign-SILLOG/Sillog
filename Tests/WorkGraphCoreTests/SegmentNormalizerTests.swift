import XCTest
@testable import WorkGraphCore

final class SegmentNormalizerTests: XCTestCase {
    /// (분, 앱, uri) 목록으로 행을 만든다. 행 번호는 1부터.
    private func rows(_ specs: [(minutes: Double, app: String, uri: String?)]) -> [ActivityRow] {
        var start = 1_000_000.0
        return specs.enumerated().map { index, spec in
            defer { start += spec.minutes * 60 }
            return ActivityRow(row: index + 1, start: start, end: start + spec.minutes * 60, dwell: Int(spec.minutes * 60),
                               app: spec.app, appBundle: "bundle.\(spec.app.lowercased())", title: spec.app, uri: spec.uri,
                               type: spec.uri == nil ? nil : "WebPage", projectKey: nil, projectTitle: nil, snippet: nil,
                               observationIds: [Int64(index + 1)])
        }
    }

    private func patch(_ segments: String) throws -> OntologyPatch { try Fixtures.patch("{\"segments\":[\(segments)]}") }

    private func seg(_ from: Int, _ to: Int, match: String = "new", id: String? = nil, title: String, type: String,
                     topics: [String] = [], summary: String = "요약", switchKind: String? = nil) -> String {
        let idPart = id.map { "\"id\":\"\($0)\"," } ?? ""
        let switchPart = switchKind.map { ",\"switch_kind\":\"\($0)\"" } ?? ""
        let topicList = topics.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"from_row\":\(from),\"to_row\":\(to),\"task\":{\"match\":\"\(match)\",\(idPart)\"title\":\"\(title)\",\"task_type\":\"\(type)\"},\"summary\":\"\(summary)\",\"topics\":[\(topicList)]\(switchPart)}"
    }

    private let discordTask = TaskDigest(id: "t_chat", title: "캡스톤디자인 팀 채널 확인", taskType: "메신저대응", topics: ["캡스톤디자인"],
                                         recentResources: [], lastActive: 0, resourceKeys: [], apps: ["bundle.discord"])
    private let researchTask = TaskDigest(id: "t_sp", title: "screenpipe 오픈소스 조사", taskType: "문헌조사", topics: ["screenpipe"],
                                          recentResources: ["screenpipe"], lastActive: 0,
                                          resourceKeys: ["https://github.com/screenpipe/screenpipe"], apps: ["bundle.chrome"])

    func testShortNewSegmentIsRoutedToSimilarOpenTask() throws {
        let activity = rows([(1, "Discord", nil)])
        let result = SegmentNormalizer().normalize(try patch(seg(1, 1, title: "팀 Discord 메시지 확인", type: "메신저대응")),
                                                   rows: activity, openTasks: [discordTask, researchTask])
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].task.match, "existing")
        XCTAssertEqual(result.segments[0].task.id, "t_chat")
    }

    func testShortSegmentSharingResourcesReusesTask() throws {
        let activity = rows([(2, "Chrome", "https://github.com/screenpipe/screenpipe")])
        let result = SegmentNormalizer().normalize(try patch(seg(1, 1, title: "screenpipe 기능 조사", type: "문헌조사", topics: ["screenpipe"])),
                                                   rows: activity, openTasks: [discordTask, researchTask])
        XCTAssertEqual(result.segments[0].task.id, "t_sp")
    }

    func testShortInterruptionBetweenSameTaskIsAbsorbedAndMerged() throws {
        let activity = rows([(10, "Cursor", "code:dash/A.tsx"), (1, "Mail", nil), (8, "Cursor", "code:dash/A.tsx")])
        let input = try patch([
            seg(1, 1, title: "대시보드 카드 UI 구현", type: "코드작성", topics: ["React"], summary: "카드 구현"),
            seg(2, 2, title: "메일 확인", type: "메신저대응", summary: "메일 잠깐 확인"),
            seg(3, 3, title: "대시보드 카드 UI 구현", type: "코드작성", topics: ["shadcn/ui"], summary: "이어서 구현"),
        ].joined(separator: ","))
        let result = SegmentNormalizer().normalize(input, rows: activity, openTasks: [])
        XCTAssertEqual(result.segments.count, 1, "끼어든 1분은 앞뒤 업무에 흡수되고 세 구간이 하나로 합쳐진다")
        XCTAssertEqual(result.segments[0].fromRow, 1)
        XCTAssertEqual(result.segments[0].toRow, 3)
        XCTAssertEqual(result.segments[0].task.title, "대시보드 카드 UI 구현")
        XCTAssertEqual(result.segments[0].summary, "카드 구현")                     // 가장 긴 구간의 요약
        XCTAssertEqual(result.segments[0].topics, ["React", "shadcn/ui"])
    }

    func testUnrelatedShortSegmentsGoToCatchAllTasks() throws {
        let activity = rows([(10, "Cursor", "code:dash/A.tsx"), (1, "Chrome", "https://openai.com/news"), (2, "Chrome", "https://youtube.com/watch?v=x")])
        let input = try patch([
            seg(1, 1, title: "대시보드 카드 UI 구현", type: "코드작성"),
            seg(2, 2, title: "OpenAI 기술 정보 확인", type: "문헌조사", topics: ["OpenAI"]),
            seg(3, 3, title: "연습 영상 시청", type: "기타", switchKind: "drift"),
        ].joined(separator: ","))
        let result = SegmentNormalizer().normalize(input, rows: activity, openTasks: [])
        XCTAssertEqual(result.segments.map(\.task.title), ["대시보드 카드 UI 구현", SegmentNormalizer.catchAllTitle, SegmentNormalizer.driftTitle])
        XCTAssertEqual(result.segments[1].task.taskType, "기타")
        XCTAssertEqual(result.segments[1].topics, [], "자잘한 확인에는 주제를 붙이지 않는다")
        XCTAssertEqual(result.segments[2].switchKind, "drift")
    }

    func testLongNewSegmentsAndExistingMatchesAreLeftAlone() throws {
        let activity = rows([(4, "Chrome", "https://a.dev"), (1, "Discord", nil)])
        let input = try patch([
            seg(1, 1, title: "시장 조사", type: "시장조사"),
            seg(2, 2, match: "existing", id: "t_chat", title: "무시됨", type: "메신저대응"),
        ].joined(separator: ","))
        let result = SegmentNormalizer().normalize(input, rows: activity, openTasks: [discordTask])
        XCTAssertEqual(result, input)
    }

    func testShortSegmentCanJoinTaskCreatedEarlierInTheSameBatch() throws {
        let activity = rows([(12, "Chrome", "https://docs.a.dev/guide"), (6, "Cursor", "code:x/B.swift"), (2, "Chrome", "https://docs.a.dev/guide")])
        let input = try patch([
            seg(1, 1, title: "A 라이브러리 문서 조사", type: "문헌조사", topics: ["A"]),
            seg(2, 2, title: "B 기능 구현", type: "코드작성"),
            seg(3, 3, title: "A 문서 다시 확인", type: "문헌조사", topics: ["A"]),
        ].joined(separator: ","))
        let result = SegmentNormalizer().normalize(input, rows: activity, openTasks: [])
        XCTAssertEqual(result.segments.map(\.task.title), ["A 라이브러리 문서 조사", "B 기능 구현", "A 라이브러리 문서 조사"])
    }

    func testLoneShortSegmentIsKeptUnlessItMatchesAnOpenTask() throws {
        // 배치 전체가 짧은 구간 하나: 쪼개짐이 아니라 막 시작한 업무일 수 있으니 공용 업무로 보내지 않는다.
        let activity = rows([(2, "Cursor", "code:dash/A.tsx")])
        let lone = try patch(seg(1, 1, title: "대시보드 카드 UI 구현", type: "코드작성"))
        XCTAssertEqual(SegmentNormalizer().normalize(lone, rows: activity, openTasks: [discordTask]), lone)
        // 그래도 비슷한 열린 업무가 있으면 그쪽으로 돌린다.
        let chat = rows([(1, "Discord", nil)])
        let result = SegmentNormalizer().normalize(try patch(seg(1, 1, title: "팀 채널 확인", type: "메신저대응")), rows: chat, openTasks: [discordTask])
        XCTAssertEqual(result.segments[0].task.id, "t_chat")
    }

    func testFragmentedHourCollapsesToAFewTasks() throws {
        // 실제로 겪은 패턴: 50분 동안 메신저 확인 4번, 같은 조사 2번, 1분짜리 확인 여러 번이 전부 새 업무로 나왔다.
        let activity = rows([(2, "Discord", nil), (1, "Chrome", "https://github.com/screenpipe/screenpipe"), (2, "Chrome", "https://github.com/screenpipe/screenpipe/issues"),
                             (1, "Discord", nil), (1, "Chrome", "https://openai.com/news"), (18, "Code", "code:cap/App.swift"), (1, "Discord", nil), (2, "Discord", nil)])
        let input = try patch([
            seg(1, 1, title: "팀 Discord 메시지 확인", type: "메신저대응"),
            seg(2, 2, title: "screenpipe 기능 조사", type: "문헌조사", topics: ["screenpipe"]),
            seg(3, 3, title: "screenpipe 오픈소스 조사", type: "문헌조사", topics: ["screenpipe"]),
            seg(4, 4, title: "캡스톤디자인 팀 채널 확인", type: "메신저대응"),
            seg(5, 5, title: "OpenAI 기술 정보 확인", type: "문헌조사"),
            seg(6, 6, title: "캡스톤 코드 분석", type: "코드작성"),
            seg(7, 7, title: "팀 채널 및 AI 도구 확인", type: "메신저대응"),
            seg(8, 8, title: "팀 채널 확인", type: "메신저대응"),
        ].joined(separator: ","))
        let result = SegmentNormalizer().normalize(input, rows: activity, openTasks: [])
        let titles = Set(result.segments.map(\.task.title))
        XCTAssertLessThanOrEqual(titles.count, 4, "8개 업무가 4개 이하로 줄어야 한다: \(titles)")
        XCTAssertTrue(titles.contains("캡스톤 코드 분석"))
    }
}

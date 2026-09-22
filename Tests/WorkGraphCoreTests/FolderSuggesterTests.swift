import XCTest
@testable import WorkGraphCore

final class FolderSuggesterTests: XCTestCase {
    private var root: URL!
    private var db: WGDatabase!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wg-suggest-\(UUID().uuidString)")
        for (path, files) in [("Desktop/5-1/ai 기초수학", ["week1.pdf", "week2.pdf"]), ("Desktop/5-1/자료구조", ["ch1.pdf"]), ("Downloads", [])] {
            let dir = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for file in files { try Data("x".utf8).write(to: dir.appendingPathComponent(file)) }
        }
        db = try WGDatabase.inMemory()
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private var index: FolderIndex { FolderIndex.scan(roots: [root.appendingPathComponent("Desktop").path], home: root.path) }

    private func download(_ name: String) throws -> String {
        let path = root.appendingPathComponent("Downloads/\(name)").path
        try Data("pdf".utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    func testLLMPicksAmongRealCandidatesAndSuggestionIsStored() async throws {
        let mathFolder = root.appendingPathComponent("Desktop/5-1/ai 기초수학").path
        let llm = StubLLM([.success(#"{"folder":"\#(mathFolder)","confidence":0.88,"reason":"AI기초수학 강의자료라 같은 과목 폴더"}"#)])
        let suggester = FolderSuggester(db: db, llm: llm, home: root.path, minConfidence: 0.6)
        let path = try download("week3_linear_algebra.pdf")
        let suggestion = try await suggester.suggest(filePath: path, originURL: "https://eclass.example.ac.kr/course/1234/file/99", index: index,
                                                     context: FolderSuggester.Context(recentTitles: ["AI기초수학 3주차 강의자료 - e-Class"],
                                                                                      screenText: "AI기초수학 (월 3,4교시) 3주차 강의자료 벡터공간과 내적.pdf 다운로드", openTasks: [], now: 1_000))
        let result = try XCTUnwrap(suggestion)
        XCTAssertEqual(result.suggestedFolder, mathFolder)
        XCTAssertEqual(result.status, "pending")
        XCTAssertEqual(result.reason, "AI기초수학 강의자료라 같은 과목 폴더")
        XCTAssertTrue(llm.lastUser.contains("week3_linear_algebra.pdf"))
        XCTAssertTrue(llm.lastUser.contains("eclass.example.ac.kr"))
        XCTAssertTrue(llm.lastUser.contains("~/Desktop/5-1/ai 기초수학"))
        XCTAssertTrue(llm.lastUser.contains("week1.pdf"))
        XCTAssertTrue(llm.lastUser.contains("TEXT ON SCREEN WHEN THE FILE ARRIVED: AI기초수학 (월 3,4교시)"))
        XCTAssertEqual(try FileSuggestionStore(db).pending().count, 1)
    }

    func testLowConfidenceOrNoneMeansNoSuggestion() async throws {
        let llm = StubLLM([.success(#"{"folder":"","confidence":0.2,"reason":"모르겠음"}"#)])
        let suggester = FolderSuggester(db: db, llm: llm, home: root.path)
        let suggestion = try await suggester.suggest(filePath: try download("random.bin"), originURL: nil, index: index,
                                                     context: FolderSuggester.Context(recentTitles: [], openTasks: [], now: 1_000))
        XCTAssertNil(suggestion)
        XCTAssertTrue(try FileSuggestionStore(db).pending().isEmpty)
    }

    func testLLMCannotInventAFolder() async throws {
        let llm = StubLLM([.success(#"{"folder":"/nowhere/made-up","confidence":0.95,"reason":"x"}"#)])
        let suggester = FolderSuggester(db: db, llm: llm, home: root.path)
        let suggestion = try await suggester.suggest(filePath: try download("a.pdf"), originURL: nil, index: index,
                                                     context: FolderSuggester.Context(recentTitles: ["자료구조"], openTasks: [], now: 1_000))
        XCTAssertNil(suggestion, "후보에 없는 경로는 버린다")
    }

    func testAcceptMovesFileLearnsAndCanUndo() async throws {
        let mathFolder = root.appendingPathComponent("Desktop/5-1/ai 기초수학").path
        let llm = StubLLM([.success(#"{"folder":"\#(mathFolder)","confidence":0.9,"reason":"r"}"#),
                           .success(#"{"folder":"\#(mathFolder)","confidence":0.9,"reason":"r2"}"#)])
        let suggester = FolderSuggester(db: db, llm: llm, home: root.path)
        let path = try download("week3.pdf")
        let suggestionMaybe = try await suggester.suggest(filePath: path, originURL: "https://eclass.example.ac.kr/course/1234/file/99", index: index,
                                                                   context: FolderSuggester.Context(recentTitles: [], openTasks: [], now: 1_000))
        let suggestion = try XCTUnwrap(suggestionMaybe)
        let moved = try suggester.accept(id: suggestion.id!, now: 1_100)
        XCTAssertEqual(moved, mathFolder + "/week3.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertEqual(try FileSuggestionStore(db).suggestion(id: suggestion.id!)?.status, "moved")

        // 같은 페이지에서 받은 다음 파일도 LLM 이 새로 판단한다. 전에 옮긴 곳은 힌트로만 들어간다.
        let againMaybe = try await suggester.suggest(filePath: try download("week4.pdf"), originURL: "https://eclass.example.ac.kr/course/1234/file/100", index: index,
                                                              context: FolderSuggester.Context(recentTitles: [], openTasks: [], now: 2_000))
        let again = try XCTUnwrap(againMaybe)
        XCTAssertEqual(again.source, "llm")
        XCTAssertEqual(llm.calls, 2)
        XCTAssertTrue(llm.lastUser.contains("EARLIER THE USER MOVED a file from the same page TO: ~/Desktop/5-1/ai 기초수학 (hint, not a rule)"), llm.lastUser)

        // 이름이 겹치면 덮어쓰지 않고 번호를 붙인다
        _ = try download("week3.pdf")
        let clash = try suggester.move(from: root.appendingPathComponent("Downloads/week3.pdf").path, to: mathFolder)
        XCTAssertEqual((clash as NSString).lastPathComponent, "week3 (2).pdf")

        // 되돌리기
        let restored = try suggester.undo(id: suggestion.id!, now: 1_200)
        XCTAssertEqual(restored, path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertEqual(try FileSuggestionStore(db).suggestion(id: suggestion.id!)?.status, "undone")
    }

    func testTaskRuleIsOnlyAHintToTheLLM() async throws {
        let mathFolder = root.appendingPathComponent("Desktop/5-1/ai 기초수학").path
        let dsFolder = root.appendingPathComponent("Desktop/5-1/자료구조").path
        let llm = StubLLM([.success(#"{"folder":"\#(mathFolder)","confidence":0.9,"reason":"r"}"#),
                           .success(#"{"folder":"\#(dsFolder)","confidence":0.8,"reason":"다른 과목"}"#)])
        let suggester = FolderSuggester(db: db, llm: llm, home: root.path)
        let firstMaybe = try await suggester.suggest(filePath: try download("a.pdf"), originURL: nil, index: index,
                                                              context: FolderSuggester.Context(recentTitles: [], openTasks: [], currentTaskKey: "t_1", now: 1_000))
        let first = try XCTUnwrap(firstMaybe)
        _ = try suggester.accept(id: first.id!, now: 1_100)
        // 같은 업무 중 받은 다음 파일: 규칙으로 바로 정하지 않고 LLM 이 힌트를 보고 고른다
        let secondMaybe = try await suggester.suggest(filePath: try download("b.pdf"), originURL: nil, index: index,
                                                               context: FolderSuggester.Context(recentTitles: [], openTasks: [], currentTaskKey: "t_1", now: 2_000))
        let second = try XCTUnwrap(secondMaybe)
        XCTAssertEqual(llm.calls, 2)
        XCTAssertEqual(second.source, "llm")
        XCTAssertEqual(second.suggestedFolder, dsFolder)
        XCTAssertTrue(llm.lastUser.contains("EARLIER THE USER MOVED a file downloaded while working on the same task TO: ~/Desktop/5-1/ai 기초수학"))
    }

    func testUndoneFileIsNotSuggestedAgainRightAway() async throws {
        let mathFolder = root.appendingPathComponent("Desktop/5-1/ai 기초수학").path
        let llm = StubLLM([.success(#"{"folder":"\#(mathFolder)","confidence":0.9,"reason":"r"}"#),
                           .success(#"{"folder":"\#(mathFolder)","confidence":0.9,"reason":"r"}"#)])
        let suggester = FolderSuggester(db: db, llm: llm, home: root.path)
        let path = try download("x.pdf")
        let firstMaybe = try await suggester.suggest(filePath: path, originURL: nil, index: index, context: FolderSuggester.Context(recentTitles: [], openTasks: [], now: 1_000))
        let first = try XCTUnwrap(firstMaybe)
        _ = try suggester.accept(id: first.id!, now: 1_100)
        _ = try suggester.undo(id: first.id!, now: 1_200)
        // 되돌린 직후 (다운로드 폴더에 다시 나타남): 제안하지 않는다
        let soon = try await suggester.suggest(filePath: path, originURL: nil, index: index, context: FolderSuggester.Context(recentTitles: [], openTasks: [], now: 1_300))
        XCTAssertNil(soon)
        XCTAssertEqual(llm.calls, 1)
        // 한참 뒤에 다시 받으면 새로 판단
        let later = try await suggester.suggest(filePath: path, originURL: nil, index: index, context: FolderSuggester.Context(recentTitles: [], openTasks: [], now: 5_000))
        XCTAssertNotNil(later)
    }

    func testPendingSuggestionClosesWhenTheFileIsGone() async throws {
        let mathFolder = root.appendingPathComponent("Desktop/5-1/ai 기초수학").path
        let llm = StubLLM([.success(#"{"folder":"\#(mathFolder)","confidence":0.9,"reason":"r"}"#)])
        let suggester = FolderSuggester(db: db, llm: llm, home: root.path)
        let path = try download("y.pdf")
        let pendingMaybe = try await suggester.suggest(filePath: path, originURL: nil, index: index, context: FolderSuggester.Context(recentTitles: [], openTasks: [], now: 1_000))
        let pending = try XCTUnwrap(pendingMaybe)
        try FileManager.default.removeItem(atPath: path)                 // 사용자가 Finder 에서 직접 옮김
        let closed = try FileSuggestionStore(db).closeGone(now: 1_500, fileExists: { FileManager.default.fileExists(atPath: $0) })
        XCTAssertEqual(closed, [pending.id!])
        XCTAssertEqual(try FileSuggestionStore(db).suggestion(id: pending.id!)?.status, "gone")
        XCTAssertTrue(try FileSuggestionStore(db).pending().isEmpty)
    }

    func testRejectWithChosenFolderTeachesThatFolder() async throws {
        let mathFolder = root.appendingPathComponent("Desktop/5-1/ai 기초수학").path
        let dsFolder = root.appendingPathComponent("Desktop/5-1/자료구조").path
        let llm = StubLLM([.success(#"{"folder":"\#(mathFolder)","confidence":0.9,"reason":"r"}"#),
                           .success(#"{"folder":"\#(dsFolder)","confidence":0.9,"reason":"r"}"#)])
        let suggester = FolderSuggester(db: db, llm: llm, home: root.path)
        let suggestionMaybe = try await suggester.suggest(filePath: try download("ch2.pdf"), originURL: "https://eclass.example.ac.kr/course/777/file/1", index: index,
                                                                   context: FolderSuggester.Context(recentTitles: [], openTasks: [], now: 1_000))
        let suggestion = try XCTUnwrap(suggestionMaybe)
        let moved = try suggester.rejectAndMove(id: suggestion.id!, to: dsFolder, now: 1_100)
        XCTAssertEqual((moved as NSString).deletingLastPathComponent, dsFolder)
        XCTAssertEqual(try FileSuggestionStore(db).suggestion(id: suggestion.id!)?.status, "moved")
        XCTAssertEqual(try FileSuggestionStore(db).suggestion(id: suggestion.id!)?.movedTo, moved)
        let nextMaybe = try await suggester.suggest(filePath: try download("ch3.pdf"), originURL: "https://eclass.example.ac.kr/course/777/file/2", index: index,
                                                             context: FolderSuggester.Context(recentTitles: [], openTasks: [], now: 2_000))
        let next = try XCTUnwrap(nextMaybe)
        XCTAssertEqual(next.suggestedFolder, dsFolder)
        XCTAssertTrue(llm.lastUser.contains("EARLIER THE USER MOVED a file from the same page TO: ~/Desktop/5-1/자료구조"), "사용자가 고른 폴더가 힌트가 된다")
    }
}

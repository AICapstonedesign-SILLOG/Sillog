import XCTest
@testable import WorkGraphCore

final class FileSuggestionCopyTests: XCTestCase {
    func testBodyMatchesFigmaExample() {
        XCTAssertEqual(FileSuggestionCopy.title, "파일을 정리할까요?")
        XCTAssertEqual(FileSuggestionCopy.body(fileName: "통계학_수업자료.pdf", folder: "/Users/me/Documents/통계학", home: "/Users/me"),
                       "통계학_수업자료.pdf을 문서 / 통계학 폴더로 옮겨 보세요.")
    }

    func testParticleFollowsLastHangulSyllable() {
        XCTAssertEqual(FileSuggestionCopy.objectParticle("보고서"), "를")
        XCTAssertEqual(FileSuggestionCopy.objectParticle("논문"), "을")
        XCTAssertEqual(FileSuggestionCopy.objectParticle("report.pdf"), "을")
        XCTAssertEqual(FileSuggestionCopy.objectParticle(""), "을")
    }

    func testFolderLabel() {
        let home = "/Users/me"
        XCTAssertEqual(FileSuggestionCopy.folderLabel("/Users/me/Downloads", home: home), "다운로드")
        XCTAssertEqual(FileSuggestionCopy.folderLabel("/Users/me/Documents/통계학/", home: home), "문서 / 통계학")
        XCTAssertEqual(FileSuggestionCopy.folderLabel("/Users/me/프로젝트/캡스톤", home: home), "프로젝트 / 캡스톤")
        XCTAssertEqual(FileSuggestionCopy.folderLabel("/Users/me", home: home), "홈")
        XCTAssertEqual(FileSuggestionCopy.folderLabel("/Volumes/USB/자료", home: home), "Volumes / USB / 자료")
        XCTAssertEqual(FileSuggestionCopy.folderLabel("/Users/meow/a", home: home), "Users / meow / a", "이름만 홈으로 시작하는 다른 폴더")
    }
}

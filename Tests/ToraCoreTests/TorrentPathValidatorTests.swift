import XCTest
@testable import ToraCore

final class TorrentPathValidatorTests: XCTestCase {
    private let downloadDirectory = URL(fileURLWithPath: "/Users/example/Downloads/Tora", isDirectory: true)

    func testAllowsSimpleRelativePath() throws {
        XCTAssertNoThrow(try TorrentPathValidator.validate("folder/file.txt", inside: downloadDirectory))
    }

    func testRejectsParentDirectoryTraversal() {
        XCTAssertThrowsError(try TorrentPathValidator.validate("../evil.txt", inside: downloadDirectory))
        XCTAssertThrowsError(try TorrentPathValidator.validate("folder/../../evil.txt", inside: downloadDirectory))
    }

    func testRejectsAbsolutePath() {
        XCTAssertThrowsError(try TorrentPathValidator.validate("/Users/example/.ssh/id_rsa", inside: downloadDirectory))
    }

    func testRejectsHomeRelativePath() {
        XCTAssertThrowsError(try TorrentPathValidator.validate("~/Desktop/evil.txt", inside: downloadDirectory))
    }

    func testRejectsWindowsStyleTraversalAndDrivePaths() {
        XCTAssertThrowsError(try TorrentPathValidator.validate("folder\\..\\evil.txt", inside: downloadDirectory))
        XCTAssertThrowsError(try TorrentPathValidator.validate("C:\\Users\\example\\evil.txt", inside: downloadDirectory))
    }

    func testRejectsEmptyPathComponents() {
        XCTAssertThrowsError(try TorrentPathValidator.validate("folder//file.txt", inside: downloadDirectory))
        XCTAssertThrowsError(try TorrentPathValidator.validate("folder/", inside: downloadDirectory))
    }

    func testRejectsControlCharacters() {
        XCTAssertThrowsError(try TorrentPathValidator.validate("folder/file\u{0000}.txt", inside: downloadDirectory))
    }
}

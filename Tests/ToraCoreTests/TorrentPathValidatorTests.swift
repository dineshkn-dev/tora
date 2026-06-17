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

    func testRejectsExistingSymlinkPathComponent() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let link = temporaryRoot.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
            try? FileManager.default.removeItem(at: outside)
        }

        XCTAssertThrowsError(try TorrentPathValidator.validate("linked/file.txt", inside: temporaryRoot))
    }

    func testRejectsExistingFinalSymlinkPathComponent() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        let link = temporaryRoot.appendingPathComponent("file.txt", isDirectory: false)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try Data().write(to: outside)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
            try? FileManager.default.removeItem(at: outside)
        }

        XCTAssertThrowsError(try TorrentPathValidator.validate("file.txt", inside: temporaryRoot))
    }
}

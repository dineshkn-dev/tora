import XCTest
@testable import ToraCore

final class DownloadPathPolicyTests: XCTestCase {
    func testRejectsDownloadDirectoryOutsideAllowedRoot() throws {
        let root = URL(fileURLWithPath: "/Users/example/Downloads/Tora", isDirectory: true)
        let policy = DownloadPathPolicy(allowedRoot: root)

        XCTAssertNoThrow(try policy.validateDownloadDirectory(root))
        XCTAssertNoThrow(try policy.validateDownloadDirectory(root.appendingPathComponent("Album", isDirectory: true)))
        XCTAssertThrowsError(try policy.validateDownloadDirectory(URL(fileURLWithPath: "/Users/example/Downloads/Tora-Other", isDirectory: true)))
        XCTAssertThrowsError(try policy.validateDownloadDirectory(URL(fileURLWithPath: "/Users/example/Documents", isDirectory: true)))
    }

    func testRejectsSymlinkDownloadDirectory() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = temporaryRoot.appendingPathComponent("target", isDirectory: true)
        let link = temporaryRoot.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let policy = DownloadPathPolicy(allowedRoot: temporaryRoot)

        XCTAssertThrowsError(try policy.validateDownloadDirectory(link))
    }

    func testRejectsIntermediateSymlinkDownloadDirectory() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let link = temporaryRoot.appendingPathComponent("link", isDirectory: true)
        let candidate = link.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
            try? FileManager.default.removeItem(at: target)
        }

        let policy = DownloadPathPolicy(allowedRoot: temporaryRoot)

        XCTAssertThrowsError(try policy.validateDownloadDirectory(candidate))
    }
}

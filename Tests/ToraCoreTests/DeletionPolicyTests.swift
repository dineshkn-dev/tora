import XCTest
@testable import ToraCore

final class DeletionPolicyTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Users/example/Downloads/Tora", isDirectory: true)

    func testAllowsRootAndChildren() throws {
        let policy = DeletionPolicy(allowedRoot: root)

        XCTAssertNoThrow(try policy.validateDeletionRoot(root))
        XCTAssertNoThrow(try policy.validateDeletionRoot(root.appendingPathComponent("torrent", isDirectory: true)))
    }

    func testRejectsSiblingPrefix() throws {
        let policy = DeletionPolicy(allowedRoot: root)

        XCTAssertThrowsError(try policy.validateDeletionRoot(URL(fileURLWithPath: "/Users/example/Downloads/Tora-Other", isDirectory: true)))
    }

    func testRejectsOutsideRoot() throws {
        let policy = DeletionPolicy(allowedRoot: root)

        XCTAssertThrowsError(try policy.validateDeletionRoot(URL(fileURLWithPath: "/Users/example/Documents", isDirectory: true)))
    }

    func testRejectsSymlinkDeletionTarget() throws {
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

        let policy = DeletionPolicy(allowedRoot: temporaryRoot)

        XCTAssertThrowsError(try policy.validateDeletionRoot(link.appendingPathComponent("nested", isDirectory: true)))
    }
}

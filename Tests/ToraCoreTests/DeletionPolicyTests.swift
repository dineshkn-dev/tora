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
}

import Foundation

public struct SessionDataStore: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var sessionStateURL: URL {
        directory.appendingPathComponent("session_state", isDirectory: false).appendingPathExtension("dat")
    }
}

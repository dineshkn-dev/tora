import Foundation
import ToraCore

public struct ResumeDataStore: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(for id: TorrentID) -> URL {
        directory.appendingPathComponent(id.rawValue, isDirectory: false).appendingPathExtension("fastresume")
    }
}

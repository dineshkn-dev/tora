import Foundation

public struct TorrentRecord: Codable, Equatable, Sendable {
    public let id: TorrentID
    public let name: String
    public let source: TorrentSource
    public let downloadDirectory: URL
    public let selectedFileIndexes: Set<Int>
    public let createdAt: Date

    public init(
        id: TorrentID,
        name: String,
        source: TorrentSource,
        downloadDirectory: URL,
        selectedFileIndexes: Set<Int>,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.downloadDirectory = downloadDirectory
        self.selectedFileIndexes = selectedFileIndexes
        self.createdAt = createdAt
    }
}

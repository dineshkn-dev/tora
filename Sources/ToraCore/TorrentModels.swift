import Foundation

public struct TorrentID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct PendingTorrent: Equatable, Sendable, Codable {
    public let name: String
    public let infoHash: String?
    public let files: [TorrentFile]
    public let source: TorrentSource

    public init(name: String, infoHash: String?, files: [TorrentFile], source: TorrentSource) {
        self.name = name
        self.infoHash = infoHash
        self.files = files
        self.source = source
    }
}

public enum TorrentSource: Equatable, Sendable, Codable {
    case torrentFile(URL)
    case magnet(String)
}

public struct TorrentFile: Equatable, Codable, Sendable {
    public let index: Int
    public let path: String
    public let size: Int64
    public let isWantedByDefault: Bool

    public init(index: Int, path: String, size: Int64, isWantedByDefault: Bool = true) {
        self.index = index
        self.path = path
        self.size = size
        self.isWantedByDefault = isWantedByDefault
    }
}

public struct AddTorrentOptions: Equatable, Sendable, Codable {
    public let downloadDirectory: URL
    public let selectedFileIndexes: Set<Int>
    public let startPaused: Bool
    public let fetchMetadataOnly: Bool

    public init(
        downloadDirectory: URL,
        selectedFileIndexes: Set<Int>,
        startPaused: Bool,
        fetchMetadataOnly: Bool = false
    ) {
        self.downloadDirectory = downloadDirectory
        self.selectedFileIndexes = selectedFileIndexes
        self.startPaused = startPaused
        self.fetchMetadataOnly = fetchMetadataOnly
    }
}

public struct TorrentSnapshot: Equatable, Sendable {
    public let id: TorrentID
    public let name: String
    public let progress: Double
    public let state: TorrentState
    public let downloadRate: Int64
    public let uploadRate: Int64
    public let totalWanted: Int64
    public let totalDone: Int64
    public let totalUploaded: Int64
    public let seedingSeconds: Int
    public let hasMetadata: Bool

    public init(
        id: TorrentID,
        name: String,
        progress: Double,
        state: TorrentState,
        downloadRate: Int64,
        uploadRate: Int64,
        totalWanted: Int64,
        totalDone: Int64,
        totalUploaded: Int64 = 0,
        seedingSeconds: Int = 0,
        hasMetadata: Bool = true
    ) {
        self.id = id
        self.name = name
        self.progress = progress
        self.state = state
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
        self.totalWanted = totalWanted
        self.totalDone = totalDone
        self.totalUploaded = totalUploaded
        self.seedingSeconds = seedingSeconds
        self.hasMetadata = hasMetadata
    }

    public var seedRatio: Double {
        guard totalDone > 0 else { return 0 }
        return Double(totalUploaded) / Double(totalDone)
    }
}

public enum TorrentState: String, Codable, Sendable {
    case checking
    case downloadingMetadata
    case downloading
    case finished
    case seeding
    case paused
    case error
}

public enum TorrentEvent: Equatable, Sendable {
    case added(TorrentID)
    case updated(TorrentSnapshot)
    case removed(TorrentID)
    case metadataReceived(TorrentID, PendingTorrent)
    case resumeDataSaved(TorrentID)
    case failed(TorrentID?, String)
}

public enum RemoveMode: Equatable, Sendable {
    case removeTorrentOnly
    case removeTorrentAndDownloadedData
}

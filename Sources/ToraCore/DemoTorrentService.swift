import Foundation

public actor DemoTorrentService: TorrentServiceProtocol {
    private var list: [TorrentSnapshot] = [
        TorrentSnapshot(
            id: TorrentID(rawValue: "demo-hash-1"),
            name: "Cyberpunk 2077 Update",
            progress: 0.684,
            state: .downloading,
            downloadRate: 12500000,
            uploadRate: 2100000,
            totalWanted: 2100000000,
            totalDone: 1436400000,
            totalUploaded: 0,
            seedingSeconds: 0,
            hasMetadata: true
        ),
        TorrentSnapshot(
            id: TorrentID(rawValue: "demo-hash-2"),
            name: "ubuntu-23.10-desktop-amd64.iso",
            progress: 0.684,
            state: .downloading,
            downloadRate: 12500000,
            uploadRate: 2100000,
            totalWanted: 2100000000,
            totalDone: 1436400000,
            totalUploaded: 0,
            seedingSeconds: 0,
            hasMetadata: true
        ),
        TorrentSnapshot(
            id: TorrentID(rawValue: "demo-hash-3"),
            name: "ubuntu-docs.zip",
            progress: 1.0,
            state: .seeding,
            downloadRate: 0,
            uploadRate: 2100000,
            totalWanted: 1200000000,
            totalDone: 1200000000,
            totalUploaded: 1200000000,
            seedingSeconds: 5776,
            hasMetadata: true
        )
    ]
    
    private var lastUpdate = Date()

    public init() {}

    public func start() async throws {}
    public func shutdown() async {}

    public func inspectTorrentFile(_ url: URL) async throws -> PendingTorrent {
        PendingTorrent(name: "Demo Torrent", infoHash: nil, files: [], source: .torrentFile(url))
    }

    public func inspectMagnet(_ magnet: String) async throws -> PendingTorrent {
        PendingTorrent(name: "Demo Torrent", infoHash: nil, files: [], source: .magnet(magnet))
    }

    public func addTorrent(_ pending: PendingTorrent, options: AddTorrentOptions) async throws -> TorrentID {
        TorrentID(rawValue: UUID().uuidString)
    }

    public func metadataForTorrent(_ id: TorrentID, source: TorrentSource) async throws -> PendingTorrent? { nil }
    public func setFileSelectionAndStart(_ id: TorrentID, selectedFileIndexes: Set<Int>, startPaused: Bool) async throws {}
    public func pauseTorrent(_ id: TorrentID) async throws {}
    public func resumeTorrent(_ id: TorrentID) async throws {}
    public func fetchMetadata(_ id: TorrentID) async throws {}
    public func removeTorrent(_ id: TorrentID, mode: RemoveMode) async throws {}
    
    public func torrents() async -> [TorrentSnapshot] {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastUpdate)
        lastUpdate = now
        
        list = list.map { torrent in
            if torrent.state == .downloading {
                // Jitter speeds: 10-15 MB/s down, 1.8-2.4 MB/s up
                let newDL = Int64.random(in: 10_000_000...15_000_000)
                let newUL = Int64.random(in: 1_800_000...2_400_000)
                
                let added = Int64(Double(newDL) * elapsed)
                let done = min(torrent.totalWanted, torrent.totalDone + added)
                let newProgress = Double(done) / Double(torrent.totalWanted)
                
                return TorrentSnapshot(
                    id: torrent.id,
                    name: torrent.name,
                    progress: newProgress,
                    state: done >= torrent.totalWanted ? .seeding : .downloading,
                    downloadRate: done >= torrent.totalWanted ? 0 : newDL,
                    uploadRate: newUL,
                    totalWanted: torrent.totalWanted,
                    totalDone: done,
                    totalUploaded: torrent.totalUploaded,
                    seedingSeconds: torrent.seedingSeconds,
                    hasMetadata: true
                )
            } else if torrent.state == .seeding {
                let newUL = Int64.random(in: 1_800_000...2_400_000)
                let addedUL = Int64(Double(newUL) * elapsed)
                let newSecs = torrent.seedingSeconds + Int(elapsed)
                return TorrentSnapshot(
                    id: torrent.id,
                    name: torrent.name,
                    progress: 1.0,
                    state: .seeding,
                    downloadRate: 0,
                    uploadRate: newUL,
                    totalWanted: torrent.totalWanted,
                    totalDone: torrent.totalDone,
                    totalUploaded: torrent.totalUploaded + addedUL,
                    seedingSeconds: newSecs,
                    hasMetadata: true
                )
            }
            return torrent
        }
        return list
    }
    
    public func drainEvents() async -> [TorrentEvent] { [] }
    public func updateSettings(_ settings: TorrentSessionSettings) async throws {}

    public nonisolated func events() -> AsyncStream<TorrentEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

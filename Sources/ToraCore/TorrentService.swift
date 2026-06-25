import Foundation
import ToraLibtorrentBridge

public protocol TorrentServiceProtocol: Sendable {
    func start() async throws
    func shutdown() async
    func inspectTorrentFile(_ url: URL) async throws -> PendingTorrent
    func inspectMagnet(_ magnet: String) async throws -> PendingTorrent
    func addTorrent(_ pending: PendingTorrent, options: AddTorrentOptions) async throws -> TorrentID
    func metadataForTorrent(_ id: TorrentID, source: TorrentSource) async throws -> PendingTorrent?
    func setFileSelectionAndStart(_ id: TorrentID, selectedFileIndexes: Set<Int>, startPaused: Bool) async throws
    func pauseTorrent(_ id: TorrentID) async throws
    func resumeTorrent(_ id: TorrentID) async throws
    func fetchMetadata(_ id: TorrentID) async throws
    func removeTorrent(_ id: TorrentID, mode: RemoveMode) async throws
    func torrents() async -> [TorrentSnapshot]
    func events() -> AsyncStream<TorrentEvent>
    func drainEvents() async -> [TorrentEvent]
    func updateSettings(_ settings: TorrentSessionSettings) async throws
}

public protocol TorrentMetadataStoring: Sendable {
    func load() async throws -> [TorrentRecord]
    func upsert(_ record: TorrentRecord) async throws
    func remove(id: TorrentID) async throws
}

public actor TorrentService: TorrentServiceProtocol {
    private let pathPolicy: DownloadPathPolicy
    private let magnetValidator: MagnetValidator
    private let inputValidator: TorrentInputValidator
    private var settings: TorrentSessionSettings
    private let metadataStore: (any TorrentMetadataStoring)?
    private let deletionPolicy: DeletionPolicy?
    private let resumeDataDirectory: URL?
    private let sessionStateURL: URL?
    private let client: TORLibtorrentClient

    public init(
        settings: TorrentSessionSettings = .secureDefault,
        pathPolicy: DownloadPathPolicy = DownloadPathPolicy(),
        magnetValidator: MagnetValidator = MagnetValidator(),
        inputValidator: TorrentInputValidator = TorrentInputValidator(),
        metadataStore: (any TorrentMetadataStoring)? = nil,
        deletionPolicy: DeletionPolicy? = nil,
        resumeDataDirectory: URL? = nil,
        sessionStateURL: URL? = nil
    ) throws {
        self.settings = settings
        self.pathPolicy = pathPolicy
        self.magnetValidator = magnetValidator
        self.inputValidator = inputValidator
        self.metadataStore = metadataStore
        self.deletionPolicy = deletionPolicy
        self.resumeDataDirectory = resumeDataDirectory
        self.sessionStateURL = sessionStateURL
        var error: NSError?
        self.client = TORLibtorrentClient(config: settings.bridgeConfig(), error: &error)
        if let error {
            throw error
        }
    }

    public func start() async throws {
        guard let records = try await metadataStore?.load() else { return }
        for record in records {
            do {
                try pathPolicy.validateDownloadDirectory(record.downloadDirectory)
            } catch {
                try? await metadataStore?.remove(id: record.id)
                continue
            }
            let pending = PendingTorrent(
                name: record.name,
                infoHash: record.id.rawValue,
                files: [],
                source: record.source
            )
            let request = TORAddTorrentRequest()
            request.pendingTorrent = pending.bridgeModel()
            request.sessionConfig = settings.bridgeConfig(sessionStateURL: sessionStateURL)
            request.downloadDirectory = record.downloadDirectory
            request.selectedFileIndexes = IndexSet(record.selectedFileIndexes)
            request.startPaused = true
            request.fetchMetadataOnly = false
            if let resumeDataDirectory {
                request.resumeDataURL = resumeDataDirectory
                    .appendingPathComponent(record.id.rawValue, isDirectory: false)
                    .appendingPathExtension("fastresume")
            }
            if let restoredID = try? client.addTorrent(request) {
                let torrentID = TorrentID(rawValue: restoredID)
                if torrentID != record.id {
                    try? await metadataStore?.remove(id: record.id)
                    try? await metadataStore?.upsert(TorrentRecord(
                        id: torrentID,
                        name: record.name,
                        source: record.source,
                        downloadDirectory: record.downloadDirectory,
                        selectedFileIndexes: record.selectedFileIndexes,
                        createdAt: record.createdAt
                    ))
                }
            }
        }
    }

    public func shutdown() async {
        try? client.requestResumeDataForAllTorrents()
        _ = await drainEvents()
        client.shutdown()
    }

    public func inspectTorrentFile(_ url: URL) async throws -> PendingTorrent {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let fileSize = values.fileSize else {
                throw TorrentServiceError.invalidTorrentFile
            }
            guard fileSize <= 10 * 1024 * 1024 else {
                throw TorrentServiceError.torrentFileTooLarge
            }
        } catch let error as TorrentServiceError {
            throw error
        } catch {
            throw TorrentServiceError.invalidTorrentFile
        }

        let pending = try client.inspectTorrentFile(at: url)
        return pending.coreModel(source: TorrentSource.torrentFile(url))
    }

    public func inspectMagnet(_ magnet: String) async throws -> PendingTorrent {
        try magnetValidator.validate(magnet)
        let pending = try client.inspectMagnet(magnet)
        return pending.coreModel(source: TorrentSource.magnet(magnet))
    }

    public func addTorrent(_ pending: PendingTorrent, options: AddTorrentOptions) async throws -> TorrentID {
        try pathPolicy.validateDownloadDirectory(options.downloadDirectory)
        try inputValidator.validate(pending, options: options)
        let request = TORAddTorrentRequest()
        request.pendingTorrent = pending.bridgeModel()
        request.sessionConfig = settings.bridgeConfig(sessionStateURL: sessionStateURL)
        if options.fetchMetadataOnly {
            let metadataFetchDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ToraMetadataFetch", isDirectory: true)
            try FileManager.default.createDirectory(
                at: metadataFetchDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            request.downloadDirectory = metadataFetchDirectory
        } else {
            request.downloadDirectory = options.downloadDirectory
        }
        request.selectedFileIndexes = IndexSet(options.selectedFileIndexes)
        request.startPaused = options.startPaused
        request.fetchMetadataOnly = options.fetchMetadataOnly
        if let resumeDataDirectory, let infoHash = pending.infoHash {
            request.resumeDataURL = resumeDataDirectory
                .appendingPathComponent(infoHash, isDirectory: false)
                .appendingPathExtension("fastresume")
        }

        let id = try client.addTorrent(request)
        let torrentID = TorrentID(rawValue: id)
        if options.fetchMetadataOnly {
            return torrentID
        }
        try await metadataStore?.upsert(TorrentRecord(
            id: torrentID,
            name: pending.name,
            source: pending.source,
            downloadDirectory: options.downloadDirectory,
            selectedFileIndexes: options.selectedFileIndexes
        ))
        return torrentID
    }

    public func metadataForTorrent(_ id: TorrentID, source: TorrentSource) async throws -> PendingTorrent? {
        (try? client.metadata(forTorrent: id.rawValue))?.coreModel(source: source)
    }

    public func setFileSelectionAndStart(_ id: TorrentID, selectedFileIndexes: Set<Int>, startPaused: Bool) async throws {
        let records = try await metadataStore?.load() ?? []
        guard let record = records.first(where: { $0.id == id }) else {
            throw TorrentServiceError.missingMetadataForSelection
        }
        let pending = try client.metadata(forTorrent: id.rawValue).coreModel(source: record.source)
        let options = AddTorrentOptions(
            downloadDirectory: record.downloadDirectory,
            selectedFileIndexes: selectedFileIndexes,
            startPaused: startPaused
        )
        try pathPolicy.validateDownloadDirectory(record.downloadDirectory)
        try inputValidator.validate(pending, options: options)
        try client.setSelectedFileIndexes(
            IndexSet(selectedFileIndexes),
            forTorrent: id.rawValue,
            startPaused: startPaused
        )
        try await metadataStore?.upsert(TorrentRecord(
            id: record.id,
            name: record.name,
            source: record.source,
            downloadDirectory: record.downloadDirectory,
            selectedFileIndexes: selectedFileIndexes,
            createdAt: record.createdAt
        ))
    }

    public func pauseTorrent(_ id: TorrentID) async throws {
        try client.pauseTorrent(id.rawValue)
    }

    public func resumeTorrent(_ id: TorrentID) async throws {
        try client.resumeTorrent(id.rawValue)
    }

    public func fetchMetadata(_ id: TorrentID) async throws {
        guard settings.enableDHT else {
            throw TorrentServiceError.dhtRequiredForMagnetMetadata
        }
        try client.fetchMetadata(forTorrent: id.rawValue)
    }

    public func removeTorrent(_ id: TorrentID, mode: RemoveMode) async throws {
        if mode == .removeTorrentAndDownloadedData {
            guard let record = try await metadataStore?.load().first(where: { $0.id == id }) else {
                throw TorrentServiceError.missingMetadataForDeletion
            }
            try deletionPolicy?.validateDeletionRoot(record.downloadDirectory)
        }
        do {
            try client.removeTorrent(id.rawValue, deleteData: mode == .removeTorrentAndDownloadedData)
        } catch {
            guard mode == .removeTorrentOnly, error.localizedDescription == "Torrent not found." else {
                throw error
            }
        }
        try await metadataStore?.remove(id: id)
    }

    public func torrents() async -> [TorrentSnapshot] {
        client.torrentStatuses().compactMap(TorrentSnapshot.init(bridgeStatus:))
    }

    public nonisolated func events() -> AsyncStream<TorrentEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func drainEvents() async -> [TorrentEvent] {
        guard let resumeDataDirectory else { return [] }
        return client.drainEventsSavingResumeData(toDirectory: resumeDataDirectory).compactMap(TorrentEvent.init(bridgeEvent:))
    }

    public func updateSettings(_ settings: TorrentSessionSettings) async throws {
        try client.apply(settings.bridgeConfig(sessionStateURL: sessionStateURL))
        self.settings = settings
    }
}

public actor MockTorrentService: TorrentServiceProtocol {
    public init() {}

    public func start() async throws {}
    public func shutdown() async {}

    public func inspectTorrentFile(_ url: URL) async throws -> PendingTorrent {
        PendingTorrent(
            name: url.deletingPathExtension().lastPathComponent,
            infoHash: nil,
            files: [],
            source: .torrentFile(url)
        )
    }

    public func inspectMagnet(_ magnet: String) async throws -> PendingTorrent {
        try MagnetValidator().validate(magnet)
        return PendingTorrent(name: "Magnet Torrent", infoHash: nil, files: [], source: .magnet(magnet))
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
    public func torrents() async -> [TorrentSnapshot] { [] }
    public func drainEvents() async -> [TorrentEvent] { [] }
    public func updateSettings(_ settings: TorrentSessionSettings) async throws {}

    public nonisolated func events() -> AsyncStream<TorrentEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

public enum TorrentServiceError: LocalizedError, Equatable {
    case bridgeNotConfigured
    case notImplemented
    case missingMetadataForDeletion
    case missingMetadataForSelection
    case dhtRequiredForMagnetMetadata
    case invalidTorrentFile
    case torrentFileTooLarge

    public var errorDescription: String? {
        switch self {
        case .bridgeNotConfigured:
            "The libtorrent bridge is not configured yet."
        case .notImplemented:
            "This torrent operation is not implemented yet."
        case .missingMetadataForDeletion:
            "Refusing to delete downloaded data because torrent metadata is missing."
        case .missingMetadataForSelection:
            "Cannot start this torrent because its saved metadata record is missing."
        case .dhtRequiredForMagnetMetadata:
            "DHT is disabled. Enable DHT to fetch trackerless magnet metadata."
        case .invalidTorrentFile:
            "The torrent file is invalid or cannot be read."
        case .torrentFileTooLarge:
            "The torrent file is too large to load safely (limit is 10 MB)."
        }
    }
}

private extension TorrentSessionSettings {
    func bridgeConfig(sessionStateURL: URL? = nil) -> TORSessionConfig {
        let config = TORSessionConfig()
        config.enableDHT = enableDHT
        config.enableLSD = enableLSD
        config.enableUPnP = enableUPnP
        config.enableNATPMP = enableNATPMP
        config.enablePeerExchange = enablePeerExchange
        config.encryptionPolicy = encryptionPolicy.bridgeValue
        config.listenPortStart = listenPortStart
        config.listenPortEnd = listenPortEnd
        config.maxConnections = maxConnections
        config.maxUploads = maxUploads
        config.downloadRateLimitBytesPerSecond = downloadRateLimitBytesPerSecond ?? 0
        config.uploadRateLimitBytesPerSecond = uploadRateLimitBytesPerSecond ?? 0
        config.seedRatioLimitPercent = seedRatioLimitPercent ?? 0
        config.seedTimeLimitSeconds = seedTimeLimitSeconds ?? 0
        config.seedTimeRatioLimitPercent = seedTimeRatioLimitPercent ?? 0
        config.sessionStateURL = sessionStateURL
        return config
    }
}

private extension EncryptionPolicy {
    var bridgeValue: TOREncryptionPolicy {
        switch self {
        case .enabled: .enabled
        case .forced: .forced
        case .disabled: .disabled
        }
    }
}

private extension TORPendingTorrent {
    func coreModel(source: TorrentSource) -> PendingTorrent {
        PendingTorrent(
            name: name,
            infoHash: infoHash,
            files: files.map { $0.coreModel() },
            source: source
        )
    }
}

private extension TORTorrentFile {
    func coreModel() -> TorrentFile {
        TorrentFile(index: index, path: path, size: size, isWantedByDefault: true)
    }
}

private extension TorrentSnapshot {
    init?(bridgeStatus: TORTorrentStatus) {
        self.init(
            id: TorrentID(rawValue: bridgeStatus.torrentID),
            name: bridgeStatus.name,
            progress: bridgeStatus.progress,
            state: TorrentState(rawValue: bridgeStatus.state) ?? .error,
            downloadRate: bridgeStatus.downloadRate,
            uploadRate: bridgeStatus.uploadRate,
            totalWanted: bridgeStatus.totalWanted,
            totalDone: bridgeStatus.totalDone,
            totalUploaded: bridgeStatus.totalUploaded,
            seedingSeconds: bridgeStatus.seedingSeconds,
            hasMetadata: bridgeStatus.hasMetadata
        )
    }
}

private extension TorrentEvent {
    init?(bridgeEvent: TORTorrentEvent) {
        switch bridgeEvent.kind {
        case .metadataReceived:
            guard let torrentID = bridgeEvent.torrentID, let pending = bridgeEvent.pendingTorrent else { return nil }
            self = .metadataReceived(TorrentID(rawValue: torrentID), pending.coreModel(source: .magnet("")))
        case .resumeDataSaved:
            guard let torrentID = bridgeEvent.torrentID else { return nil }
            self = .resumeDataSaved(TorrentID(rawValue: torrentID))
        case .error:
            self = .failed(bridgeEvent.torrentID.map(TorrentID.init(rawValue:)), bridgeEvent.message ?? "Unknown libtorrent error")
        @unknown default:
            return nil
        }
    }
}

private extension PendingTorrent {
    func bridgeModel() -> TORPendingTorrent {
        let pending = TORPendingTorrent()
        pending.name = name
        pending.infoHash = infoHash
        pending.files = files.map { $0.bridgeModel() }
        switch source {
        case .torrentFile(let url):
            pending.torrentFileURL = url
        case .magnet(let magnet):
            pending.magnetLink = magnet
        }
        return pending
    }
}

private extension TorrentFile {
    func bridgeModel() -> TORTorrentFile {
        let file = TORTorrentFile()
        file.index = index
        file.path = path
        file.size = size
        return file
    }
}

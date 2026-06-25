import Foundation

public struct TorrentInputValidator: Sendable {
    private let pathPolicy: DownloadPathPolicy

    public init(pathPolicy: DownloadPathPolicy = DownloadPathPolicy()) {
        self.pathPolicy = pathPolicy
    }

    public func validate(_ pending: PendingTorrent, options: AddTorrentOptions) throws {
        try pathPolicy.validateDownloadDirectory(options.downloadDirectory)

        if pending.files.isEmpty {
            guard options.startPaused || options.fetchMetadataOnly else {
                throw TorrentInputValidationError.metadataRequiredBeforeStart
            }
            return
        }

        let selectedFiles = pending.files.filter { options.selectedFileIndexes.contains($0.index) }
        guard !selectedFiles.isEmpty else {
            throw TorrentInputValidationError.noFilesSelected
        }

        let cache = TorrentPathValidationCache()
        var normalizedPaths = Set<String>()
        for file in selectedFiles {
            try TorrentPathValidator.validate(file.path, inside: options.downloadDirectory, cache: cache)

            let normalized = Self.normalizedCollisionKey(file.path)
            guard normalizedPaths.insert(normalized).inserted else {
                throw TorrentInputValidationError.duplicateFilePath(file.path)
            }
        }
    }

    private static func normalizedCollisionKey(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }
}

public enum TorrentInputValidationError: LocalizedError, Equatable {
    case noFilesSelected
    case metadataRequiredBeforeStart
    case duplicateFilePath(String)

    public var errorDescription: String? {
        switch self {
        case .noFilesSelected:
            "At least one file must be selected before starting a torrent."
        case .metadataRequiredBeforeStart:
            "Magnet metadata must be available before the torrent can start."
        case .duplicateFilePath(let path):
            "Torrent contains a duplicate or colliding file path: \(path)"
        }
    }
}

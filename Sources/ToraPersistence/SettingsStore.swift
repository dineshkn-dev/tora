import Foundation
import ToraCore

public struct SettingsStore: Sendable {
    private let fileURL: URL
    private let maxFileSizeBytes: Int

    public init(directory: URL, maxFileSizeBytes: Int = 64 * 1024) {
        self.fileURL = directory.appendingPathComponent("settings", isDirectory: false).appendingPathExtension("json")
        self.maxFileSizeBytes = maxFileSizeBytes
    }

    public func load() throws -> TorrentSessionSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .secureDefault
        }
        try validateFileSize()
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(TorrentSessionSettings.self, from: data)
    }

    public func save(_ settings: TorrentSessionSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func validateFileSize() throws {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize <= maxFileSizeBytes else {
            throw PersistenceStoreError.fileTooLarge
        }
    }
}

public enum PersistenceStoreError: LocalizedError, Equatable {
    case fileTooLarge

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge: "Stored application data is too large to load safely."
        }
    }
}

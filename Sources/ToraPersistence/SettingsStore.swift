import Foundation
import ToraCore

public struct SettingsStore: Sendable {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("settings", isDirectory: false).appendingPathExtension("json")
    }

    public func load() throws -> TorrentSessionSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .secureDefault
        }
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
}

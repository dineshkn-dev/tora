import Foundation
import ToraCore

public struct MetadataStore: TorrentMetadataStoring, Sendable {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("torrents", isDirectory: false).appendingPathExtension("json")
    }

    public func load() async throws -> [TorrentRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TorrentRecord].self, from: data)
    }

    public func save(_ records: [TorrentRecord]) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    public func upsert(_ record: TorrentRecord) async throws {
        var records = try await load()
        records.removeAll { $0.id == record.id }
        records.append(record)
        try await save(records.sorted { $0.createdAt < $1.createdAt })
    }

    public func remove(id: TorrentID) async throws {
        var records = try await load()
        records.removeAll { $0.id == id }
        try await save(records)
    }
}

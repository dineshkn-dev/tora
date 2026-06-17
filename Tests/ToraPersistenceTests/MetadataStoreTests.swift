import XCTest
import ToraCore
@testable import ToraPersistence

final class MetadataStoreTests: XCTestCase {
    func testRoundTripsTorrentRecords() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MetadataStore(directory: directory)
        let record = TorrentRecord(
            id: TorrentID(rawValue: "abc"),
            name: "Example",
            source: .torrentFile(URL(fileURLWithPath: "/tmp/example.torrent")),
            downloadDirectory: URL(fileURLWithPath: "/tmp/Tora", isDirectory: true),
            selectedFileIndexes: [0, 2],
            createdAt: Date(timeIntervalSince1970: 10)
        )

        try await store.upsert(record)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, [record])
    }

    func testRejectsOversizedMetadataFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("torrents").appendingPathExtension("json")
        try Data(repeating: 0x20, count: 128).write(to: fileURL)
        let store = MetadataStore(directory: directory, maxFileSizeBytes: 16)

        do {
            _ = try await store.load()
            XCTFail("Expected oversized metadata to be rejected.")
        } catch {
            XCTAssertEqual(error as? PersistenceStoreError, .fileTooLarge)
        }
    }
}

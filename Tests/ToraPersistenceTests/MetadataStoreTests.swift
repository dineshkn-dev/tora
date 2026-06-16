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
}

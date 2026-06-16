import XCTest
import ToraLibtorrentBridge

final class LibtorrentBridgeFixtureTests: XCTestCase {
    func testInspectsFixtureTorrentWhenLibtorrentIsEnabled() throws {
        guard ProcessInfo.processInfo.environment["TORA_LIBTORRENT_PREFIX"] != nil else {
            throw XCTSkip("libtorrent-enabled fixture test requires TORA_LIBTORRENT_PREFIX")
        }

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/empty-file.torrent.hex")
        let data = try Self.decodeHex(String(contentsOf: fixture, encoding: .utf8))
        let torrentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("torrent")
        try data.write(to: torrentURL)
        defer { try? FileManager.default.removeItem(at: torrentURL) }

        let config = TORSessionConfig()
        config.listenPortStart = 49_152
        config.listenPortEnd = 65_535
        let client = TORLibtorrentClient(config: config, error: nil)

        let pending = try client.inspectTorrentFile(at: torrentURL)
        XCTAssertEqual(pending.name, "one-byte.txt")
        XCTAssertEqual(pending.files.count, 1)
        XCTAssertEqual(pending.files.first?.path, "one-byte.txt")
    }

    private static func decodeHex(_ hex: String) throws -> Data {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        var data = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                throw NSError(domain: "ToraTests", code: 1)
            }
            data.append(byte)
            index = next
        }
        return data
    }
}

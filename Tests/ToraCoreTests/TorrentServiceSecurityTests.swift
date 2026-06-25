import XCTest
@testable import ToraCore

final class TorrentServiceSecurityTests: XCTestCase {
    func testInspectTorrentFileRejectsOversizedFile() async throws {
        let service = try TorrentService()

        // Create a temporary file larger than 10 MB
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("torrent")
        
        let size = 10 * 1024 * 1024 + 1 // 10 MB + 1 byte
        let data = Data(repeating: 0, count: size)
        try data.write(to: tempURL)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            _ = try await service.inspectTorrentFile(tempURL)
            XCTFail("Should have thrown torrentFileTooLarge error")
        } catch TorrentServiceError.torrentFileTooLarge {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInspectTorrentFileAllowsValidSize() async throws {
        let service = try TorrentService()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("torrent")
        
        let size = 1024 // 1 KB
        let data = Data(repeating: 0, count: size)
        try data.write(to: tempURL)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            _ = try await service.inspectTorrentFile(tempURL)
            // It might fail inside the bridge because of bencode format, but should not throw torrentFileTooLarge or invalidTorrentFile (it should bubble up bridge parsing errors)
        } catch TorrentServiceError.torrentFileTooLarge {
            XCTFail("Should not throw torrentFileTooLarge")
        } catch TorrentServiceError.invalidTorrentFile {
            XCTFail("Should not throw invalidTorrentFile for valid size")
        } catch {
            // Bridge/libtorrent error (e.g. failed to parse) is expected and correct
        }
    }
}

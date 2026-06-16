import XCTest
@testable import ToraCore

final class TorrentInputValidatorTests: XCTestCase {
    private let validator = TorrentInputValidator()
    private let downloadDirectory = URL(fileURLWithPath: "/Users/example/Downloads/Tora", isDirectory: true)

    func testRejectsEmptySelection() {
        let pending = PendingTorrent(
            name: "Example",
            infoHash: nil,
            files: [TorrentFile(index: 0, path: "file.txt", size: 1)],
            source: .magnet("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567")
        )
        let options = AddTorrentOptions(downloadDirectory: downloadDirectory, selectedFileIndexes: [], startPaused: true)

        XCTAssertThrowsError(try validator.validate(pending, options: options))
    }

    func testRejectsDuplicateCaseInsensitivePaths() {
        let pending = PendingTorrent(
            name: "Example",
            infoHash: nil,
            files: [
                TorrentFile(index: 0, path: "Folder/File.txt", size: 1),
                TorrentFile(index: 1, path: "folder/file.TXT", size: 1)
            ],
            source: .torrentFile(URL(fileURLWithPath: "/tmp/example.torrent"))
        )
        let options = AddTorrentOptions(downloadDirectory: downloadDirectory, selectedFileIndexes: [0, 1], startPaused: true)

        XCTAssertThrowsError(try validator.validate(pending, options: options))
    }

    func testIgnoresUnselectedDuplicatePath() {
        let pending = PendingTorrent(
            name: "Example",
            infoHash: nil,
            files: [
                TorrentFile(index: 0, path: "Folder/File.txt", size: 1),
                TorrentFile(index: 1, path: "folder/file.TXT", size: 1)
            ],
            source: .torrentFile(URL(fileURLWithPath: "/tmp/example.torrent"))
        )
        let options = AddTorrentOptions(downloadDirectory: downloadDirectory, selectedFileIndexes: [0], startPaused: true)

        XCTAssertNoThrow(try validator.validate(pending, options: options))
    }

    func testAllowsMetadataLessMagnetOnlyWhenPaused() {
        let pending = PendingTorrent(
            name: "Magnet",
            infoHash: "0123456789abcdef0123456789abcdef01234567",
            files: [],
            source: .magnet("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567")
        )

        XCTAssertNoThrow(try validator.validate(
            pending,
            options: AddTorrentOptions(downloadDirectory: downloadDirectory, selectedFileIndexes: [], startPaused: true)
        ))
        XCTAssertThrowsError(try validator.validate(
            pending,
            options: AddTorrentOptions(downloadDirectory: downloadDirectory, selectedFileIndexes: [], startPaused: false)
        ))
        XCTAssertNoThrow(try validator.validate(
            pending,
            options: AddTorrentOptions(
                downloadDirectory: downloadDirectory,
                selectedFileIndexes: [],
                startPaused: false,
                fetchMetadataOnly: true
            )
        ))
    }
}

import XCTest
import ToraCore
@testable import ToraPersistence

final class SettingsStoreTests: XCTestCase {
    func testReturnsSecureDefaultWhenMissing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SettingsStore(directory: directory)

        let settings = try store.load()
        XCTAssertEqual(settings, .secureDefault)
    }

    func testRoundTripsSettings() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SettingsStore(directory: directory)
        var settings = TorrentSessionSettings.secureDefault
        settings.enableDHT = true
        settings.encryptionPolicy = .forced
        settings.seedRatioLimitPercent = 150
        settings.seedTimeLimitSeconds = 3_600

        try store.save(settings)

        let loaded = try store.load()
        XCTAssertEqual(loaded, settings)
    }

    func testRejectsOversizedSettingsFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("settings").appendingPathExtension("json")
        try Data(repeating: 0x20, count: 128).write(to: fileURL)
        let store = SettingsStore(directory: directory, maxFileSizeBytes: 16)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? PersistenceStoreError, .fileTooLarge)
        }
    }
}

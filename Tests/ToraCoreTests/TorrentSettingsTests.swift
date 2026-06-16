import XCTest
@testable import ToraCore

final class TorrentSettingsTests: XCTestCase {
    func testSecureDefaultsKeepDiscoveryExplicitlyDisabled() {
        let settings = TorrentSessionSettings.secureDefault

        XCTAssertFalse(settings.enableDHT)
        XCTAssertFalse(settings.enableLSD)
        XCTAssertFalse(settings.enableUPnP)
        XCTAssertFalse(settings.enableNATPMP)
        XCTAssertFalse(settings.enablePeerExchange)
        XCTAssertEqual(settings.encryptionPolicy, .enabled)
        XCTAssertEqual(settings.seedRatioLimitPercent, 200)
        XCTAssertNil(settings.seedTimeLimitSeconds)
        XCTAssertNil(settings.seedTimeRatioLimitPercent)
    }
}

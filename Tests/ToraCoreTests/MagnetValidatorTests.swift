import XCTest
@testable import ToraCore

final class MagnetValidatorTests: XCTestCase {
    private let validator = MagnetValidator()

    func testAllowsBtihMagnet() {
        XCTAssertNoThrow(try validator.validate("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"))
    }

    func testRejectsEmptyMagnet() {
        XCTAssertThrowsError(try validator.validate(""))
    }

    func testRejectsWrongScheme() {
        XCTAssertThrowsError(try validator.validate("https://example.com/file.torrent"))
    }

    func testRejectsMissingExactTopic() {
        XCTAssertThrowsError(try validator.validate("magnet:?dn=example"))
    }

    func testRejectsControlCharacters() {
        XCTAssertThrowsError(try validator.validate("magnet:?xt=urn:btih:abc\u{0008}"))
    }

    func testRejectsOversizedMagnet() {
        XCTAssertThrowsError(try validator.validate("magnet:?xt=urn:btih:" + String(repeating: "a", count: 9_000)))
    }
}

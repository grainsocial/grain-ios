import XCTest
@testable import Grain

final class GrainTests: XCTestCase {
    func testAspectRatio() {
        let ratio = AspectRatio(width: 16, height: 9)
        XCTAssertEqual(ratio.ratio, 16.0 / 9.0, accuracy: 0.001)
    }

    func testBase64URLEncoding() {
        let data = Data([0xFF, 0xFE, 0xFD])
        let encoded = data.base64URLEncoded()
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
    }

    func testTokenStorageClear() {
        TokenStorage.clear()
        XCTAssertNil(TokenStorage.accessToken)
        XCTAssertNil(TokenStorage.refreshToken)
        XCTAssertNil(TokenStorage.userDID)
        XCTAssertTrue(TokenStorage.isExpired)
    }

    func testNotificationReasonParsing() {
        XCTAssertEqual(NotificationReason(rawValue: "gallery-favorite"), .galleryFavorite)
        XCTAssertEqual(NotificationReason(rawValue: "follow"), .follow)
        XCTAssertNil(NotificationReason(rawValue: "invalid"))
    }
}

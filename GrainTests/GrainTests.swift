@testable import Grain
import XCTest

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
        // TokenStorage is Keychain-backed and the test host shares that
        // Keychain with the installed app, so an unguarded clear() signs the
        // simulator's app out. Snapshot the real session and restore it.
        let saved = (
            accessToken: TokenStorage.accessToken,
            refreshToken: TokenStorage.refreshToken,
            userDID: TokenStorage.userDID,
            userHandle: TokenStorage.userHandle,
            userAvatar: TokenStorage.userAvatar,
            expiresAt: TokenStorage.tokenExpiresAt,
            scope: TokenStorage.grantedScope
        )
        defer {
            TokenStorage.accessToken = saved.accessToken
            TokenStorage.refreshToken = saved.refreshToken
            TokenStorage.userDID = saved.userDID
            TokenStorage.userHandle = saved.userHandle
            TokenStorage.userAvatar = saved.userAvatar
            TokenStorage.tokenExpiresAt = saved.expiresAt
            TokenStorage.grantedScope = saved.scope
        }

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

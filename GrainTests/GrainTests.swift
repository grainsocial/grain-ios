@testable import Grain
import XCTest

final class GrainTests: GrainTestCase {
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

    func testTokenStorageRemoveAccount() {
        // TokenStorage is Keychain-backed and the test host shares that
        // Keychain with the installed app. Credentials are per-DID, so a
        // synthetic DID keeps the simulator's real session out of it.
        let did = "did:plc:tokenstorageremovetest"
        TokenStorage.storeTokens(
            did: did,
            accessToken: "access",
            refreshToken: "refresh",
            handle: "remove-me.test",
            expiresAt: Date().addingTimeInterval(3600),
            scope: "atproto"
        )
        TokenStorage.upsertAccount(StoredAccount(did: did, handle: "remove-me.test", avatar: nil))
        defer { TokenStorage.removeAccount(did) }

        XCTAssertTrue(TokenStorage.hasCredentials(for: did))
        XCTAssertEqual(TokenStorage.handle(for: did), "remove-me.test")
        XCTAssertTrue(TokenStorage.accounts.contains { $0.did == did })

        TokenStorage.removeAccount(did)

        XCTAssertNil(TokenStorage.accessToken(for: did))
        XCTAssertNil(TokenStorage.refreshToken(for: did))
        XCTAssertNil(TokenStorage.tokenExpiresAt(for: did))
        XCTAssertFalse(TokenStorage.hasCredentials(for: did))
        XCTAssertFalse(TokenStorage.accounts.contains { $0.did == did })
    }

    func testNotificationReasonParsing() {
        XCTAssertEqual(NotificationReason(rawValue: "gallery-favorite"), .galleryFavorite)
        XCTAssertEqual(NotificationReason(rawValue: "follow"), .follow)
        XCTAssertNil(NotificationReason(rawValue: "invalid"))
    }
}

@testable import Grain
import XCTest

/// Keychain-backed credentials for every signed-in account. The test host
/// shares its Keychain with the app installed on the simulator, so every test
/// uses synthetic DIDs and puts the active account back afterwards.
@MainActor
final class TokenStorageTests: GrainTestCase {
    private var did = ""
    private var savedActiveDID: String?

    override func setUp() async throws {
        try await super.setUp()
        did = "did:plc:tokenstore-\(UUID().uuidString)"
        savedActiveDID = TokenStorage.activeDID
    }

    override func tearDown() async throws {
        TokenStorage.removeAccount(did)
        TokenStorage.activeDID = savedActiveDID
        try await super.tearDown()
    }

    private func store(
        accessToken: String = "access",
        refreshToken: String? = "refresh",
        handle: String? = "tester.test",
        expiresAt: Date = Date().addingTimeInterval(3600),
        scope: String? = "atproto transition:generic"
    ) {
        TokenStorage.storeTokens(
            did: did,
            accessToken: accessToken,
            refreshToken: refreshToken,
            handle: handle,
            expiresAt: expiresAt,
            scope: scope
        )
    }

    // MARK: - Round trips

    func testATokenResponseRoundTrips() {
        let expiry = Date().addingTimeInterval(1800)
        store(expiresAt: expiry)

        XCTAssertEqual(TokenStorage.accessToken(for: did), "access")
        XCTAssertEqual(TokenStorage.refreshToken(for: did), "refresh")
        XCTAssertEqual(TokenStorage.handle(for: did), "tester.test")
        XCTAssertEqual(TokenStorage.grantedScope(for: did), "atproto transition:generic")
        XCTAssertEqual(
            TokenStorage.tokenExpiresAt(for: did)?.timeIntervalSince1970 ?? 0,
            expiry.timeIntervalSince1970,
            accuracy: 1
        )
    }

    /// A refresh response carries a new access token but often omits the scope
    /// and handle. Letting those overwrite would blank out what the app knows.
    func testARefreshWithoutAScopeKeepsTheGrantedScope() {
        store()

        TokenStorage.storeTokens(
            did: did,
            accessToken: "newer-access",
            refreshToken: "newer-refresh",
            handle: nil,
            expiresAt: Date().addingTimeInterval(3600),
            scope: nil
        )

        XCTAssertEqual(TokenStorage.accessToken(for: did), "newer-access")
        XCTAssertEqual(TokenStorage.grantedScope(for: did), "atproto transition:generic")
        XCTAssertEqual(TokenStorage.handle(for: did), "tester.test")
    }

    /// A session created before the scope field existed reads as nil, which is
    /// what makes the app force a fresh sign-in.
    func testASessionWithNoStoredScopeReadsAsNil() {
        TokenStorage.storeTokens(
            did: did,
            accessToken: "access",
            refreshToken: "refresh",
            handle: "tester.test",
            expiresAt: Date().addingTimeInterval(3600),
            scope: nil
        )

        XCTAssertNil(TokenStorage.grantedScope(for: did))
    }

    func testAvatarsAreStoredSeparatelyFromTheTokenResponse() {
        store()
        XCTAssertNil(TokenStorage.avatar(for: did))

        TokenStorage.setAvatar("https://cdn/avatar.jpg", for: did)
        XCTAssertEqual(TokenStorage.avatar(for: did), "https://cdn/avatar.jpg")

        TokenStorage.setAvatar(nil, for: did)
        XCTAssertNil(TokenStorage.avatar(for: did))
    }

    // MARK: - hasCredentials

    func testAnAccountWithBothTokensCanResume() {
        store()
        XCTAssertTrue(TokenStorage.hasCredentials(for: did))
    }

    /// Without a refresh token the session dies the moment the access token
    /// expires, so it doesn't count as resumable.
    func testAnAccountWithNoRefreshTokenCannotResume() {
        store(refreshToken: nil)
        XCTAssertFalse(TokenStorage.hasCredentials(for: did))
    }

    func testAnUnknownAccountHasNoCredentials() {
        XCTAssertFalse(TokenStorage.hasCredentials(for: "did:plc:never-signed-in"))
        XCTAssertNil(TokenStorage.accessToken(for: "did:plc:never-signed-in"))
        XCTAssertNil(TokenStorage.tokenExpiresAt(for: "did:plc:never-signed-in"))
    }

    // MARK: - Active account

    /// `userDID` is the older name and has to stay an alias, not a second slot.
    func testUserDIDIsTheSameSlotAsActiveDID() {
        TokenStorage.activeDID = did
        XCTAssertEqual(TokenStorage.userDID, did)

        TokenStorage.userDID = "did:plc:other"
        XCTAssertEqual(TokenStorage.activeDID, "did:plc:other")

        TokenStorage.activeDID = nil
        XCTAssertNil(TokenStorage.userDID)
    }

    // MARK: - Account list

    func testUpsertingTwiceUpdatesRatherThanDuplicates() {
        TokenStorage.upsertAccount(StoredAccount(did: did, handle: "old.test", avatar: nil))
        TokenStorage.upsertAccount(StoredAccount(did: did, handle: "new.test", avatar: "https://cdn/a.jpg"))

        let matches = TokenStorage.accounts.filter { $0.did == did }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.handle, "new.test")
        XCTAssertEqual(matches.first?.avatar, "https://cdn/a.jpg")
    }

    // MARK: - removeAccount

    func testRemovingAnAccountWipesEverythingItOwned() {
        store()
        TokenStorage.setAvatar("https://cdn/a.jpg", for: did)
        TokenStorage.upsertAccount(StoredAccount(did: did, handle: "tester.test", avatar: nil))

        TokenStorage.removeAccount(did)

        XCTAssertNil(TokenStorage.accessToken(for: did))
        XCTAssertNil(TokenStorage.refreshToken(for: did))
        XCTAssertNil(TokenStorage.handle(for: did))
        XCTAssertNil(TokenStorage.avatar(for: did))
        XCTAssertNil(TokenStorage.tokenExpiresAt(for: did))
        XCTAssertNil(TokenStorage.grantedScope(for: did))
        XCTAssertFalse(TokenStorage.accounts.contains { $0.did == did })
    }

    /// Signing out the active account must leave nobody active — the caller
    /// decides who takes over, and guessing here would silently switch users.
    func testRemovingTheActiveAccountClearsTheActiveSlot() {
        store()
        TokenStorage.activeDID = did

        TokenStorage.removeAccount(did)

        XCTAssertNil(TokenStorage.activeDID)
    }

    func testRemovingANonActiveAccountLeavesTheActiveOneAlone() {
        let other = "did:plc:tokenstore-other-\(UUID().uuidString)"
        defer { TokenStorage.removeAccount(other) }

        store()
        TokenStorage.storeTokens(
            did: other, accessToken: "a", refreshToken: "r",
            handle: "other.test", expiresAt: Date().addingTimeInterval(3600), scope: nil
        )
        TokenStorage.activeDID = did

        TokenStorage.removeAccount(other)

        XCTAssertEqual(TokenStorage.activeDID, did)
        XCTAssertEqual(TokenStorage.accessToken(for: did), "access")
    }

    /// Sign-out runs this on accounts that may already be half gone.
    func testRemovingAnAccountThatWasNeverStoredIsHarmless() {
        let active = TokenStorage.activeDID
        TokenStorage.removeAccount("did:plc:never-signed-in")
        XCTAssertEqual(TokenStorage.activeDID, active)
    }

    // MARK: - StoredAccount

    func testStoredAccountsAreIdentifiedByDID() {
        let account = StoredAccount(did: did, handle: "tester.test", avatar: nil)

        XCTAssertEqual(account.id, did)
        XCTAssertEqual(account, StoredAccount(did: did, handle: "tester.test", avatar: nil))
        XCTAssertNotEqual(account, StoredAccount(did: "did:plc:other", handle: "tester.test", avatar: nil))
    }
}

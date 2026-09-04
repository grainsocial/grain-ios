@testable import Grain
import XCTest

/// The account hooks are plain (non-isolated) closures, so what they record has
/// to live somewhere a closure can mutate.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String?] = []

    func record(_ value: String?) {
        lock.withLock { values.append(value) }
    }

    var recorded: [String?] {
        lock.withLock { values }
    }

    var count: Int {
        lock.withLock { values.count }
    }
}

/// Account switching and sign-out, which is the half of `AuthManager` that
/// doesn't need an OAuth round trip. It is also the half that can strand a
/// user: switching to an account whose grant has gone, or signing out of one
/// account and taking the others with it.
///
/// Everything here uses synthetic DIDs, and the active account is put back in
/// `tearDown` — the test host shares its Keychain with the app installed on the
/// simulator.
@MainActor
final class AuthManagerAccountTests: GrainTestCase {
    private var alice = ""
    private var bob = ""
    private var savedActiveDID: String?
    private var savedActiveAccountID: String?

    override func setUp() async throws {
        try await super.setUp()
        alice = "did:plc:authtest-alice-\(UUID().uuidString)"
        bob = "did:plc:authtest-bob-\(UUID().uuidString)"
        savedActiveDID = TokenStorage.activeDID
        savedActiveAccountID = AccountScopedStorage.activeAccountID
    }

    override func tearDown() async throws {
        for did in [alice, bob] {
            TokenStorage.removeAccount(did)
            try? DPoP.clearKey(for: did)
            AccountScopedStorage.purge(did: did)
        }
        TokenStorage.activeDID = savedActiveDID
        AccountScopedStorage.activeAccountID = savedActiveAccountID
        try await super.tearDown()
    }

    /// A signed-in account with a live token and its own DPoP key.
    private func signIn(_ did: String, handle: String, expiresIn: TimeInterval = 3600) throws {
        _ = try DPoP.loadOrCreate(for: did)
        TokenStorage.storeTokens(
            did: did,
            accessToken: "\(handle)-access",
            refreshToken: "\(handle)-refresh",
            handle: handle,
            expiresAt: Date().addingTimeInterval(expiresIn),
            scope: AuthManager.requiredScopes.joined(separator: " ")
        )
        TokenStorage.upsertAccount(StoredAccount(did: did, handle: handle, avatar: nil))
    }

    /// In the account list but with no credentials behind it — what's left
    /// after a grant is revoked server-side.
    private func stranded(_ did: String, handle: String) {
        TokenStorage.upsertAccount(StoredAccount(did: did, handle: handle, avatar: nil))
    }

    // MARK: - Configuration

    /// These are registered with the PDS; changing one without updating the
    /// client metadata breaks sign-in for everyone.
    func testTheOAuthIdentifiersAreTheRegisteredOnes() {
        XCTAssertEqual(AuthManager.clientID, "grain-native://app")
        XCTAssertEqual(AuthManager.redirectURI, "grain://oauth/callback")
        XCTAssertFalse(AuthManager.requiredScopes.isEmpty)
        XCTAssertTrue(AuthManager.requiredScopes.contains("atproto"))
    }

    func testTheClientPointsAtTheConfiguredServer() {
        XCTAssertEqual(AuthManager().makeClient().baseURL, AuthManager.serverURL)
    }

    // MARK: - switchTo

    func testSwitchingAdoptsTheAccountsIdentity() async throws {
        try signIn(alice, handle: "alice.test")
        let auth = AuthManager()

        try await auth.switchTo(did: alice)

        XCTAssertEqual(auth.userDID, alice)
        XCTAssertEqual(auth.userHandle, "alice.test")
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertNotNil(auth.dpop)
    }

    /// The Keychain is authoritative but the launch path reads the UserDefaults
    /// copy, so a switch that moves only one leaves the next cold start on the
    /// wrong account.
    func testSwitchingMovesBothCopiesOfTheActiveDID() async throws {
        try signIn(alice, handle: "alice.test")
        let auth = AuthManager()

        try await auth.switchTo(did: alice)

        XCTAssertEqual(TokenStorage.activeDID, alice)
        XCTAssertEqual(AccountScopedStorage.activeAccountID, alice)
    }

    /// Per-account caches re-point themselves from this hook, so it has to fire
    /// with the account that actually took over.
    func testSwitchingNotifiesWithTheNewAccount() async throws {
        try signIn(alice, handle: "alice.test")
        let auth = AuthManager()
        let activated = Recorder()
        auth.onAccountDidActivate = { activated.record($0) }

        try await auth.switchTo(did: alice)

        XCTAssertEqual(activated.recorded, [alice])
    }

    /// Push registration unwinds here, and it needs credentials that still work
    /// — so the hook has to run before the handover, not after.
    func testSwitchingHandsTheOutgoingAccountsContextToTheDeactivateHook() async throws {
        try signIn(alice, handle: "alice.test")
        try signIn(bob, handle: "bob.test")
        let auth = AuthManager()
        try await auth.switchTo(did: alice)

        let deactivated = Recorder()
        auth.onAccountWillDeactivate = { deactivated.record($0?.accessToken) }

        try await auth.switchTo(did: bob)

        XCTAssertEqual(
            deactivated.recorded, ["alice.test-access"],
            "The hook must see the outgoing account's token, while it still works"
        )
        XCTAssertEqual(auth.userDID, bob)
    }

    /// Tapping the account you're already on shouldn't tear down the view tree.
    func testSwitchingToTheCurrentAccountIsANoOp() async throws {
        try signIn(alice, handle: "alice.test")
        let auth = AuthManager()
        try await auth.switchTo(did: alice)

        let activated = Recorder()
        auth.onAccountDidActivate = { activated.record($0) }
        try await auth.switchTo(did: alice)

        XCTAssertEqual(activated.count, 0)
        XCTAssertEqual(auth.userDID, alice)
    }

    /// An account whose grant is gone must fail the switch by name rather than
    /// handing over to a session that can't make a single request.
    func testSwitchingToAStrandedAccountThrowsWithItsHandle() async throws {
        try signIn(alice, handle: "alice.test")
        stranded(bob, handle: "bob.test")
        let auth = AuthManager()
        try await auth.switchTo(did: alice)

        do {
            try await auth.switchTo(did: bob)
            XCTFail("Expected the switch to fail")
        } catch let AuthManager.AccountError.signInRequired(handle) {
            XCTAssertEqual(handle, "bob.test")
        }

        XCTAssertEqual(auth.userDID, alice, "A failed switch must leave the current account in place")
    }

    // MARK: - signOut

    func testSigningOutErasesThatAccountsCredentials() async throws {
        try signIn(alice, handle: "alice.test")
        try signIn(bob, handle: "bob.test")
        let auth = AuthManager()
        try await auth.switchTo(did: alice)

        await auth.signOut(did: alice)

        XCTAssertFalse(TokenStorage.hasCredentials(for: alice))
        XCTAssertFalse(TokenStorage.accounts.contains { $0.did == alice })
    }

    /// A multi-account user signing out of one account should land on another,
    /// not on the login screen.
    func testSigningOutOfTheActiveAccountFallsBackToAnotherSignedInOne() async throws {
        try signIn(alice, handle: "alice.test")
        try signIn(bob, handle: "bob.test")
        let auth = AuthManager()
        try await auth.switchTo(did: bob)
        try await auth.switchTo(did: alice)

        await auth.signOut(did: alice)

        XCTAssertNotEqual(auth.userDID, alice)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertTrue(TokenStorage.hasCredentials(for: bob))
    }

    /// Signing out of an account from the switcher, while looking at a
    /// different one, must not disturb the session on screen.
    func testSigningOutOfANonActiveAccountLeavesTheCurrentSessionAlone() async throws {
        try signIn(alice, handle: "alice.test")
        try signIn(bob, handle: "bob.test")
        let auth = AuthManager()
        try await auth.switchTo(did: alice)

        await auth.signOut(did: bob)

        XCTAssertEqual(auth.userDID, alice)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertTrue(TokenStorage.hasCredentials(for: alice))
        XCTAssertFalse(TokenStorage.hasCredentials(for: bob))
    }

    /// Signing out has to take the account's local content with it, or the next
    /// person to sign in on this device sees the last one's cached feed.
    func testSigningOutPurgesTheAccountsLocalState() async throws {
        try signIn(alice, handle: "alice.test")
        try signIn(bob, handle: "bob.test")
        let auth = AuthManager()
        try await auth.switchTo(did: alice)

        let searches = RecentSearchStorage(did: alice)
        searches.addTextSearch("portra")
        XCTAssertFalse(RecentSearchStorage(did: alice).textSearches.isEmpty)

        await auth.signOut(did: alice)

        XCTAssertTrue(RecentSearchStorage(did: alice).textSearches.isEmpty)
    }

    /// The DPoP key is bound to the access token; leaving it behind is a stale
    /// secret for an account that no longer exists.
    func testSigningOutDropsTheAccountsDPoPKey() async throws {
        try signIn(alice, handle: "alice.test")
        try signIn(bob, handle: "bob.test")
        let auth = AuthManager()
        let originalThumbprint = try DPoP.loadOrCreate(for: alice).thumbprint
        try await auth.switchTo(did: alice)

        await auth.signOut(did: alice)

        // A fresh key means the old one really was cleared rather than reused.
        let rebuilt = try DPoP.loadOrCreate(for: alice)
        defer { try? DPoP.clearKey(for: alice) }
        XCTAssertNotEqual(rebuilt.thumbprint, originalThumbprint)
    }

    func testLoggingOutSignsOutWhoeverIsOnScreen() async throws {
        try signIn(alice, handle: "alice.test")
        try signIn(bob, handle: "bob.test")
        let auth = AuthManager()
        try await auth.switchTo(did: alice)

        await auth.logout()

        XCTAssertFalse(TokenStorage.hasCredentials(for: alice))
        XCTAssertNotEqual(auth.userDID, alice)
    }

    // MARK: - authContext

    func testThereIsNoAuthContextWithoutASession() async {
        let auth = AuthManager()
        auth.userDID = nil

        let context = await auth.authContext()

        XCTAssertNil(context)
    }

    func testAnAuthContextCarriesTheActiveAccountsToken() async throws {
        try signIn(alice, handle: "alice.test")
        let auth = AuthManager()
        try await auth.switchTo(did: alice)

        let context = await auth.authContext()

        XCTAssertEqual(context?.accessToken, "alice.test-access")
        XCTAssertNil(context?.nonce, "A fresh context starts without a nonce; the PDS supplies one")
    }

    // MARK: - AccountError

    /// This reaches the user in an alert on the account switcher.
    func testTheStrandedAccountErrorNamesTheAccount() {
        XCTAssertEqual(
            AuthManager.AccountError.signInRequired(handle: "alice.test").errorDescription,
            "Sign in again to use @alice.test."
        )
        XCTAssertEqual(
            AuthManager.AccountError.signInRequired(handle: nil).errorDescription,
            "Sign in again to use this account."
        )
    }
}

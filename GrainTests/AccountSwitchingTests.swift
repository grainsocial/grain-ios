@testable import Grain
import XCTest

/// Storage-level guarantees the account switcher rests on: two accounts never
/// read each other's credentials or cached content, and signing one out leaves
/// the other intact.
///
/// Every test uses synthetic DIDs — the test host shares its Keychain and
/// UserDefaults with the app installed on the simulator.
@MainActor
final class AccountSwitchingTests: GrainTestCase {
    private let alice = "did:plc:switchtest-alice"
    private let bob = "did:plc:switchtest-bob"

    override func tearDown() {
        TokenStorage.removeAccount(alice)
        TokenStorage.removeAccount(bob)
        AccountScopedStorage.purge(did: alice)
        AccountScopedStorage.purge(did: bob)
        super.tearDown()
    }

    private func signIn(_ did: String, handle: String, token: String) {
        TokenStorage.storeTokens(
            did: did,
            accessToken: token,
            refreshToken: "\(token)-refresh",
            handle: handle,
            expiresAt: Date().addingTimeInterval(3600),
            scope: "atproto"
        )
        TokenStorage.upsertAccount(StoredAccount(did: did, handle: handle, avatar: nil))
    }

    func testCredentialsAreIsolatedPerAccount() {
        signIn(alice, handle: "alice.test", token: "alice-token")
        signIn(bob, handle: "bob.test", token: "bob-token")

        XCTAssertEqual(TokenStorage.accessToken(for: alice), "alice-token")
        XCTAssertEqual(TokenStorage.accessToken(for: bob), "bob-token")
        XCTAssertEqual(TokenStorage.handle(for: alice), "alice.test")
        XCTAssertEqual(TokenStorage.handle(for: bob), "bob.test")
    }

    func testSigningOutOneAccountLeavesTheOtherSignedIn() {
        signIn(alice, handle: "alice.test", token: "alice-token")
        signIn(bob, handle: "bob.test", token: "bob-token")

        TokenStorage.removeAccount(alice)

        XCTAssertFalse(TokenStorage.hasCredentials(for: alice))
        XCTAssertTrue(TokenStorage.hasCredentials(for: bob))
        XCTAssertFalse(TokenStorage.accounts.contains { $0.did == alice })
        XCTAssertTrue(TokenStorage.accounts.contains { $0.did == bob })
    }

    func testUpsertKeepsDetailsAnEmptyTokenResponseWouldWipe() {
        TokenStorage.upsertAccount(StoredAccount(did: alice, handle: "alice.test", avatar: "https://cdn/alice.jpg"))
        // A refresh knows the DID but carries no profile details.
        TokenStorage.upsertAccount(StoredAccount(did: alice, handle: nil, avatar: nil))

        let stored = TokenStorage.accounts.first { $0.did == alice }
        XCTAssertEqual(stored?.handle, "alice.test")
        XCTAssertEqual(stored?.avatar, "https://cdn/alice.jpg")
    }

    func testDPoPKeysAreDistinctPerAccountAndSurviveTheOtherSigningOut() throws {
        let aliceKey = try DPoP.loadOrCreate(for: alice)
        let bobKey = try DPoP.loadOrCreate(for: bob)
        defer {
            try? DPoP.clearKey(for: alice)
            try? DPoP.clearKey(for: bob)
        }

        XCTAssertNotEqual(aliceKey.thumbprint, bobKey.thumbprint)
        // Reloading must return the same key: the access token is bound to it.
        XCTAssertEqual(try DPoP.loadOrCreate(for: alice).thumbprint, aliceKey.thumbprint)

        try DPoP.clearKey(for: alice)
        XCTAssertEqual(try DPoP.loadOrCreate(for: bob).thumbprint, bobKey.thumbprint)
    }

    func testScopedDefaultsKeysDoNotCollide() {
        XCTAssertEqual(AccountScopedStorage.key("viewedStoryUris", did: alice), "viewedStoryUris::\(alice)")
        XCTAssertNotEqual(
            AccountScopedStorage.key("viewedStoryUris", did: alice),
            AccountScopedStorage.key("viewedStoryUris", did: bob)
        )
        // No account (signed out) falls back to the bare key.
        XCTAssertEqual(AccountScopedStorage.key("viewedStoryUris", did: nil), "viewedStoryUris")
    }

    func testViewedStoriesAreTrackedPerAccount() {
        let storage = ViewedStoryStorage(did: alice)
        storage.markViewed(uri: "at://story-1", authorDid: "did:plc:author", createdAt: "2026-08-16T00:00:00Z")
        XCTAssertTrue(storage.isViewed(uri: "at://story-1"))

        storage.switchAccount(did: bob)
        XCTAssertFalse(storage.isViewed(uri: "at://story-1"), "Bob shouldn't inherit Alice's watch history")

        storage.switchAccount(did: alice)
        XCTAssertTrue(storage.isViewed(uri: "at://story-1"), "Switching back restores Alice's history")
    }

    func testPurgeRemovesOnlyTheSignedOutAccountsViewedStories() {
        let storage = ViewedStoryStorage(did: alice)
        storage.markViewed(uri: "at://alice-story", authorDid: "did:plc:author", createdAt: "2026-08-16T00:00:00Z")
        storage.switchAccount(did: bob)
        storage.markViewed(uri: "at://bob-story", authorDid: "did:plc:author", createdAt: "2026-08-16T00:00:00Z")
        storage.switchAccount(did: alice)

        AccountScopedStorage.purge(did: alice)

        XCTAssertFalse(ViewedStoryStorage(did: alice).isViewed(uri: "at://alice-story"))
        XCTAssertTrue(ViewedStoryStorage(did: bob).isViewed(uri: "at://bob-story"))
    }

    func testUploadCenterOnlySurfacesDraftsOwnedByTheActiveAccount() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("switchtest-drafts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GalleryDraftStore(root: root)
        store.save(draft(repo: alice, title: "Alice's gallery"))
        store.save(draft(repo: bob, title: "Bob's gallery"))

        let center = GalleryUploadCenter(store: store)
        center.accountChanged(to: alice)
        XCTAssertEqual(center.pending.map(\.title), ["Alice's gallery"])

        center.accountChanged(to: bob)
        XCTAssertEqual(center.pending.map(\.title), ["Bob's gallery"])
    }

    private func draft(repo: String, title: String) -> GalleryDraft {
        GalleryDraft(
            repo: repo,
            title: title,
            description: "",
            labels: [],
            location: nil,
            includeExif: false,
            postToBluesky: false,
            // Relative, not a literal: the store sweeps drafts older than a
            // week, so a hardcoded date turns this into a time bomb.
            createdAt: DateFormatting.nowISO(),
            galleryRkey: TID.next(),
            blueskyRkey: TID.next(),
            photos: []
        )
    }
}

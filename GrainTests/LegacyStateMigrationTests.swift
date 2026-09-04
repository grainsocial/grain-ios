@testable import Grain
import XCTest

/// Multi-account arrived after the app had already shipped, so every device
/// that updated had per-user state sitting at unsuffixed keys. Migration claims
/// it for whoever was signed in; without it that account appears to lose its
/// watch history and search history on update.
@MainActor
final class LegacyStateMigrationTests: XCTestCase {
    private var did = ""
    private let legacyKeys = ["viewedStoryUris", "viewedStoryAuthors", "recentSearchProfiles", "recentSearchText"]

    override func setUp() async throws {
        try await super.setUp()
        did = "did:plc:migration-\(UUID().uuidString)"
        clearLegacyKeys()
    }

    override func tearDown() async throws {
        clearLegacyKeys()
        AccountScopedStorage.purge(did: did)
        try await super.tearDown()
    }

    private func clearLegacyKeys() {
        for key in legacyKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func scoped(_ base: String) -> String {
        AccountScopedStorage.key(base, did: did)
    }

    func testLegacyStateIsClaimedByTheSignedInAccount() {
        UserDefaults.standard.set(["at://story-1"], forKey: "viewedStoryUris")
        UserDefaults.standard.set(["portra"], forKey: "recentSearchText")

        AccountScopedStorage.migrateLegacyState(to: did)

        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: scoped("viewedStoryUris")), ["at://story-1"])
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: scoped("recentSearchText")), ["portra"])
    }

    /// The bare keys have to go, or a second account signing in later would
    /// inherit the first one's history.
    func testTheUnsuffixedKeysAreRemovedAfterwards() {
        UserDefaults.standard.set(["at://story-1"], forKey: "viewedStoryUris")

        AccountScopedStorage.migrateLegacyState(to: did)

        XCTAssertNil(UserDefaults.standard.object(forKey: "viewedStoryUris"))
    }

    /// Migration runs on sign-in, which happens again every time an account is
    /// re-added — it must not clobber the state that account has since built up.
    func testExistingScopedStateWins() {
        UserDefaults.standard.set(["at://mine"], forKey: scoped("viewedStoryUris"))
        UserDefaults.standard.set(["at://legacy"], forKey: "viewedStoryUris")

        AccountScopedStorage.migrateLegacyState(to: did)

        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: scoped("viewedStoryUris")), ["at://mine"])
        XCTAssertNil(UserDefaults.standard.object(forKey: "viewedStoryUris"), "The legacy key is still cleaned up")
    }

    /// A fresh install has nothing to migrate.
    func testMigratingWithNothingToClaimIsHarmless() {
        AccountScopedStorage.migrateLegacyState(to: did)

        for key in legacyKeys {
            XCTAssertNil(UserDefaults.standard.object(forKey: scoped(key)))
        }
    }

    /// The whole point of the migration is that the storage classes then read
    /// it back under the new keys.
    func testMigratedViewedStoriesAreVisibleToTheStorage() {
        let flushTarget = "did:plc:migration-flush-\(UUID().uuidString)"
        defer { AccountScopedStorage.purge(did: flushTarget) }

        let legacy = ViewedStoryStorage(did: nil)
        legacy.markViewed(uri: "at://story-1", authorDid: "did:plc:author", createdAt: DateFormatting.nowISO())
        XCTAssertTrue(legacy.isViewed(uri: "at://story-1"))
        // Writes are debounced; switching accounts flushes the pending one
        // synchronously, which is what a real sign-in does before migrating.
        legacy.switchAccount(did: flushTarget)

        AccountScopedStorage.migrateLegacyState(to: did)

        XCTAssertTrue(ViewedStoryStorage(did: did).isViewed(uri: "at://story-1"))
    }

    func testMigratedSearchHistoryIsVisibleToTheStorage() {
        let legacy = RecentSearchStorage(did: nil)
        legacy.addTextSearch("portra")
        legacy.addProfile(did: "did:plc:a", displayName: "A", handle: "a.test", avatar: nil)

        AccountScopedStorage.migrateLegacyState(to: did)

        let migrated = RecentSearchStorage(did: did)
        XCTAssertEqual(migrated.textSearches.map(\.query), ["portra"])
        XCTAssertEqual(migrated.profiles.map(\.did), ["did:plc:a"])
    }

    // MARK: - activeAccountID

    /// The launch path reads this instead of the Keychain, so it has to round
    /// trip and to clear properly on sign-out.
    func testTheActiveAccountIDRoundTripsAndClears() {
        let saved = AccountScopedStorage.activeAccountID
        defer { AccountScopedStorage.activeAccountID = saved }

        AccountScopedStorage.activeAccountID = did
        XCTAssertEqual(AccountScopedStorage.activeAccountID, did)

        AccountScopedStorage.activeAccountID = nil
        XCTAssertNil(AccountScopedStorage.activeAccountID)
    }
}

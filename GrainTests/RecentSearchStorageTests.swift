@testable import Grain
import XCTest

/// Recent searches are account-scoped UserDefaults state, so every test uses a
/// synthetic DID and clears it afterwards — the test host shares UserDefaults
/// with the app installed on the simulator.
@MainActor
final class RecentSearchStorageTests: XCTestCase {
    private var did = ""

    override func setUp() async throws {
        try await super.setUp()
        did = "did:plc:recentsearch-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        AccountScopedStorage.purge(did: did)
        try await super.tearDown()
    }

    private func makeStorage() -> RecentSearchStorage {
        RecentSearchStorage(did: did)
    }

    // MARK: - Profiles

    func testAddedProfilesComeBackMostRecentFirst() {
        let storage = makeStorage()
        storage.addProfile(did: "did:plc:a", displayName: "A", handle: "a.test", avatar: nil)
        storage.addProfile(did: "did:plc:b", displayName: "B", handle: "b.test", avatar: nil)

        XCTAssertEqual(storage.profiles.map(\.did), ["did:plc:b", "did:plc:a"])
    }

    /// Tapping the same person twice should move them to the top, not add a
    /// second row for them.
    func testReAddingAProfileMovesItToTheTopWithoutDuplicating() {
        let storage = makeStorage()
        storage.addProfile(did: "did:plc:a", displayName: "A", handle: "a.test", avatar: nil)
        storage.addProfile(did: "did:plc:b", displayName: "B", handle: "b.test", avatar: nil)
        storage.addProfile(did: "did:plc:a", displayName: "A", handle: "a.test", avatar: nil)

        XCTAssertEqual(storage.profiles.map(\.did), ["did:plc:a", "did:plc:b"])
    }

    func testProfileHistoryIsCappedAtTen() {
        let storage = makeStorage()
        for i in 0 ..< 15 {
            storage.addProfile(did: "did:plc:\(i)", displayName: nil, handle: nil, avatar: nil)
        }

        XCTAssertEqual(storage.profiles.count, 10)
        XCTAssertEqual(storage.profiles.first?.did, "did:plc:14", "Newest entry should survive the cap")
        XCTAssertEqual(storage.profiles.last?.did, "did:plc:5", "Oldest entries should be the ones dropped")
    }

    func testRemovingAProfileLeavesTheRest() {
        let storage = makeStorage()
        storage.addProfile(did: "did:plc:a", displayName: nil, handle: nil, avatar: nil)
        storage.addProfile(did: "did:plc:b", displayName: nil, handle: nil, avatar: nil)

        storage.removeProfile("did:plc:a")

        XCTAssertEqual(storage.profiles.map(\.did), ["did:plc:b"])
    }

    // MARK: - Text searches

    func testAddedTextSearchesComeBackMostRecentFirst() {
        let storage = makeStorage()
        storage.addTextSearch("film")
        storage.addTextSearch("portra")

        XCTAssertEqual(storage.textSearches.map(\.query), ["portra", "film"])
    }

    func testTextSearchesAreTrimmedAndBlankOnesAreIgnored() {
        let storage = makeStorage()
        storage.addTextSearch("  film  ")
        storage.addTextSearch("   ")
        storage.addTextSearch("\n")

        XCTAssertEqual(storage.textSearches.map(\.query), ["film"])
    }

    /// Case shouldn't split one search into two rows.
    func testRepeatingATextSearchInADifferentCaseReplacesTheOldEntry() {
        let storage = makeStorage()
        storage.addTextSearch("Film")
        storage.addTextSearch("film")

        XCTAssertEqual(storage.textSearches.map(\.query), ["film"])
    }

    func testTextSearchHistoryIsCappedAtTen() {
        let storage = makeStorage()
        for i in 0 ..< 15 {
            storage.addTextSearch("query-\(i)")
        }

        XCTAssertEqual(storage.textSearches.count, 10)
        XCTAssertEqual(storage.textSearches.first?.query, "query-14")
    }

    func testRemovingATextSearchLeavesTheRest() {
        let storage = makeStorage()
        storage.addTextSearch("film")
        storage.addTextSearch("portra")

        storage.removeTextSearch("film")

        XCTAssertEqual(storage.textSearches.map(\.query), ["portra"])
    }

    // MARK: - Persistence and clearing

    /// The point of the class is surviving a relaunch, which is what a second
    /// instance reading the same keys stands in for.
    func testHistorySurvivesANewInstance() {
        let storage = makeStorage()
        storage.addProfile(did: "did:plc:a", displayName: "A", handle: "a.test", avatar: "https://cdn/a.jpg")
        storage.addTextSearch("film")

        let reloaded = makeStorage()

        XCTAssertEqual(reloaded.profiles.map(\.did), ["did:plc:a"])
        XCTAssertEqual(reloaded.profiles.first?.avatar, "https://cdn/a.jpg")
        XCTAssertEqual(reloaded.textSearches.map(\.query), ["film"])
    }

    func testClearAllEmptiesBothListsOnDiskToo() {
        let storage = makeStorage()
        storage.addProfile(did: "did:plc:a", displayName: nil, handle: nil, avatar: nil)
        storage.addTextSearch("film")

        storage.clearAll()

        XCTAssertTrue(storage.profiles.isEmpty)
        XCTAssertTrue(storage.textSearches.isEmpty)

        let reloaded = makeStorage()
        XCTAssertTrue(reloaded.profiles.isEmpty)
        XCTAssertTrue(reloaded.textSearches.isEmpty)
    }

    /// Two accounts on one device must not see each other's searches.
    func testHistoryIsScopedToTheAccountThatMadeIt() {
        let other = "did:plc:recentsearch-other-\(UUID().uuidString)"
        defer { AccountScopedStorage.purge(did: other) }

        let mine = makeStorage()
        mine.addTextSearch("film")

        let theirs = RecentSearchStorage(did: other)

        XCTAssertTrue(theirs.textSearches.isEmpty)
        XCTAssertEqual(mine.textSearches.map(\.query), ["film"])
    }

    func testIdentifiersAreTheStoredValues() {
        XCTAssertEqual(
            RecentProfileSearch(did: "did:plc:a", displayName: nil, handle: nil, avatar: nil).id,
            "did:plc:a"
        )
        XCTAssertEqual(RecentTextSearch(query: "film").id, "film")
    }
}

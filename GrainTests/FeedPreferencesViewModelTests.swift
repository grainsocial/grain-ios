@testable import Grain
import XCTest

/// File scope, not a static member: `MockURLProtocol.handler` runs outside the
/// main actor, so anything it reads has to live outside this @MainActor class.
private let serverFeeds = """
{"preferences": {
  "pinnedFeeds": [
    {"id": "following", "label": "Following", "type": "feed", "path": "/feeds/following"},
    {"id": "camera:Leica M6", "label": "Leica M6", "type": "camera", "path": "/c/leica"}
  ],
  "includeExif": false
}}
"""

/// Pinned feeds drive the feed switcher, and every mutation is applied
/// optimistically then written to the server. The rollback on failure is the
/// part worth holding still: without it a tab bar shows a feed the account
/// doesn't actually have pinned.
@MainActor
final class FeedPreferencesViewModelTests: GrainTestCase {
    private var client: XRPCClient!
    private var vm: FeedPreferencesViewModel!

    override func setUp() async throws {
        try await super.setUp()
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        vm = FeedPreferencesViewModel(client: client)
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try await super.tearDown()
    }

    private let hashtagFeed = PinnedFeed(id: "hashtag:film", label: "#film", type: "hashtag", path: "/t/film")

    // MARK: - Defaults

    func testItStartsOnTheDefaultFeedsBeforeAnythingLoads() {
        XCTAssertEqual(vm.pinnedFeeds, PinnedFeed.defaults)
        XCTAssertEqual(vm.selectedFeedId, "recent")
        XCTAssertEqual(vm.selectedFeedLabel, "Recent")
        XCTAssertTrue(vm.includeExif)
    }

    /// The label is what the switcher shows, and a feed that was unpinned out
    /// from under the selection must not leave a blank button.
    func testTheLabelFallsBackWhenTheSelectionIsNotPinned() {
        vm.selectedFeedId = "hashtag:nothing"
        XCTAssertEqual(vm.selectedFeedLabel, "Feed")
    }

    // MARK: - refresh

    func testRefreshAdoptsTheServersFeedsAndExifSetting() async {
        MockURLProtocol.respondWithJSON(serverFeeds)

        await vm.refresh(auth: nil)

        XCTAssertEqual(vm.pinnedFeeds.map(\.id), ["following", "camera:Leica M6"])
        XCTAssertFalse(vm.includeExif)
    }

    /// "recent" is the default selection but isn't in the account's list, so it
    /// has to move to something that is.
    func testRefreshMovesASelectionThatIsNoLongerPinned() async {
        MockURLProtocol.respondWithJSON(serverFeeds)

        await vm.refresh(auth: nil)

        XCTAssertEqual(vm.selectedFeedId, "following")
    }

    func testRefreshKeepsASelectionTheServerStillHas() async {
        MockURLProtocol.respondWithJSON(serverFeeds)
        vm.selectedFeedId = "camera:Leica M6"

        await vm.refresh(auth: nil)

        XCTAssertEqual(vm.selectedFeedId, "camera:Leica M6")
    }

    /// An account that has never set preferences comes back empty, and wiping
    /// the switcher down to nothing would leave no feed to show.
    func testAnEmptyFeedListLeavesTheDefaultsInPlace() async {
        MockURLProtocol.respondWithJSON(#"{"preferences": {"pinnedFeeds": []}}"#)

        await vm.refresh(auth: nil)

        XCTAssertEqual(vm.pinnedFeeds, PinnedFeed.defaults)
    }

    func testAFailedRefreshLeavesTheDefaultsInPlace() async {
        MockURLProtocol.respondWithError(statusCode: 500)

        await vm.refresh(auth: nil)

        XCTAssertEqual(vm.pinnedFeeds, PinnedFeed.defaults)
        XCTAssertTrue(vm.includeExif)
    }

    /// Called from `.task` on a view that can re-appear repeatedly.
    func testLoadIfNeededOnlyFetchesOnce() async {
        var requests = 0
        MockURLProtocol.handler = { request in
            requests += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(serverFeeds.utf8), response)
        }

        await vm.loadIfNeeded(auth: nil)
        await vm.loadIfNeeded(auth: nil)

        XCTAssertEqual(requests, 1)
    }

    // MARK: - isPinned

    func testIsPinnedReadsTheCurrentList() {
        XCTAssertTrue(vm.isPinned("recent"))
        XCTAssertFalse(vm.isPinned("hashtag:film"))
    }

    // MARK: - pinFeed

    func testPinningAppendsToTheEndOfTheList() async {
        MockURLProtocol.respondWithJSON("{}")

        await vm.pinFeed(hashtagFeed, auth: nil)

        XCTAssertEqual(vm.pinnedFeeds.last?.id, "hashtag:film")
        XCTAssertTrue(vm.isPinned("hashtag:film"))
    }

    func testPinningSomethingAlreadyPinnedIsANoOp() async {
        var requestMade = false
        MockURLProtocol.handler = { request in
            requestMade = true
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        await vm.pinFeed(PinnedFeed.defaults[0], auth: nil)

        XCTAssertFalse(requestMade)
        XCTAssertEqual(vm.pinnedFeeds, PinnedFeed.defaults)
    }

    func testAFailedPinIsRolledBack() async {
        MockURLProtocol.respondWithError(statusCode: 500)

        await vm.pinFeed(hashtagFeed, auth: nil)

        XCTAssertEqual(vm.pinnedFeeds, PinnedFeed.defaults)
    }

    // MARK: - unpinFeed

    func testUnpinningRemovesTheFeed() async {
        MockURLProtocol.respondWithJSON("{}")

        await vm.unpinFeed("following", auth: nil)

        XCTAssertEqual(vm.pinnedFeeds.map(\.id), ["recent", "foryou"])
    }

    /// Unpinning the feed you're looking at has to move the selection with it.
    func testUnpinningTheSelectedFeedMovesTheSelection() async {
        MockURLProtocol.respondWithJSON("{}")
        vm.selectedFeedId = "recent"

        await vm.unpinFeed("recent", auth: nil)

        XCTAssertEqual(vm.selectedFeedId, "following")
    }

    func testUnpinningTheLastFeedFallsBackToRecent() async {
        MockURLProtocol.respondWithJSON("{}")
        vm.pinnedFeeds = [PinnedFeed.defaults[1]]
        vm.selectedFeedId = "following"

        await vm.unpinFeed("following", auth: nil)

        XCTAssertEqual(vm.selectedFeedId, "recent")
    }

    func testAFailedUnpinRestoresBothTheListAndTheSelection() async {
        MockURLProtocol.respondWithError(statusCode: 500)
        vm.selectedFeedId = "recent"

        await vm.unpinFeed("recent", auth: nil)

        XCTAssertEqual(vm.pinnedFeeds, PinnedFeed.defaults)
        XCTAssertEqual(vm.selectedFeedId, "recent")
    }

    // MARK: - reorderFeeds

    func testReorderingKeepsTheNewOrder() async {
        MockURLProtocol.respondWithJSON("{}")
        let reversed = Array(PinnedFeed.defaults.reversed())

        await vm.reorderFeeds(reversed, auth: nil)

        XCTAssertEqual(vm.pinnedFeeds, reversed)
    }

    func testAFailedReorderSnapsBack() async {
        MockURLProtocol.respondWithError(statusCode: 500)

        await vm.reorderFeeds(Array(PinnedFeed.defaults.reversed()), auth: nil)

        XCTAssertEqual(vm.pinnedFeeds, PinnedFeed.defaults)
    }

    // MARK: - includeExif

    func testTurningExifOffSticks() async {
        MockURLProtocol.respondWithJSON("{}")

        await vm.setIncludeExif(false, auth: nil)

        XCTAssertFalse(vm.includeExif)
    }

    /// A silently-reverted privacy toggle is worse than a visibly failed one,
    /// so the switch has to snap back rather than lie.
    func testAFailedExifToggleSnapsBack() async {
        MockURLProtocol.respondWithError(statusCode: 500)

        await vm.setIncludeExif(false, auth: nil)

        XCTAssertTrue(vm.includeExif)
    }
}

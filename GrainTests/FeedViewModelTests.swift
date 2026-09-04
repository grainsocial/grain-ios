@testable import Grain
import XCTest

/// File scope, not a static member: `MockURLProtocol.handler` runs outside the
/// main actor, so anything it reads has to live outside a @MainActor class.
private func feedBody(ids: [Int], cursor: String?) -> String {
    let items = ids.map { id in
        """
        {
          "uri": "at://did:plc:a/social.grain.gallery/\(id)",
          "cid": "bafyg\(id)",
          "title": "Gallery \(id)",
          "creator": {"cid": "c1", "did": "did:plc:a", "handle": "alice.test"},
          "indexedAt": "2025-01-02T00:00:00Z"
        }
        """
    }.joined(separator: ",")
    let cursorJSON = cursor.map { "\"\($0)\"" } ?? "null"
    return "{\"items\": [\(items)], \"cursor\": \(cursorJSON)}"
}

/// The feed is the first screen and its view model has to survive a cold cache,
/// a failed fetch, and a tab switch mid-request. The cursor and the disk cache
/// are where it goes wrong quietly: a stale cursor re-appends a page, and a
/// cache key collision shows one account another's galleries.
@MainActor
final class FeedViewModelTests: GrainTestCase {
    private var client: XRPCClient!

    override func setUp() async throws {
        try await super.setUp()
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try await super.tearDown()
    }

    private func makeViewModel(feedName: String = "recent", cacheKey: String? = nil) -> FeedViewModel {
        FeedViewModel(client: client, feedName: feedName, cacheKey: cacheKey)
    }

    // MARK: - loadInitial

    func testLoadingFillsTheFeed() async {
        MockURLProtocol.respondWithJSON(feedBody(ids: [1, 2], cursor: nil))
        let vm = makeViewModel()

        await vm.loadInitial()

        XCTAssertEqual(vm.galleries.map(\.title), ["Gallery 1", "Gallery 2"])
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.error)
        XCTAssertTrue(vm.hasFetchedInitial)
    }

    /// The flag drives "we've heard from the server at least once", so a
    /// failure has to set it too or the screen retries forever.
    func testAFailedLoadStillCountsAsHavingFetched() async {
        MockURLProtocol.respondWithError(statusCode: 500)
        let vm = makeViewModel()

        await vm.loadInitial()

        XCTAssertTrue(vm.hasFetchedInitial)
        XCTAssertNotNil(vm.error)
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.galleries.isEmpty)
    }

    func testASuccessfulReloadClearsAPreviousError() async {
        MockURLProtocol.respondWithError(statusCode: 500)
        let vm = makeViewModel()
        await vm.loadInitial()
        XCTAssertNotNil(vm.error)

        MockURLProtocol.respondWithJSON(feedBody(ids: [1], cursor: nil))
        await vm.loadInitial()

        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.galleries.count, 1)
    }

    func testReloadingReplacesRatherThanAppends() async {
        MockURLProtocol.respondWithJSON(feedBody(ids: [1, 2], cursor: nil))
        let vm = makeViewModel()
        await vm.loadInitial()

        MockURLProtocol.respondWithJSON(feedBody(ids: [3], cursor: nil))
        await vm.loadInitial()

        XCTAssertEqual(vm.galleries.map(\.title), ["Gallery 3"])
    }

    /// Pull-to-refresh after paging has to forget where it had got to, or the
    /// next page continues from a cursor into the old result set.
    func testAReloadForgetsThePagingCursor() async {
        MockURLProtocol.respondWithJSON(feedBody(ids: [1], cursor: "page2"))
        let vm = makeViewModel()
        await vm.loadInitial()

        MockURLProtocol.respondWithJSON(feedBody(ids: [9], cursor: nil))
        await vm.loadInitial()

        var requestMade = false
        MockURLProtocol.handler = { request in
            requestMade = true
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(feedBody(ids: [99], cursor: nil).utf8), response)
        }
        await vm.loadMore()

        XCTAssertFalse(requestMade, "The exhausted second response should have ended paging")
        XCTAssertEqual(vm.galleries.map(\.title), ["Gallery 9"])
    }

    // MARK: - loadMore

    func testPagingAppendsTheNextPage() async {
        MockURLProtocol.respondWithJSON(feedBody(ids: [1], cursor: "page2"))
        let vm = makeViewModel()
        await vm.loadInitial()

        MockURLProtocol.respondWithJSON(feedBody(ids: [2, 3], cursor: nil))
        await vm.loadMore()

        XCTAssertEqual(vm.galleries.map(\.title), ["Gallery 1", "Gallery 2", "Gallery 3"])
    }

    /// Scrolling to the bottom fires this repeatedly.
    func testPagingStopsOnceTheServerRunsOut() async {
        MockURLProtocol.respondWithJSON(feedBody(ids: [1], cursor: "page2"))
        let vm = makeViewModel()
        await vm.loadInitial()

        MockURLProtocol.respondWithJSON(feedBody(ids: [2], cursor: nil))
        await vm.loadMore()

        var extraRequests = 0
        MockURLProtocol.handler = { request in
            extraRequests += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(feedBody(ids: [99], cursor: nil).utf8), response)
        }
        await vm.loadMore()

        XCTAssertEqual(extraRequests, 0)
        XCTAssertEqual(vm.galleries.count, 2)
    }

    func testThereIsNothingToPageBeforeTheFirstLoad() async {
        var requestMade = false
        MockURLProtocol.handler = { request in
            requestMade = true
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(feedBody(ids: [1], cursor: nil).utf8), response)
        }

        await makeViewModel().loadMore()

        XCTAssertFalse(requestMade)
    }

    func testAFailedPageKeepsWhatIsAlreadyOnScreen() async {
        MockURLProtocol.respondWithJSON(feedBody(ids: [1], cursor: "page2"))
        let vm = makeViewModel()
        await vm.loadInitial()

        MockURLProtocol.respondWithError(statusCode: 500)
        await vm.loadMore()

        XCTAssertEqual(vm.galleries.map(\.title), ["Gallery 1"])
        XCTAssertNotNil(vm.error)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Disk cache

    /// The cache exists so the feed renders before the first network response —
    /// a new view model on the same key has to see it without fetching.
    func testACachedFeedIsAvailableBeforeAnyRequest() async {
        // The cache files entries under the active account, so pointing that at
        // a synthetic DID keeps this out of the installed app's real cache.
        let did = "did:plc:feedvm-\(UUID().uuidString)"
        let savedAccount = AccountScopedStorage.activeAccountID
        AccountScopedStorage.activeAccountID = did
        defer {
            FeedCache.shared.purge(did: did)
            AccountScopedStorage.activeAccountID = savedAccount
        }
        let key = "feedvm-\(UUID().uuidString)"

        MockURLProtocol.respondWithJSON(feedBody(ids: [1, 2], cursor: nil))
        await makeViewModel(cacheKey: key).loadInitial()

        // The write is handed to a detached task, so give it a moment to land.
        try? await Task.sleep(for: .milliseconds(300))

        let restored = makeViewModel(cacheKey: key)
        XCTAssertEqual(restored.galleries.map(\.title), ["Gallery 1", "Gallery 2"])
        XCTAssertFalse(restored.hasFetchedInitial, "Cached content isn't a fetch")
    }

    func testAViewModelWithNoCacheKeyStartsEmpty() {
        XCTAssertTrue(makeViewModel().galleries.isEmpty)
    }

    // MARK: - Pinned feed convenience init

    /// A following or for-you feed is scoped to the viewer; the others aren't,
    /// and sending an actor on those would silently filter the feed.
    func testOnlyThePersonalFeedsCarryTheViewersDID() async {
        for (feed, expectsActor) in [
            (PinnedFeed.defaults[0], false),
            (PinnedFeed.defaults[1], true),
            (PinnedFeed.defaults[2], true),
        ] {
            let seen = ParamRecorder()
            MockURLProtocol.handler = { request in
                seen.record(request.url)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(feedBody(ids: [], cursor: nil).utf8), response)
            }

            let vm = FeedViewModel(client: client, pinnedFeed: feed, userDID: "did:plc:me")
            await vm.loadInitial()

            XCTAssertEqual(
                seen.value(for: "actor"), expectsActor ? "did:plc:me" : nil,
                "\(feed.id) sent the wrong actor"
            )
            XCTAssertEqual(seen.value(for: "feed"), feed.feedName)
        }
    }

    func testACameraFeedSendsTheCameraName() async {
        let seen = ParamRecorder()
        MockURLProtocol.handler = { request in
            seen.record(request.url)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(feedBody(ids: [], cursor: nil).utf8), response)
        }

        let feed = PinnedFeed(id: "camera:Leica M6", label: "Leica M6", type: "camera", path: "/c/leica")
        await FeedViewModel(client: client, pinnedFeed: feed).loadInitial()

        XCTAssertEqual(seen.value(for: "feed"), "camera")
        XCTAssertEqual(seen.value(for: "camera"), "Leica M6")
    }

    func testAHashtagFeedSendsTheTag() async {
        let seen = ParamRecorder()
        MockURLProtocol.handler = { request in
            seen.record(request.url)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(feedBody(ids: [], cursor: nil).utf8), response)
        }

        let feed = PinnedFeed(id: "hashtag:film", label: "#film", type: "hashtag", path: "/t/film")
        await FeedViewModel(client: client, pinnedFeed: feed).loadInitial()

        XCTAssertEqual(seen.value(for: "feed"), "hashtag")
        XCTAssertEqual(seen.value(for: "tag"), "film")
    }
}

/// Captures the URL a request went to, from off the main actor.
private final class ParamRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var url: URL?

    func record(_ url: URL?) {
        lock.withLock { self.url = url }
    }

    func value(for name: String) -> String? {
        let captured = lock.withLock { url }
        guard let captured,
              let items = URLComponents(url: captured, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        return items.first { $0.name == name }?.value
    }
}

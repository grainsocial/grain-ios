@testable import Grain
import XCTest

/// File scope, not a static member: `MockURLProtocol.handler` runs outside the
/// main actor, so anything it reads has to live outside a @MainActor class.
private func galleryJSON(
    _ id: Int,
    creator: String = "did:plc:someone",
    photos: Int = 1,
    thumb: String = "https://test.local/thumb.jpg"
) -> String {
    let items = (0 ..< photos).map { index in
        """
        {
          "uri": "at://\(creator)/social.grain.photo/\(id)-\(index)",
          "cid": "bafyp\(id)\(index)",
          "thumb": "\(thumb)",
          "fullsize": "https://test.local/full.jpg",
          "aspectRatio": {"width": 3, "height": 2}
        }
        """
    }.joined(separator: ",")
    return """
    {
      "uri": "at://\(creator)/social.grain.gallery/\(id)",
      "cid": "bafyg\(id)",
      "title": "Gallery \(id)",
      "creator": {"cid": "c1", "did": "\(creator)", "handle": "someone.test"},
      "items": [\(items)],
      "indexedAt": "2025-01-02T00:00:00Z"
    }
    """
}

private func feedJSON(_ galleries: [String], cursor: String?) -> String {
    let cursorJSON = cursor.map { "\"\($0)\"" } ?? "null"
    return "{\"items\": [\(galleries.joined(separator: ","))], \"cursor\": \(cursorJSON)}"
}

private func profileJSON(viewer: String = "{}") -> String {
    """
    {
      "cid": "bafycid",
      "did": "did:plc:someone",
      "handle": "someone.test",
      "displayName": "Someone",
      "followersCount": 10,
      "followsCount": 5,
      "galleryCount": 2,
      "viewer": \(viewer)
    }
    """
}

/// The favorites tab and the block/mute actions on a profile. Favorites are the
/// fiddly half: they're cached to disk, paged, and filtered — a gallery whose
/// thumbnail can't load would otherwise sit as a permanent blank tile.
@MainActor
final class ProfileFavoritesAndModerationTests: XCTestCase {
    private var client: XRPCClient!
    private var vm: ProfileDetailViewModel!
    private var auth: AuthContext!
    private var did = ""
    private var savedAccount: String?

    override func setUp() async throws {
        try await super.setUp()
        did = "did:plc:profilevm-\(UUID().uuidString)"
        // The favorites cache files entries under the active account; pointing
        // that at a synthetic DID keeps this out of the installed app's cache.
        savedAccount = AccountScopedStorage.activeAccountID
        AccountScopedStorage.activeAccountID = did
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        vm = ProfileDetailViewModel(client: client)
        auth = try AuthContext(accessToken: "token", dpop: DPoP.loadOrCreate(for: did))
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        FeedCache.shared.purge(did: did)
        AccountScopedStorage.activeAccountID = savedAccount
        try? DPoP.clearKey(for: did)
        try await super.tearDown()
    }

    // MARK: - Favorites hydration

    /// A favorited gallery whose photos are gone renders as a blank tile
    /// forever, because there is no image for the loader to even attempt.
    func testFavoritesWithNoPhotosAreDropped() async {
        MockURLProtocol.respondWithJSON(feedJSON([
            galleryJSON(1),
            galleryJSON(2, photos: 0),
        ], cursor: nil))

        await vm.loadFavorites(did: "did:plc:someone")

        XCTAssertEqual(vm.favoriteGalleries.map(\.title), ["Gallery 1"])
    }

    /// Same for a thumbnail URL that's empty or that `URL` won't parse — the
    /// loader can't start, so the tile never fills in.
    func testFavoritesWithAnUnusableThumbnailAreDropped() async {
        MockURLProtocol.respondWithJSON(feedJSON([
            galleryJSON(1),
            galleryJSON(2, thumb: ""),
        ], cursor: nil))

        await vm.loadFavorites(did: "did:plc:someone")

        XCTAssertEqual(vm.favoriteGalleries.map(\.title), ["Gallery 1"])
    }

    /// A thumbnail confirmed broken while scrolling shouldn't come back on the
    /// next load.
    func testAFavoriteKnownToBeBrokenIsDroppedOnReload() async {
        vm.brokenFavoriteUris = ["at://did:plc:someone/social.grain.gallery/1"]
        MockURLProtocol.respondWithJSON(feedJSON([galleryJSON(1), galleryJSON(2)], cursor: nil))

        await vm.loadFavorites(did: "did:plc:someone")

        XCTAssertEqual(vm.favoriteGalleries.map(\.title), ["Gallery 2"])
    }

    /// Marking one broken mid-scroll takes it off screen without a reload.
    func testMarkingAFavoriteBrokenHidesItImmediately() async {
        MockURLProtocol.respondWithJSON(feedJSON([galleryJSON(1), galleryJSON(2)], cursor: nil))
        await vm.loadFavorites(did: "did:plc:someone")
        XCTAssertEqual(vm.visibleFavorites.count, 2)

        vm.brokenFavoriteUris.insert("at://did:plc:someone/social.grain.gallery/1")

        XCTAssertEqual(vm.visibleFavorites.map(\.title), ["Gallery 2"])
        XCTAssertEqual(vm.favoriteGalleries.count, 2, "The list itself is untouched; only what's shown changes")
    }

    // MARK: - Favorites loading

    func testFavoritesOnlyLoadOnce() async {
        var requests = 0
        MockURLProtocol.handler = { request in
            requests += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(feedJSON([galleryJSON(1)], cursor: nil).utf8), response)
        }

        await vm.loadFavorites(did: "did:plc:someone")
        await vm.loadFavorites(did: "did:plc:someone")

        XCTAssertEqual(requests, 1)
        XCTAssertTrue(vm.favoritesLoaded)
        XCTAssertFalse(vm.isLoadingFavorites)
    }

    func testAFailedFavoritesLoadRecordsItsOwnError() async {
        MockURLProtocol.respondWithError(statusCode: 500)

        await vm.loadFavorites(did: "did:plc:someone")

        XCTAssertNotNil(vm.favoritesError)
        XCTAssertTrue(vm.favoriteGalleries.isEmpty)
        XCTAssertTrue(vm.favoritesLoaded, "A failure still counts as having tried")
        XCTAssertNil(vm.error, "A favorites failure must not blank the whole profile")
    }

    func testPagingFavoritesAppendsAndFilters() async {
        MockURLProtocol.respondWithJSON(feedJSON([galleryJSON(1)], cursor: "page2"))
        await vm.loadFavorites(did: "did:plc:someone")
        XCTAssertTrue(vm.hasMoreFavorites)

        MockURLProtocol.respondWithJSON(feedJSON([galleryJSON(2), galleryJSON(3, photos: 0)], cursor: nil))
        await vm.loadMoreFavorites(did: "did:plc:someone")

        XCTAssertEqual(vm.favoriteGalleries.map(\.title), ["Gallery 1", "Gallery 2"])
        XCTAssertFalse(vm.hasMoreFavorites)
    }

    /// Scrolling to the bottom fires this repeatedly.
    func testPagingFavoritesStopsWhenTheServerRunsOut() async {
        MockURLProtocol.respondWithJSON(feedJSON([galleryJSON(1)], cursor: nil))
        await vm.loadFavorites(did: "did:plc:someone")

        var requests = 0
        MockURLProtocol.handler = { request in
            requests += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(feedJSON([galleryJSON(9)], cursor: nil).utf8), response)
        }
        await vm.loadMoreFavorites(did: "did:plc:someone")

        XCTAssertEqual(requests, 0)
    }

    // MARK: - Story archive

    func testTheStoryArchiveOnlyLoadsOnce() async {
        var requests = 0
        MockURLProtocol.handler = { request in
            requests += 1
            let body = #"{"stories": [], "cursor": null}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }

        await vm.loadStoryArchive(did: "did:plc:someone")
        await vm.loadStoryArchive(did: "did:plc:someone")

        XCTAssertEqual(requests, 1)
    }

    /// The archive is a secondary tab; a failure there must not surface as a
    /// profile-level error.
    func testAFailedArchiveLoadIsSwallowed() async {
        MockURLProtocol.respondWithError(statusCode: 500)

        await vm.loadStoryArchive(did: "did:plc:someone")

        XCTAssertTrue(vm.archivedStories.isEmpty)
        XCTAssertNil(vm.error)
    }

    func testPagingTheArchiveAppends() async {
        let page1 = """
        {"stories": [{
          "uri": "at://did:plc:someone/social.grain.story/1", "cid": "c1",
          "creator": {"cid": "p1", "did": "did:plc:someone", "handle": "someone.test"},
          "thumb": "https://test.local/t.jpg", "fullsize": "https://test.local/f.jpg",
          "aspectRatio": {"width": 3, "height": 4}, "createdAt": "2025-01-02T00:00:00Z"
        }], "cursor": "page2"}
        """
        MockURLProtocol.respondWithJSON(page1)
        await vm.loadStoryArchive(did: "did:plc:someone")
        XCTAssertEqual(vm.archivedStories.count, 1)

        let page2 = """
        {"stories": [{
          "uri": "at://did:plc:someone/social.grain.story/2", "cid": "c2",
          "creator": {"cid": "p1", "did": "did:plc:someone", "handle": "someone.test"},
          "thumb": "https://test.local/t2.jpg", "fullsize": "https://test.local/f2.jpg",
          "aspectRatio": {"width": 3, "height": 4}, "createdAt": "2025-01-02T00:00:00Z"
        }], "cursor": null}
        """
        MockURLProtocol.respondWithJSON(page2)
        await vm.loadMoreArchive(did: "did:plc:someone")

        XCTAssertEqual(vm.archivedStories.count, 2)
    }

    // MARK: - Gallery paging

    func testPagingGalleriesAppendsUntilTheServerRunsOut() async {
        MockURLProtocol.respondByPath([
            "getActorProfile": profileJSON(),
            "getFeed": feedJSON([galleryJSON(1)], cursor: "page2"),
        ])
        await vm.load(did: "did:plc:someone")
        XCTAssertTrue(vm.hasMoreGalleries)

        MockURLProtocol.respondWithJSON(feedJSON([galleryJSON(2)], cursor: nil))
        await vm.loadMoreGalleries(did: "did:plc:someone")

        XCTAssertEqual(vm.galleries.map(\.title), ["Gallery 1", "Gallery 2"])
        XCTAssertFalse(vm.hasMoreGalleries)

        var requests = 0
        MockURLProtocol.handler = { request in
            requests += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(feedJSON([], cursor: nil).utf8), response)
        }
        await vm.loadMoreGalleries(did: "did:plc:someone")
        XCTAssertEqual(requests, 0)
    }

    // MARK: - Blocking

    func testAProfileIsHiddenInEitherDirectionOfABlock() async {
        MockURLProtocol.respondByPath(["getActorProfile": profileJSON(viewer: #"{"blocking": "at://b/1"}"#)])
        await vm.load(did: "did:plc:someone")
        XCTAssertTrue(vm.isBlockHidden)

        let other = ProfileDetailViewModel(client: client)
        MockURLProtocol.respondByPath(["getActorProfile": profileJSON(viewer: #"{"blockedBy": true}"#)])
        await other.load(did: "did:plc:someone")
        XCTAssertTrue(other.isBlockHidden)
    }

    func testAnUnblockedProfileIsNotHidden() async {
        MockURLProtocol.respondByPath(["getActorProfile": profileJSON()])
        await vm.load(did: "did:plc:someone")

        XCTAssertFalse(vm.isBlockHidden)
    }

    /// Blocking is applied optimistically so the content disappears on tap.
    func testBlockingHidesTheProfileImmediately() async {
        MockURLProtocol.respondByPath(["getActorProfile": profileJSON()])
        await vm.load(did: "did:plc:someone")

        MockURLProtocol.respondWithJSON(#"{"uri": "at://did:plc:test/social.grain.graph.block/1", "cid": "b"}"#)
        await vm.toggleBlock(auth: auth)

        XCTAssertNotNil(vm.profile?.viewer?.blocking)
        XCTAssertTrue(vm.isBlockHidden)
    }

    /// If the write fails the block has to come back off, or the profile stays
    /// blank for someone who isn't actually blocked.
    func testAFailedBlockIsRolledBack() async {
        MockURLProtocol.respondByPath(["getActorProfile": profileJSON()])
        await vm.load(did: "did:plc:someone")

        MockURLProtocol.respondWithError(statusCode: 500)
        await vm.toggleBlock(auth: auth)

        XCTAssertNil(vm.profile?.viewer?.blocking)
        XCTAssertFalse(vm.isBlockHidden)
    }

    func testUnblockingRestoresTheProfile() async {
        MockURLProtocol.respondByPath(["getActorProfile": profileJSON(viewer: #"{"blocking": "at://did:plc:test/social.grain.graph.block/1"}"#)])
        await vm.load(did: "did:plc:someone")
        XCTAssertTrue(vm.isBlockHidden)

        MockURLProtocol.respondWithJSON("{}")
        await vm.toggleBlock(auth: auth)

        XCTAssertNil(vm.profile?.viewer?.blocking)
        XCTAssertFalse(vm.isBlockHidden)
    }

    func testAFailedUnblockLeavesTheBlockInPlace() async {
        MockURLProtocol.respondByPath(["getActorProfile": profileJSON(viewer: #"{"blocking": "at://did:plc:test/social.grain.graph.block/1"}"#)])
        await vm.load(did: "did:plc:someone")

        MockURLProtocol.respondWithError(statusCode: 500)
        await vm.toggleBlock(auth: auth)

        XCTAssertNotNil(vm.profile?.viewer?.blocking)
    }

    /// Signed out there is nobody to block on behalf of.
    func testBlockingBailsWithoutAuth() async {
        MockURLProtocol.respondByPath(["getActorProfile": profileJSON()])
        await vm.load(did: "did:plc:someone")

        var requestMade = false
        MockURLProtocol.handler = { request in
            requestMade = true
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await vm.toggleBlock(auth: nil)

        XCTAssertFalse(requestMade)
    }

    func testBlockingBailsBeforeTheProfileHasLoaded() async {
        var requestMade = false
        MockURLProtocol.handler = { request in
            requestMade = true
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        await vm.toggleBlock(auth: auth)

        XCTAssertFalse(requestMade)
    }

    // MARK: - Muting

    func testMutingAndUnmutingFlipTheViewerState() async {
        MockURLProtocol.respondByPath(["getActorProfile": profileJSON()])
        await vm.load(did: "did:plc:someone")

        MockURLProtocol.respondWithJSON("{}")
        await vm.toggleMute(auth: auth)
        XCTAssertEqual(vm.profile?.viewer?.muted, true)

        MockURLProtocol.respondWithJSON("{}")
        await vm.toggleMute(auth: auth)
        XCTAssertNotEqual(vm.profile?.viewer?.muted, true)
    }

    func testAFailedMuteIsRolledBack() async {
        MockURLProtocol.respondByPath(["getActorProfile": profileJSON()])
        await vm.load(did: "did:plc:someone")

        MockURLProtocol.respondWithError(statusCode: 500)
        await vm.toggleMute(auth: auth)

        XCTAssertNotEqual(vm.profile?.viewer?.muted, true)
    }

    func testMutingBailsWithoutAuth() async {
        MockURLProtocol.respondByPath(["getActorProfile": profileJSON()])
        await vm.load(did: "did:plc:someone")

        var requestMade = false
        MockURLProtocol.handler = { request in
            requestMade = true
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await vm.toggleMute(auth: nil)

        XCTAssertFalse(requestMade)
    }
}

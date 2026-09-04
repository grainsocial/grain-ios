@testable import Grain
import XCTest

/// Records the exact request each endpoint puts on the wire.
private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    var count: Int {
        lock.withLock { requests.count }
    }

    var last: URLRequest? {
        lock.withLock { requests.last }
    }

    var lastPath: String? {
        last?.url?.path
    }

    var lastMethod: String? {
        last?.httpMethod
    }

    func lastQueryValue(_ name: String) -> String? {
        guard let url = last?.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        return items.first { $0.name == name }?.value
    }

    /// URLProtocol replaces `httpBody` with a stream, so read it back the way
    /// the loading system does.
    var lastBody: [String: Any]? {
        guard let request = last else { return nil }
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                guard read > 0 else { break }
                collected.append(buffer, count: read)
            }
            data = collected
        }
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// The lexicon names, HTTP verbs and parameter names each endpoint uses. These
/// are a contract with the server that nothing else in the suite pins down —
/// a renamed parameter compiles fine and fails only against a live PDS.
@MainActor
final class EndpointContractTests: GrainTestCase {
    private var client: XRPCClient!
    private var log: RequestLog!
    private var auth: AuthContext!
    private var did = ""

    override func setUp() async throws {
        try await super.setUp()
        did = "did:plc:endpoint-\(UUID().uuidString)"
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        auth = try AuthContext(accessToken: "token", dpop: DPoP.loadOrCreate(for: did))
        log = RequestLog()
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try? DPoP.clearKey(for: did)
        try await super.tearDown()
    }

    private func respond(_ body: String) {
        let log = log!
        MockURLProtocol.handler = { request in
            log.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    // MARK: - Moderation

    func testFetchingBlocksAndMutes() async throws {
        respond(Fixtures.blockList)
        let blocks = try await client.getBlocks(auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getBlocks")
        XCTAssertEqual(blocks.items?.map(\.did), ["did:plc:a", "did:plc:b"])
        XCTAssertEqual(blocks.items?.first?.id, "did:plc:a")

        respond(Fixtures.muteList)
        let mutes = try await client.getMutes(auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getMutes")
        XCTAssertEqual(mutes.items?.map(\.did), ["did:plc:a", "did:plc:b"])
        XCTAssertEqual(mutes.items?.first?.id, "did:plc:a")
    }

    /// A block is an ordinary record write, so it has to name the right
    /// collection or it lands as something else entirely.
    func testBlockingWritesAGraphBlockRecord() async throws {
        respond(#"{"uri": "at://did:plc:test/social.grain.graph.block/1", "cid": "bafy"}"#)

        let result = try await client.blockActor(did: "did:plc:someone", auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/dev.hatk.createRecord")
        XCTAssertEqual(log.lastMethod, "POST")
        XCTAssertEqual(log.lastBody?["collection"] as? String, "social.grain.graph.block")
        let record = log.lastBody?["record"] as? [String: Any]
        XCTAssertEqual(record?["subject"] as? String, "did:plc:someone")
        XCTAssertNotNil(record?["createdAt"])
        XCTAssertEqual(result.uri, "at://did:plc:test/social.grain.graph.block/1")
    }

    /// Unblocking deletes by record key, which has to be pulled out of the URI.
    func testUnblockingDeletesTheRecordNamedInTheURI() async throws {
        respond("{}")

        try await client.unblockActor(blockUri: "at://did:plc:test/social.grain.graph.block/3jzfcijpj2z2a", auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/dev.hatk.deleteRecord")
        XCTAssertEqual(log.lastBody?["collection"] as? String, "social.grain.graph.block")
        XCTAssertEqual(log.lastBody?["rkey"] as? String, "3jzfcijpj2z2a")
    }

    /// Muting is server-side rather than a record, so it takes the actor whole.
    func testMutingAndUnmutingNameTheActor() async throws {
        respond("{}")
        try await client.muteActor(did: "did:plc:someone", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.graph.muteActor")
        XCTAssertEqual(log.lastBody?["actor"] as? String, "did:plc:someone")

        try await client.unmuteActor(did: "did:plc:someone", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.graph.unmuteActor")
        XCTAssertEqual(log.lastBody?["actor"] as? String, "did:plc:someone")
    }

    func testReportingCarriesTheSubjectAsAStrongRef() async throws {
        respond("{}")

        try await client.createReport(
            subjectUri: "at://did:plc:test/social.grain.gallery/1",
            subjectCid: "bafygallery",
            label: "spam",
            reason: "Repeated posting",
            auth: auth
        )

        XCTAssertEqual(log.lastPath, "/xrpc/dev.hatk.createReport")
        XCTAssertEqual(log.lastBody?["label"] as? String, "spam")
        XCTAssertEqual(log.lastBody?["reason"] as? String, "Repeated posting")
        let subject = log.lastBody?["subject"] as? [String: Any]
        XCTAssertEqual(subject?["$type"] as? String, "com.atproto.repo.strongRef")
        XCTAssertEqual(subject?["uri"] as? String, "at://did:plc:test/social.grain.gallery/1")
        XCTAssertEqual(subject?["cid"] as? String, "bafygallery")
    }

    func testAReportWithNoReasonOmitsIt() async throws {
        respond("{}")

        try await client.createReport(
            subjectUri: "at://did:plc:test/social.grain.gallery/1",
            subjectCid: "bafygallery",
            label: "spam",
            auth: auth
        )

        XCTAssertNil(log.lastBody?["reason"])
    }

    func testLabelDefinitionsFallBackToEmptyWhenTheServerSendsNone() async throws {
        respond("{}")
        let definitions = try await client.describeLabels(auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/dev.hatk.describeLabels")
        XCTAssertTrue(definitions.isEmpty)
    }

    // MARK: - Favorites

    /// Both gallery and story favorites go through here, so the collection and
    /// the subject have to be right for either.
    func testFavoritingWritesAFavoriteRecordPointingAtItsSubject() async throws {
        respond(#"{"uri": "at://did:plc:test/social.grain.favorite/1", "cid": "bafy"}"#)

        let result = try await FavoriteService.create(
            subject: "at://did:plc:test/social.grain.gallery/1", client: client, auth: auth
        )

        XCTAssertEqual(log.lastPath, "/xrpc/dev.hatk.createRecord")
        XCTAssertEqual(log.lastBody?["collection"] as? String, "social.grain.favorite")
        let record = log.lastBody?["record"] as? [String: Any]
        XCTAssertEqual(record?["subject"] as? String, "at://did:plc:test/social.grain.gallery/1")
        XCTAssertNotNil(DateFormatting.parse(record?["createdAt"] as? String ?? ""))
        XCTAssertEqual(result.uri, "at://did:plc:test/social.grain.favorite/1")
    }

    func testUnfavoritingDeletesTheRecordNamedInTheURI() async throws {
        respond("{}")

        try await FavoriteService.delete(
            favoriteUri: "at://did:plc:test/social.grain.favorite/3jzfcijpj2z2a", client: client, auth: auth
        )

        XCTAssertEqual(log.lastPath, "/xrpc/dev.hatk.deleteRecord")
        XCTAssertEqual(log.lastBody?["collection"] as? String, FavoriteService.collection)
        XCTAssertEqual(log.lastBody?["rkey"] as? String, "3jzfcijpj2z2a")
    }

    /// A malformed URI must not send an empty delete off to the server as if it
    /// were meaningful — it still goes, but with an empty key the PDS rejects.
    func testAFavoriteURIWithNoRecordKeyYieldsAnEmptyKey() async throws {
        respond("{}")

        try await FavoriteService.delete(favoriteUri: "", client: client, auth: auth)

        XCTAssertEqual(log.lastBody?["rkey"] as? String, "")
    }

    // MARK: - Stories

    func testStoryEndpointsNameTheRightParameters() async throws {
        respond(Fixtures.stories)
        _ = try await client.getStories(actor: "did:plc:test", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getStories")
        XCTAssertEqual(log.lastQueryValue("actor"), "did:plc:test")

        respond(#"{"story": null}"#)
        _ = try await client.getStory(uri: "at://did:plc:test/social.grain.story/1", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getStory")
        XCTAssertEqual(log.lastQueryValue("story"), "at://did:plc:test/social.grain.story/1")

        respond(#"{"stories": [], "cursor": "next"}"#)
        let archive = try await client.getStoryArchive(actor: "did:plc:test", limit: 12, cursor: "here", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getStoryArchive")
        XCTAssertEqual(log.lastQueryValue("limit"), "12")
        XCTAssertEqual(log.lastQueryValue("cursor"), "here")
        XCTAssertEqual(archive.cursor, "next")

        respond(Fixtures.storyAuthors)
        let authors = try await client.getStoryAuthors(auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getStoryAuthors")
        XCTAssertEqual(authors.authors.count, 2)
    }

    /// A first page has no cursor to send; sending an empty one would be a
    /// different request.
    func testTheFirstArchivePageSendsNoCursor() async throws {
        respond(#"{"stories": []}"#)

        _ = try await client.getStoryArchive(actor: "did:plc:test", auth: auth)

        XCTAssertNil(log.lastQueryValue("cursor"))
    }

    // MARK: - Profile lists

    func testFollowListEndpointsCarryTheViewer() async throws {
        respond(Fixtures.actorList)
        _ = try await client.getFollowers(actor: "did:plc:test", viewer: "did:plc:me", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getFollowers")
        XCTAssertEqual(log.lastQueryValue("viewer"), "did:plc:me")

        respond(Fixtures.actorList)
        _ = try await client.getFollowing(actor: "did:plc:test", viewer: "did:plc:me", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getFollowing")

        respond(Fixtures.actorList)
        _ = try await client.getKnownFollowers(actor: "did:plc:test", viewer: "did:plc:me", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getKnownFollowers")

        respond(Fixtures.actorList)
        _ = try await client.getGalleryFavorites(gallery: "at://g/1", viewer: "did:plc:me", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getGalleryFavorites")
        XCTAssertEqual(log.lastQueryValue("gallery"), "at://g/1")
    }

    /// Signed out there is no viewer to send, and the parameter has to be left
    /// off rather than sent empty.
    func testAViewerlessRequestOmitsTheParameter() async throws {
        respond(Fixtures.actorList)

        _ = try await client.getFollowers(actor: "did:plc:test", auth: auth)

        XCTAssertNil(log.lastQueryValue("viewer"))
        XCTAssertEqual(log.lastQueryValue("actor"), "did:plc:test")
    }

    func testSuggestedFollowsDecodeIntoItems() async throws {
        respond(Fixtures.suggestedFollows)

        let response = try await client.getSuggestedFollows(actor: "did:plc:test", auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getSuggestedFollows")
        XCTAssertEqual(response.items?.map(\.did), ["did:plc:a", "did:plc:b"])
        XCTAssertEqual(response.items?.first?.id, "did:plc:a")
        XCTAssertEqual(response.items?.first?.followersCount, 120)
    }

    func testAProfileRequestCanCarryAViewer() async throws {
        respond(Fixtures.profileDetailed)

        let profile = try await client.getActorProfile(actor: "did:plc:test", viewer: "did:plc:me", auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getActorProfile")
        XCTAssertEqual(log.lastQueryValue("viewer"), "did:plc:me")
        XCTAssertEqual(profile.handle, "tester.grain.social")
        XCTAssertEqual(profile.id, "did:plc:test")
    }

    // MARK: - Records

    func testDeletingAGalleryUsesTheCascadingEndpoint() async throws {
        respond("{}")

        try await client.deleteGallery(rkey: "3jzfcijpj2z2a", auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.deleteGallery")
        XCTAssertEqual(log.lastBody?["rkey"] as? String, "3jzfcijpj2z2a")
    }

    func testDeletingTheAccountSendsAnEmptyBody() async throws {
        respond("{}")

        try await client.deleteAccount(auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.deleteAccount")
        XCTAssertEqual(log.lastBody?.isEmpty, true)
    }

    func testFetchingARecordByURI() async throws {
        respond(#"{"uri": "at://did:plc:test/social.grain.gallery/1", "cid": "bafy", "record": {"title": "A"}}"#)

        let response = try await client.getRecord(uri: "at://did:plc:test/social.grain.gallery/1", auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/dev.hatk.getRecord")
        XCTAssertEqual(log.lastQueryValue("uri"), "at://did:plc:test/social.grain.gallery/1")
        XCTAssertEqual(response.record?.dictValue?["title"]?.stringValue, "A")
    }

    /// A cross-post is written with `putRecord` so a resumed publish overwrites
    /// its own post rather than posting twice.
    func testPuttingARecordCarriesItsKeyAndRepo() async throws {
        respond(#"{"uri": "at://did:plc:test/app.bsky.feed.post/1", "cid": "bafy"}"#)

        _ = try await client.putRecord(
            collection: "app.bsky.feed.post",
            rkey: "3jzfcijpj2z2a",
            record: AnyCodable(["text": "Hello"]),
            repo: "did:plc:test",
            auth: auth
        )

        XCTAssertEqual(log.lastPath, "/xrpc/dev.hatk.putRecord")
        XCTAssertEqual(log.lastBody?["collection"] as? String, "app.bsky.feed.post")
        XCTAssertEqual(log.lastBody?["rkey"] as? String, "3jzfcijpj2z2a")
        XCTAssertEqual(log.lastBody?["repo"] as? String, "did:plc:test")
    }

    /// Every record in a gallery goes out in one atomic commit; a partial batch
    /// is exactly the failure the design avoids.
    func testApplyWritesSendsTheWholeBatchInOneRequest() async throws {
        respond(#"{"results": [{"uri": "at://a/1"}, {"uri": "at://a/2"}]}"#)

        let writes = [
            ApplyWrite.create(collection: "social.grain.photo", rkey: "p1", value: AnyCodable(["alt": "one"])),
            ApplyWrite.create(collection: "social.grain.gallery", rkey: "g1", value: AnyCodable(["title": "A"])),
        ]
        let response = try await client.applyWrites(writes, auth: auth)

        XCTAssertEqual(log.count, 1, "The batch must be one commit, not one request per record")
        XCTAssertEqual(log.lastPath, "/xrpc/dev.hatk.applyWrites")
        let sent = log.lastBody?["writes"] as? [[String: Any]]
        XCTAssertEqual(sent?.count, 2)
        XCTAssertEqual(sent?.first?["$type"] as? String, "dev.hatk.applyWrites#create")
        XCTAssertEqual(sent?.first?["rkey"] as? String, "p1")
        XCTAssertEqual(response.results?.count, 2)
    }

    // MARK: - Preferences

    func testTogglingTheLocationPreference() async throws {
        respond("{}")

        try await client.putIncludeLocation(false, auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/dev.hatk.putPreference")
        XCTAssertEqual(log.lastBody?["key"] as? String, "includeLocation")
        XCTAssertEqual(log.lastBody?["value"] as? Bool, false)
    }

    func testTogglingTheExifPreference() async throws {
        respond("{}")

        try await client.putIncludeExif(true, auth: auth)

        XCTAssertEqual(log.lastBody?["key"] as? String, "includeExif")
        XCTAssertEqual(log.lastBody?["value"] as? Bool, true)
    }

    func testPinnedFeedsAreSentUnderTheirOwnKey() async throws {
        respond("{}")

        try await client.putPinnedFeeds(PinnedFeed.defaults, auth: auth)

        XCTAssertEqual(log.lastBody?["key"] as? String, "pinnedFeeds")
        let feeds = log.lastBody?["value"] as? [[String: Any]]
        XCTAssertEqual(feeds?.count, 3)
        XCTAssertEqual(feeds?.first?["id"] as? String, "recent")
    }

    // MARK: - Discovery

    func testDiscoveryEndpointsDecodeTheirLists() async throws {
        respond(Fixtures.locations)
        let locations = try await client.getLocations(auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getLocations")
        XCTAssertEqual(locations.locations?.map(\.name), ["Lisboa", "Porto"])
        XCTAssertEqual(locations.locations?.first?.id, "8a2a1072b59ffff")

        respond(Fixtures.cameras)
        let cameras = try await client.getCameras(auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.unspecced.getCameras")
        XCTAssertEqual(cameras.cameras?.map(\.camera), ["Fujifilm X100V", "Leica M6"])
        XCTAssertEqual(cameras.cameras?.first?.id, "Fujifilm X100V")
    }

    // MARK: - Identity

    /// Every list in the app is diffed on these, so a model whose `id` stopped
    /// matching its DID would reshuffle rows on every refresh.
    func testEveryActorModelIsIdentifiedByItsDID() {
        XCTAssertEqual(GrainProfile(cid: "c", did: "did:plc:a", handle: "a.test").id, "did:plc:a")
        XCTAssertEqual(GrainProfileDetailed(cid: "c", did: "did:plc:a", handle: "a.test").id, "did:plc:a")
        XCTAssertEqual(FollowerItem(did: "did:plc:a").id, "did:plc:a")
        XCTAssertEqual(FollowingItem(did: "did:plc:a").id, "did:plc:a")
        XCTAssertEqual(FavoriteItem(did: "did:plc:a").id, "did:plc:a")
        XCTAssertEqual(SuggestedItem(did: "did:plc:a").id, "did:plc:a")
        XCTAssertEqual(ProfileSearchResult(did: "did:plc:a").id, "did:plc:a")
        XCTAssertEqual(BlockItem(did: "did:plc:a", blockUri: "at://b/1").id, "did:plc:a")
        XCTAssertEqual(MuteItem(did: "did:plc:a").id, "did:plc:a")
    }

    // MARK: - Location services

    /// The H3 index is what a location feed is keyed by, so a coordinate has to
    /// round trip back to roughly where it started.
    func testACoordinateRoundTripsThroughItsH3Cell() throws {
        let index = LocationServices.latLonToH3(latitude: 38.7223, longitude: -9.1393)
        XCTAssertFalse(index.isEmpty)

        let centre = try XCTUnwrap(LocationServices.h3ToCoordinate(index))
        XCTAssertEqual(centre.latitude, 38.7223, accuracy: 0.01)
        XCTAssertEqual(centre.longitude, -9.1393, accuracy: 0.01)
    }

    func testNearbyCoordinatesShareACellAndDistantOnesDoNot() {
        let lisbon = LocationServices.latLonToH3(latitude: 38.7223, longitude: -9.1393)
        let nextDoor = LocationServices.latLonToH3(latitude: 38.72231, longitude: -9.13931)
        let porto = LocationServices.latLonToH3(latitude: 41.1579, longitude: -8.6291)

        XCTAssertEqual(lisbon, nextDoor)
        XCTAssertNotEqual(lisbon, porto)
    }

    /// A deep link can carry any string; an unparseable one has to come back
    /// nil rather than trapping.
    func testAnInvalidH3IndexHasNoCoordinate() {
        XCTAssertNil(LocationServices.h3ToCoordinate("not-an-h3-index"))
        XCTAssertNil(LocationServices.h3ToCoordinate(""))
    }

    /// Nominatim needs two characters before it will return anything useful, so
    /// a one-letter query is answered without a request.
    func testATooShortLocationSearchNeverHitsTheNetwork() async {
        let results = await LocationServices.searchLocation(query: " a ")
        XCTAssertTrue(results.isEmpty)
    }
}

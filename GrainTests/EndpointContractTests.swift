@testable import Grain
import XCTest

/// Records the exact request each endpoint puts on the wire.
private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var indexCalls: [URLRequest] = []

    /// The `indexRecords` call that follows each write is kept apart, so
    /// `last` is the call under test.
    func record(_ request: URLRequest) {
        lock.withLock {
            if request.url?.path.hasSuffix("social.grain.sync.indexRecords") == true {
                indexCalls.append(request)
            } else {
                requests.append(request)
            }
        }
    }

    var indexRequests: [URLRequest] {
        lock.withLock { indexCalls }
    }

    /// The URIs each `indexRecords` call named, in order.
    var indexed: [[String]] {
        indexRequests.map { (Self.json($0)?["uris"] as? [String]) ?? [] }
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
        last.flatMap(Self.json)
    }

    static func json(_ request: URLRequest) -> [String: Any]? {
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
        auth = try AuthContext(accessToken: "token", dpop: DPoP.loadOrCreate(for: did), did: did, pds: URL(string: "https://test.local")!)
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
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.graph.getBlocks")
        XCTAssertEqual(blocks.items?.map(\.did), ["did:plc:a", "did:plc:b"])
        XCTAssertEqual(blocks.items?.first?.id, "did:plc:a")

        respond(Fixtures.muteList)
        let mutes = try await client.getMutes(auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.graph.getMutes")
        XCTAssertEqual(mutes.items?.map(\.did), ["did:plc:a", "did:plc:b"])
        XCTAssertEqual(mutes.items?.first?.id, "did:plc:a")
    }

    /// A block is an ordinary record write, so it has to name the right
    /// collection or it lands as something else entirely.
    func testBlockingWritesAGraphBlockRecord() async throws {
        respond(#"{"uri": "at://did:plc:test/social.grain.graph.block/1", "cid": "bafy"}"#)

        let result = try await client.blockActor(did: "did:plc:someone", auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/com.atproto.repo.createRecord")
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

        XCTAssertEqual(log.lastPath, "/xrpc/com.atproto.repo.deleteRecord")
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
        respond(#"{"id": 1, "reasonType": "com.atproto.moderation.defs#reasonSpam", "subject": {}, "reportedBy": "did:plc:me", "createdAt": "2026-01-01T00:00:00Z"}"#)

        try await client.createReport(
            subjectUri: "at://did:plc:test/social.grain.gallery/1",
            subjectCid: "bafygallery",
            label: "spam",
            reason: "Repeated posting",
            auth: auth
        )

        XCTAssertEqual(log.lastPath, "/xrpc/com.atproto.moderation.createReport")
        XCTAssertEqual(log.lastBody?["reasonType"] as? String, "com.atproto.moderation.defs#reasonSpam")
        XCTAssertNil(log.lastBody?["label"])
        XCTAssertEqual(log.lastBody?["reason"] as? String, "Repeated posting")
        let subject = log.lastBody?["subject"] as? [String: Any]
        XCTAssertEqual(subject?["$type"] as? String, "com.atproto.repo.strongRef")
        XCTAssertEqual(subject?["uri"] as? String, "at://did:plc:test/social.grain.gallery/1")
        XCTAssertEqual(subject?["cid"] as? String, "bafygallery")
    }

    /// A report is grain's to file, so the PDS forwards it to grain's
    /// AppView rather than to its own moderation service.
    func testAReportIsProxiedToGrain() async throws {
        respond("{}")

        try await client.createReport(subjectUri: "at://did:plc:test/social.grain.gallery/1", subjectCid: "c", label: "copyright", auth: auth)

        XCTAssertEqual(log.last?.value(forHTTPHeaderField: "atproto-proxy"), "\(AuthManager.appviewDID)#grain_appview")
        XCTAssertEqual(log.lastBody?["reasonType"] as? String, "social.grain.moderation.defs#reasonCopyright")
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

    // MARK: - Favorites

    /// Both gallery and story favorites go through here, so the collection and
    /// the subject have to be right for either.
    func testFavoritingWritesAFavoriteRecordPointingAtItsSubject() async throws {
        respond(#"{"uri": "at://did:plc:test/social.grain.favorite/1", "cid": "bafy"}"#)

        let result = try await FavoriteService.create(
            subject: "at://did:plc:test/social.grain.gallery/1", client: client, auth: auth
        )

        XCTAssertEqual(log.lastPath, "/xrpc/com.atproto.repo.createRecord")
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

        XCTAssertEqual(log.lastPath, "/xrpc/com.atproto.repo.deleteRecord")
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
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.story.getStories")
        XCTAssertEqual(log.lastQueryValue("actor"), "did:plc:test")

        respond(#"{"story": null}"#)
        _ = try await client.getStory(uri: "at://did:plc:test/social.grain.story/1", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.story.getStory")
        XCTAssertEqual(log.lastQueryValue("story"), "at://did:plc:test/social.grain.story/1")

        respond(#"{"stories": [], "cursor": "next"}"#)
        let archive = try await client.getStoryArchive(actor: "did:plc:test", limit: 12, cursor: "here", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.story.getArchive")
        XCTAssertEqual(log.lastQueryValue("limit"), "12")
        XCTAssertEqual(log.lastQueryValue("cursor"), "here")
        XCTAssertEqual(archive.cursor, "next")

        respond(Fixtures.storyAuthors)
        let authors = try await client.getStoryAuthors(auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.story.getAuthors")
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

    func testFollowListEndpointsHitTheirMethods() async throws {
        respond(Fixtures.actorList)
        _ = try await client.getFollowers(actor: "did:plc:test", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.graph.getFollowers")

        respond(Fixtures.actorList)
        _ = try await client.getFollowing(actor: "did:plc:test", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.graph.getFollowing")

        respond(Fixtures.actorList)
        _ = try await client.getKnownFollowers(actor: "did:plc:test", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.graph.getKnownFollowers")

        respond(Fixtures.actorList)
        _ = try await client.getGalleryFavorites(gallery: "at://g/1", auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.gallery.getFavorites")
        XCTAssertEqual(log.lastQueryValue("gallery"), "at://g/1")
    }

    /// The viewer is whoever the call is signed as, so no request names one.
    func testAListRequestNamesNoViewer() async throws {
        respond(Fixtures.actorList)

        _ = try await client.getFollowers(actor: "did:plc:test", auth: auth)

        XCTAssertNil(log.lastQueryValue("viewer"))
        XCTAssertEqual(log.lastQueryValue("actor"), "did:plc:test")
    }

    func testSuggestedFollowsDecodeIntoItems() async throws {
        respond(Fixtures.suggestedFollows)

        let response = try await client.getSuggestedFollows(actor: "did:plc:test", auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.actor.getSuggestedFollows")
        XCTAssertEqual(response.items?.map(\.did), ["did:plc:a", "did:plc:b"])
        XCTAssertEqual(response.items?.first?.id, "did:plc:a")
        XCTAssertEqual(response.items?.first?.followersCount, 120)
    }

    func testAProfileRequestNamesOnlyTheActor() async throws {
        respond(Fixtures.profileDetailed)

        let profile = try await client.getActorProfile(actor: "did:plc:test", auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.actor.getProfile")
        XCTAssertNil(log.lastQueryValue("viewer"))
        XCTAssertEqual(profile.handle, "tester.grain.social")
        XCTAssertEqual(profile.id, "did:plc:test")
    }

    // MARK: - Records

    func testFetchingARecordReadsItFromTheRepo() async throws {
        respond(#"{"uri": "at://did:plc:test/social.grain.gallery/1", "cid": "bafy", "value": {"title": "A"}}"#)

        let response = try await client.getRecord(uri: "at://did:plc:test/social.grain.gallery/1", auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/com.atproto.repo.getRecord")
        XCTAssertEqual(log.lastQueryValue("repo"), "did:plc:test")
        XCTAssertEqual(log.lastQueryValue("collection"), "social.grain.gallery")
        XCTAssertEqual(log.lastQueryValue("rkey"), "1")
        XCTAssertNil(log.last?.value(forHTTPHeaderField: "atproto-proxy"))
        XCTAssertEqual(response.value?.dictValue?["title"]?.stringValue, "A")
    }

    /// The account's grain records go at its own PDS first, grain's
    /// collections only, and grain-serve is then asked to forget it.
    func testDeletingTheAccountDeletesItsGrainRecordsThenAsksToBeForgotten() async throws {
        let log = try XCTUnwrap(log)
        let did = did
        MockURLProtocol.handler = { request in
            log.record(request)
            let path = request.url?.path ?? ""
            let body = if path.hasSuffix("describeRepo") {
                #"{"collections": ["app.bsky.feed.post", "social.grain.gallery"]}"#
            } else if path.hasSuffix("listRecords") {
                #"{"records": [{"uri": "at://\#(did)/social.grain.gallery/a"}, {"uri": "at://\#(did)/social.grain.gallery/b"}]}"#
            } else if path.hasSuffix("deleteAccount") {
                #"{"deleted": 0, "done": true}"#
            } else {
                "{}"
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }

        try await client.deleteAccount(auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.server.deleteAccount")
        XCTAssertEqual(log.lastBody?["did"] as? String, did)
        XCTAssertEqual(log.last?.value(forHTTPHeaderField: "atproto-proxy"), "\(AuthManager.appviewDID)#grain_appview")
        XCTAssertEqual(log.count, 4, "describeRepo, one collection listed, one commit, deleteAccount")
        XCTAssertTrue(log.indexRequests.isEmpty, "an account being forgotten has nothing to index")
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

        XCTAssertEqual(log.lastPath, "/xrpc/com.atproto.repo.putRecord")
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
        XCTAssertEqual(log.lastPath, "/xrpc/com.atproto.repo.applyWrites")
        let sent = log.lastBody?["writes"] as? [[String: Any]]
        XCTAssertEqual(sent?.count, 2)
        XCTAssertEqual(sent?.first?["$type"] as? String, "com.atproto.repo.applyWrites#create")
        XCTAssertEqual(sent?.first?["rkey"] as? String, "p1")
        XCTAssertEqual(response.results?.count, 2)
    }

    // MARK: - Writes at the PDS

    /// A write names the account's own repo and goes to its PDS unproxied;
    /// the AppView is then asked to index it, through the proxy.
    func testACreateGoesToTheRepoThenIsIndexed() async throws {
        respond(#"{"uri": "at://\#(did)/social.grain.favorite/1", "cid": "bafy"}"#)

        _ = try await client.createRecord(collection: "social.grain.favorite", repo: did, record: AnyCodable(["subject": "x"]), auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/com.atproto.repo.createRecord")
        XCTAssertEqual(log.lastBody?["repo"] as? String, did)
        XCTAssertNil(log.last?.value(forHTTPHeaderField: "atproto-proxy"))
        XCTAssertEqual(log.indexed, [["at://\(did)/social.grain.favorite/1"]])
        XCTAssertEqual(
            log.indexRequests.first?.value(forHTTPHeaderField: "atproto-proxy"),
            "\(AuthManager.appviewDID)#grain_appview"
        )
    }

    /// A delete is indexed too, so the AppView drops it at once.
    func testADeleteNamesTheRepoAndIndexesTheDeletedURI() async throws {
        respond("{}")

        try await client.deleteRecord(collection: "social.grain.comment", rkey: "c1", auth: auth)

        XCTAssertEqual(log.lastBody?["repo"] as? String, did)
        XCTAssertEqual(log.indexed, [["at://\(did)/social.grain.comment/c1"]])
    }

    /// A gallery's batch is indexed by the URIs its writes name, 25 at a time.
    func testAppliedWritesAreIndexedInBatchesOf25() async throws {
        respond(#"{"results": []}"#)
        let writes = (0 ..< 30).map {
            ApplyWrite.create(collection: "social.grain.photo", rkey: "p\($0)", value: AnyCodable(["alt": "x"]))
        }

        _ = try await client.applyWrites(writes, auth: auth)

        XCTAssertEqual(log.lastBody?["repo"] as? String, did)
        XCTAssertEqual(log.indexed.map(\.count), [25, 5])
        XCTAssertEqual(log.indexed.first?.first, "at://\(did)/social.grain.photo/p0")
    }

    /// An update and a delete in a batch carry atproto's own `$type`s.
    func testApplyWritesTypesAreAtprotos() throws {
        let update = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            ApplyWrite.update(collection: "social.grain.gallery", rkey: "g", value: AnyCodable(["title": "B"]))
        )) as? [String: Any]
        let delete = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            ApplyWrite.delete(collection: "social.grain.gallery", rkey: "g")
        )) as? [String: Any]

        XCTAssertEqual(update?["$type"] as? String, "com.atproto.repo.applyWrites#update")
        XCTAssertEqual(delete?["$type"] as? String, "com.atproto.repo.applyWrites#delete")
        XCTAssertNil(delete?["value"])
    }

    /// The write landed; the AppView failing to index it must not undo that
    /// in the user's eyes.
    func testAFailedIndexDoesNotFailTheWrite() async throws {
        let log = try XCTUnwrap(log)
        MockURLProtocol.handler = { request in
            log.record(request)
            let indexing = request.url?.path.hasSuffix("indexRecords") == true
            let response = HTTPURLResponse(url: request.url!, statusCode: indexing ? 500 : 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"uri": "at://did:plc:x/social.grain.favorite/1", "cid": "c"}"#.utf8), response)
        }

        let result = try await client.createRecord(collection: "social.grain.favorite", repo: did, record: AnyCodable(["subject": "x"]), auth: auth)

        XCTAssertEqual(result.uri, "at://did:plc:x/social.grain.favorite/1")
        XCTAssertEqual(log.indexRequests.count, 1)
    }

    /// A Bluesky cross-post is not the AppView's to index.
    func testABlueskyPostIsNotIndexed() async throws {
        respond(#"{"uri": "at://did:plc:test/app.bsky.feed.post/1", "cid": "bafy"}"#)

        _ = try await client.putRecord(collection: "app.bsky.feed.post", rkey: "1", record: AnyCodable(["text": "hi"]), auth: auth)

        XCTAssertEqual(log.lastBody?["repo"] as? String, did, "repo defaults to the signed-in account")
        XCTAssertTrue(log.indexRequests.isEmpty)
    }

    func testABlobGoesToTheRepo() async throws {
        respond(#"{"blob": {"$type": "blob", "ref": {"$link": "bafyblob"}, "mimeType": "image/jpeg", "size": 3}}"#)

        _ = try await client.uploadBlob(data: Data([1, 2, 3]), mimeType: "image/jpeg", auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/com.atproto.repo.uploadBlob")
        XCTAssertNil(log.last?.value(forHTTPHeaderField: "atproto-proxy"))
    }

    // MARK: - Discovery

    func testDiscoveryEndpointsDecodeTheirLists() async throws {
        respond(Fixtures.locations)
        let locations = try await client.getLocations(auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.gallery.getLocations")
        XCTAssertEqual(locations.locations?.map(\.name), ["Lisboa", "Porto"])
        XCTAssertEqual(locations.locations?.first?.id, "8a2a1072b59ffff")

        respond(Fixtures.cameras)
        let cameras = try await client.getCameras(auth: auth)
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.gallery.getCameras")
        XCTAssertEqual(cameras.cameras?.map(\.camera), ["Fujifilm X100V", "Leica M6"])
        XCTAssertEqual(cameras.cameras?.first?.id, "Fujifilm X100V")
    }

    /// The index tiles draw from these without a feed request per entry, and
    /// the map asks for the lean shape by name.
    func testDiscoveryCarriesThumbnailsAndAsksForPinsByName() async throws {
        respond(#"{"cameras": [{"camera": "Leica M6", "photoCount": 120, "thumbs": ["https://test.local/1.jpg"]}]}"#)
        let cameras = try await client.getCameras(auth: auth)
        XCTAssertEqual(cameras.cameras?.first?.thumbs, ["https://test.local/1.jpg"])

        respond(#"{"locations": [{"name": "Lisboa", "h3Index": "8a2a", "galleryCount": 3, "h3Cells": ["8a2a", "8a2b"], "thumbs": ["https://test.local/2.jpg"]}]}"#)
        let full = try await client.getLocations(auth: auth)
        XCTAssertNil(log.lastQueryValue("pins"))
        XCTAssertEqual(full.locations?.first?.h3Cells, ["8a2a", "8a2b"])
        XCTAssertEqual(full.locations?.first?.thumbs, ["https://test.local/2.jpg"])

        respond(Fixtures.locations)
        let pins = try await client.getLocations(pins: true, auth: auth)
        XCTAssertEqual(log.lastQueryValue("pins"), "true")
        XCTAssertNil(pins.locations?.first?.thumbs)
    }

    /// grain-serve answers getProfile for an account with no grain profile
    /// indexed, such as one signing in for the first time, with no `cid`.
    func testAProfileWithNoRecordDecodes() throws {
        let body = #"{"did":"did:plc:a","handle":"handle.invalid","followersCount":0,"followsCount":0,"galleryCount":0}"#
        let profile = try JSONDecoder().decode(GrainProfileDetailed.self, from: Data(body.utf8))
        XCTAssertNil(profile.cid)
        XCTAssertEqual(profile.did, "did:plc:a")
    }

    /// A notification from such an account names it with no `cid` either,
    /// and the whole list is lost if one does not decode.
    func testANotificationFromAnAccountWithNoProfileDecodes() throws {
        let body = #"{"notifications":[{"author":{"did":"did:plc:a","handle":"handle.invalid"},"createdAt":"2026-11-02T00:45:28.470Z","indexedAt":"2026-11-02T00:45:28.470Z","isRead":false,"reason":"follow","uri":"at://did:plc:a/social.grain.graph.follow/3mzc3v7xfjkd4"}]}"#
        let response = try JSONDecoder().decode(GetNotificationsResponse.self, from: Data(body.utf8))
        XCTAssertNil(response.notifications.first?.author.cid)
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

/// Preferences and feeds, which grain-serve takes in its own shapes.
extension EndpointContractTests {
    // MARK: - Preferences

    /// Serve the set `current` to a read and record what is written back.
    private func respondWithPreferences(_ current: String) {
        let log = log!
        MockURLProtocol.handler = { request in
            log.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = request.httpMethod == "GET" ? #"{"preferences": \#(current)}"# : "{}"
            return (Data(body.utf8), response)
        }
    }

    /// The written set, by `$type`.
    private var writtenPreferences: [String: [String: Any]] {
        let items = log.lastBody?["preferences"] as? [[String: Any]] ?? []
        return Dictionary(items.map { ($0["$type"] as? String ?? "", $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// One kind changes; the others, the web's theme among them, are written
    /// back as they were read.
    func testTogglingTheLocationPreferenceWritesTheWholeSetBack() async throws {
        respondWithPreferences(#"""
        [
          {"$type": "social.grain.actor.defs#pinnedFeedsPref", "items": [{"id": "recent", "label": "Recent", "type": "feed", "path": "/"}]},
          {"$type": "social.grain.actor.defs#photoMetadataPref", "includeExif": true, "includeLocation": true},
          {"$type": "social.grain.actor.defs#themePref", "theme": "dark"}
        ]
        """#)

        try await client.putIncludeLocation(false, auth: auth)

        XCTAssertEqual(log.count, 2, "read, then write")
        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.actor.putPreferences")
        let written = writtenPreferences
        XCTAssertEqual(written.count, 3)
        XCTAssertEqual(written["social.grain.actor.defs#photoMetadataPref"]?["includeLocation"] as? Bool, false)
        XCTAssertEqual(written["social.grain.actor.defs#photoMetadataPref"]?["includeExif"] as? Bool, true)
        XCTAssertEqual(written["social.grain.actor.defs#themePref"]?["theme"] as? String, "dark")
        XCTAssertEqual((written["social.grain.actor.defs#pinnedFeedsPref"]?["items"] as? [[String: Any]])?.first?["id"] as? String, "recent")
    }

    func testTogglingTheExifPreference() async throws {
        respondWithPreferences("[]")

        try await client.putIncludeExif(true, auth: auth)

        XCTAssertEqual(writtenPreferences["social.grain.actor.defs#photoMetadataPref"]?["includeExif"] as? Bool, true)
        XCTAssertNil(writtenPreferences["social.grain.actor.defs#photoMetadataPref"]?["includeLocation"])
    }

    func testPinnedFeedsAreSentAsTheirOwnKind() async throws {
        respondWithPreferences("[]")

        try await client.putPinnedFeeds(PinnedFeed.defaults, auth: auth)

        let feeds = writtenPreferences["social.grain.actor.defs#pinnedFeedsPref"]?["items"] as? [[String: Any]]
        XCTAssertEqual(feeds?.count, 3)
        XCTAssertEqual(feeds?.first?["id"] as? String, "recent")
    }

    func testNotificationPreferencesCarryTheirKindsBesideTheirType() async throws {
        respondWithPreferences("[]")

        try await client.putNotificationPrefs(NotificationPrefs(follows: NotifPref(push: false, inApp: true, from: "follows")), auth: auth)

        let prefs = writtenPreferences["social.grain.actor.defs#notificationsPref"]
        let follows = prefs?["follows"] as? [String: Any]
        XCTAssertEqual(follows?["push"] as? Bool, false)
        XCTAssertEqual(follows?["from"] as? String, "follows")
        XCTAssertNil(prefs?["favorites"])
    }

    func testPreferencesDecodeFromTheirKinds() throws {
        let json = #"""
        {"preferences": [
          {"$type": "social.grain.actor.defs#notificationsPref", "comments": {"push": true, "inApp": false, "from": "all"}},
          {"$type": "social.grain.actor.defs#photoMetadataPref", "includeExif": false},
          {"$type": "social.grain.actor.defs#somethingNew", "x": 1}
        ]}
        """#
        let prefs = try JSONDecoder().decode(GetPreferencesResponse.self, from: Data(json.utf8)).preferences

        XCTAssertEqual(prefs.includeExif, false)
        XCTAssertNil(prefs.includeLocation)
        XCTAssertNil(prefs.pinnedFeeds)
        XCTAssertEqual(prefs.notificationPrefs?.comments, NotifPref(push: true, inApp: false, from: "all"))
    }

    // MARK: - Feeds

    /// A feed is named by its URI on grain-serve's DID, its name the last
    /// segment.
    func testAFeedIsAskedForByItsURI() async throws {
        respond(Fixtures.feed)

        _ = try await client.getFeed(feed: "camera", camera: "Leica M6", auth: auth)

        XCTAssertEqual(log.lastPath, "/xrpc/social.grain.feed.getFeed")
        XCTAssertEqual(log.lastQueryValue("feed"), "at://\(AuthManager.appviewDID)/social.grain.feed.generator/camera")
        XCTAssertEqual(log.lastQueryValue("camera"), "Leica M6")
    }
}

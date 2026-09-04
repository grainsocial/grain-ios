@testable import Grain
import XCTest

/// Captures the record the cross-post actually writes.
private final class PostLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    var count: Int {
        lock.withLock { requests.count }
    }

    private var last: URLRequest? {
        lock.withLock { requests.last }
    }

    var lastPath: String? {
        last?.url?.path
    }

    var lastBody: [String: Any]? {
        guard let request = last else { return nil }
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            let size = 8192
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

    var lastRecord: [String: Any]? {
        lastBody?["record"] as? [String: Any]
    }
}

/// The record a gallery's Bluesky cross-post writes. Its shape has to match the
/// web client's byte for byte — a wrong `$type` or a facet whose byte offsets
/// drift shows up as a mangled post on someone's timeline, not as an error.
///
/// `buildPostText` already has its own suite; this covers what happens to that
/// text afterwards: facets, the image embed, and which write verb is used.
@MainActor
final class BlueskyCrossPostTests: XCTestCase {
    private var client: XRPCClient!
    private var log: PostLog!
    private var auth: AuthContext!
    private var did = ""

    override func setUp() async throws {
        try await super.setUp()
        did = "did:plc:bsky-\(UUID().uuidString)"
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        auth = try AuthContext(accessToken: "token", dpop: DPoP.loadOrCreate(for: did))
        log = PostLog()

        let log = log!
        MockURLProtocol.handler = { request in
            log.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"uri": "at://did:plc:test/app.bsky.feed.post/1", "cid": "bafy"}"#.utf8), response)
        }
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try? DPoP.clearKey(for: did)
        try await super.tearDown()
    }

    private func blob(_ link: String = "bafyblob") -> BlobRef {
        BlobRef(type: "blob", ref: BlobRef.BlobLink(link: link), mimeType: "image/jpeg", size: 1234)
    }

    private func options(
        title: String? = "Golden hour",
        description: String? = nil,
        location: (name: String, address: [String: AnyCodable]?)? = nil,
        images: [(blob: BlobRef, alt: String, width: Int, height: Int)] = []
    ) -> BlueskyPostOptions {
        BlueskyPostOptions(
            url: "https://grain.social/profile/did:plc:test/gallery/1",
            title: title,
            location: location,
            description: description,
            images: images
        )
    }

    private func post(
        _ options: BlueskyPostOptions,
        rkey: String? = nil
    ) async throws {
        try await BlueskyPost.create(
            options: options,
            client: client,
            repo: "did:plc:test",
            auth: auth,
            rkey: rkey,
            createdAt: "2025-01-02T00:00:00.000Z"
        )
    }

    // MARK: - Record shape

    func testTheRecordCarriesTheTextAndTheGrainTag() async throws {
        try await post(options())

        let record = try XCTUnwrap(log.lastRecord)
        XCTAssertEqual(record["tags"] as? [String], ["grainsocial"])
        XCTAssertEqual(record["createdAt"] as? String, "2025-01-02T00:00:00.000Z")
        let text = try XCTUnwrap(record["text"] as? String)
        XCTAssertTrue(text.contains("Golden hour"))
        XCTAssertTrue(text.contains("https://grain.social/profile/did:plc:test/gallery/1"))
    }

    /// The cross-post is written under a record key the draft assigned, so a
    /// resumed publish overwrites its own post rather than posting twice.
    func testAKeyedCrossPostOverwritesRatherThanPostsAgain() async throws {
        try await post(options(), rkey: "3jzfcijpj2z2a")

        XCTAssertEqual(log.lastPath, "/xrpc/dev.hatk.putRecord")
        XCTAssertEqual(log.lastBody?["rkey"] as? String, "3jzfcijpj2z2a")
        XCTAssertEqual(log.lastBody?["collection"] as? String, "app.bsky.feed.post")
        XCTAssertEqual(log.lastBody?["repo"] as? String, "did:plc:test")
    }

    func testAnUnkeyedCrossPostCreatesANewRecord() async throws {
        try await post(options())

        XCTAssertEqual(log.lastPath, "/xrpc/dev.hatk.createRecord")
        XCTAssertEqual(log.lastBody?["collection"] as? String, "app.bsky.feed.post")
    }

    // MARK: - Image embed

    func testImagesBecomeABlueskyImageEmbed() async throws {
        try await post(options(images: [
            (blob: blob("bafyone"), alt: "First photo", width: 3000, height: 2000),
        ]))

        let record = try XCTUnwrap(log.lastRecord)
        let embed = try XCTUnwrap(record["embed"] as? [String: Any])
        XCTAssertEqual(embed["$type"] as? String, "app.bsky.embed.images")

        let images = try XCTUnwrap(embed["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0]["alt"] as? String, "First photo")

        let image = try XCTUnwrap(images[0]["image"] as? [String: Any])
        XCTAssertEqual(image["$type"] as? String, "blob")
        XCTAssertEqual(image["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(image["size"] as? Int, 1234)
        XCTAssertEqual((image["ref"] as? [String: Any])?["$link"] as? String, "bafyone")

        let ratio = try XCTUnwrap(images[0]["aspectRatio"] as? [String: Any])
        XCTAssertEqual(ratio["width"] as? Int, 3000)
        XCTAssertEqual(ratio["height"] as? Int, 2000)
    }

    /// Bluesky takes at most four images; sending more is rejected outright.
    func testOnlyTheFirstFourImagesAreEmbedded() async throws {
        let images = (0 ..< 7).map {
            (blob: blob("bafy\($0)"), alt: "Photo \($0)", width: 100, height: 100)
        }

        try await post(options(images: images))

        let embed = try XCTUnwrap(log.lastRecord?["embed"] as? [String: Any])
        let embedded = try XCTUnwrap(embed["images"] as? [[String: Any]])
        XCTAssertEqual(embedded.count, 4)
        XCTAssertEqual(embedded.first?["alt"] as? String, "Photo 0")
        XCTAssertEqual(embedded.last?["alt"] as? String, "Photo 3")
    }

    /// A gallery with no blobs yet must not send an empty embed — Bluesky
    /// rejects one.
    func testAPostWithNoImagesHasNoEmbed() async throws {
        try await post(options())

        XCTAssertNil(log.lastRecord?["embed"])
    }

    /// A blob missing its optional fields still has to produce a well-formed
    /// embed rather than nulls the server won't take.
    func testAnIncompleteBlobFallsBackToDefaults() async throws {
        let bare = BlobRef(type: nil, ref: nil, mimeType: nil, size: nil)

        try await post(options(images: [(blob: bare, alt: "", width: 1, height: 1)]))

        let embed = try XCTUnwrap(log.lastRecord?["embed"] as? [String: Any])
        let image = try XCTUnwrap((embed["images"] as? [[String: Any]])?.first?["image"] as? [String: Any])
        XCTAssertEqual(image["$type"] as? String, "blob")
        XCTAssertEqual(image["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(image["size"] as? Int, 0)
        XCTAssertEqual((image["ref"] as? [String: Any])?["$link"] as? String, "")
    }

    // MARK: - Facets in the written record

    /// The gallery link is always in the text, so every cross-post carries at
    /// least one link facet — without it the URL posts as plain text.
    func testTheGalleryLinkIsFacetedAsALink() async throws {
        try await post(options())

        let facets = try XCTUnwrap(log.lastRecord?["facets"] as? [[String: Any]])
        let features = facets.flatMap { ($0["features"] as? [[String: Any]]) ?? [] }
        XCTAssertTrue(features.contains { $0["$type"] as? String == "app.bsky.richtext.facet#link" })
        XCTAssertTrue(features.contains {
            $0["uri"] as? String == "https://grain.social/profile/did:plc:test/gallery/1"
        })
    }

    func testAHashtagInTheDescriptionIsFacetedAsATag() async throws {
        try await post(options(description: "Shot on #Portra400 in the morning."))

        let facets = try XCTUnwrap(log.lastRecord?["facets"] as? [[String: Any]])
        let features = facets.flatMap { ($0["features"] as? [[String: Any]]) ?? [] }
        let tags = features.filter { $0["$type"] as? String == "app.bsky.richtext.facet#tag" }
        XCTAssertTrue(tags.contains { $0["tag"] as? String == "Portra400" })
    }

    /// Every facet's byte range has to land inside the text it annotates, or
    /// Bluesky renders the link over the wrong characters.
    func testEveryFacetPointsAtRealBytesOfTheText() async throws {
        try await post(options(title: "A café gallery", description: "Shot on #Portra400 ☕️"))

        let record = try XCTUnwrap(log.lastRecord)
        let text = try XCTUnwrap(record["text"] as? String)
        let byteCount = text.utf8.count
        let facets = try XCTUnwrap(record["facets"] as? [[String: Any]])

        for facet in facets {
            let index = try XCTUnwrap(facet["index"] as? [String: Any])
            let start = try XCTUnwrap(index["byteStart"] as? Int)
            let end = try XCTUnwrap(index["byteEnd"] as? Int)
            XCTAssertGreaterThanOrEqual(start, 0)
            XCTAssertGreaterThan(end, start)
            XCTAssertLessThanOrEqual(end, byteCount, "A facet runs past the end of the text")
        }
    }

    // MARK: - parseTextToFacets

    func testAPlainSentenceHasNoFacets() async {
        let facets = await BlueskyPost.parseTextToFacets("Just a caption with nothing special in it.")
        XCTAssertTrue(facets.isEmpty)
    }

    func testEmptyTextHasNoFacets() async {
        let facets = await BlueskyPost.parseTextToFacets("")
        XCTAssertTrue(facets.isEmpty)
    }

    func testAURLIsFacetedWithItsOwnByteRange() async throws {
        let text = "See https://grain.social/x for more"
        let facets = await BlueskyPost.parseTextToFacets(text)

        XCTAssertEqual(facets.count, 1)
        let facet = try XCTUnwrap(facets.first)
        let bytes = Array(text.utf8)[facet.index.byteStart ..< facet.index.byteEnd]
        XCTAssertEqual(String(bytes: bytes, encoding: .utf8), "https://grain.social/x")
        guard case let .link(uri) = facet.features.first else {
            return XCTFail("Expected a link feature")
        }
        XCTAssertEqual(uri, "https://grain.social/x")
    }

    func testHashtagsAreFacetedWithoutTheHash() async throws {
        let text = "Filed under #portra400 and #kodak"
        let facets = await BlueskyPost.parseTextToFacets(text)

        let tags: [String] = facets.compactMap { facet in
            if case let .tag(tag) = facet.features.first {
                return tag
            }
            return nil
        }
        XCTAssertEqual(tags, ["portra400", "kodak"])

        // The byte range covers the "#" too, so the whole token is highlighted.
        let first = try XCTUnwrap(facets.first)
        let bytes = Array(text.utf8)[first.index.byteStart ..< first.index.byteEnd]
        XCTAssertEqual(String(bytes: bytes, encoding: .utf8), "#portra400")
    }

    /// The pattern is `#\p{L}…`, so a tag has to start with a letter. That rules
    /// out the film-stock tags this app is full of — `#35mm`, `#120` — which
    /// cross-post as plain text rather than as links. Pinned because it matches
    /// `RichTextView`'s in-app parsing, not because a photography app obviously
    /// wants it.
    func testATagStartingWithADigitIsNotFaceted() async {
        let facets = await BlueskyPost.parseTextToFacets("Shot on #35mm and #120")

        let tags = facets.filter {
            if case .tag = $0.features.first {
                true
            } else {
                false
            }
        }
        XCTAssertTrue(tags.isEmpty)
    }

    /// Emoji ahead of a facet push the byte offsets away from the character
    /// offsets, which is exactly where an offset bug shows up.
    func testByteOffsetsSurviveEmojiEarlierInTheText() async throws {
        let text = "📷☕️ shot at https://grain.social/x"
        let facets = await BlueskyPost.parseTextToFacets(text)

        let facet = try XCTUnwrap(facets.first)
        let bytes = Array(text.utf8)[facet.index.byteStart ..< facet.index.byteEnd]
        XCTAssertEqual(String(bytes: bytes, encoding: .utf8), "https://grain.social/x")
        XCTAssertGreaterThan(facet.index.byteStart, text.distance(from: text.startIndex, to: text.startIndex))
    }

    /// URLs are claimed before hashtags, so a fragment inside a link must not
    /// also be parsed as a tag.
    func testAFragmentInsideALinkIsNotAlsoAHashtag() async {
        let facets = await BlueskyPost.parseTextToFacets("See https://grain.social/x#section for more")

        let tags = facets.filter {
            if case .tag = $0.features.first {
                true
            } else {
                false
            }
        }
        XCTAssertTrue(tags.isEmpty, "The link claimed those bytes first")
    }

    func testFacetsComeBackInTextOrder() async {
        let facets = await BlueskyPost.parseTextToFacets("#first then https://grain.social/x then #last")

        let starts = facets.map(\.index.byteStart)
        XCTAssertEqual(starts, starts.sorted())
        XCTAssertEqual(facets.count, 3)
    }
}

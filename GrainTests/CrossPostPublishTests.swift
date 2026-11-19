import CryptoKit
@testable import Grain
import XCTest

/// Records every write the publish makes.
private final class PublishLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(path: String, body: Data?)] = []

    func record(path: String, body: Data?) {
        lock.withLock { entries.append((path, body)) }
    }

    func count(_ nsid: String) -> Int {
        lock.withLock { entries.count { $0.path.hasSuffix(nsid) } }
    }

    func bodies(_ nsid: String) -> [[String: Any]] {
        lock.withLock {
            entries
                .filter { $0.path.hasSuffix(nsid) }
                .compactMap(\.body)
                .compactMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        }
    }
}

@MainActor
private final class StubAuth: AuthContextProviding {
    private let context: AuthContext?

    init(signedIn: Bool = true) {
        context = signedIn
            ? AuthContext(accessToken: "test-token", dpop: DPoP(privateKey: P256.Signing.PrivateKey()), did: "did:plc:test", pds: URL(string: "https://test.local")!)
            : nil
    }

    func authContext() async -> AuthContext? {
        context
    }
}

/// A GET has no body: its query as a JSON object, logged in its place.
private func queryAsBody(of request: URLRequest) -> Data? {
    let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
    return try? JSONSerialization.data(withJSONObject: query)
}

private func bodyData(of request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let size = 8192
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: size)
        guard read > 0 else { break }
        data.append(buffer, count: read)
    }
    return data
}

/// Publishing a gallery that also goes to Bluesky.
///
/// The cross-post runs after the gallery's own atomic commit and is deliberately
/// best-effort: Bluesky being down must not fail a gallery that is already live
/// on the PDS. It is also the one write that can duplicate — hence the record
/// key carried on the draft.
@MainActor
final class CrossPostPublishTests: GrainTestCase {
    private var root: URL!
    private var store: GalleryDraftStore!
    private var center: GalleryUploadCenter!
    private var client: XRPCClient!
    private var log: PublishLog!

    override func setUp() async throws {
        try await super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("crosspost-\(UUID().uuidString)", isDirectory: true)
        store = GalleryDraftStore(root: root)
        center = GalleryUploadCenter(store: store)
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        log = PublishLog()
        respondOK()
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func respondOK() {
        let log = log!
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if path.hasSuffix("social.grain.gallery.getCrossPost") {
                log.record(path: path, body: queryAsBody(of: request))
                let post = #"{"post": {"$type": "app.bsky.feed.post", "text": "Golden hour", "tags": ["grainsocial"], "createdAt": "2025-01-01T00:00:00.000Z"}}"#
                return (Data(post.utf8), response)
            }
            log.record(path: path, body: bodyData(of: request))
            let body = #"{"uri": "at://did:plc:test/x/1", "cid": "bafy", "results": [], "blob": {"$type": "blob", "ref": {"$link": "bafyblob"}, "mimeType": "image/jpeg", "size": 10}}"#
            return (Data(body.utf8), response)
        }
    }

    /// A draft whose photos are already uploaded, so publishing goes straight to
    /// the commit and then the cross-post.
    private func draft(
        postToBluesky: Bool,
        title: String = "Golden hour",
        description: String = "Shot on Portra.",
        location: GalleryDraft.Location? = nil
    ) -> GalleryDraft {
        let photo = GalleryDraft.Photo(
            id: UUID(),
            fileName: "photo.jpg",
            width: 3000,
            height: 2000,
            alt: "A quiet street",
            exif: nil,
            photoRkey: TID.next(),
            exifRkey: TID.next(),
            itemRkey: TID.next(),
            blob: BlobRef(
                type: "blob",
                ref: BlobRef.BlobLink(link: "bafyalready"),
                mimeType: "image/jpeg",
                size: 1234
            )
        )
        return GalleryDraft(
            repo: "did:plc:test",
            title: title,
            description: description,
            labels: [],
            location: location,
            includeExif: false,
            postToBluesky: postToBluesky,
            createdAt: DateFormatting.nowISO(),
            galleryRkey: TID.next(),
            blueskyRkey: TID.next(),
            photos: [photo]
        )
    }

    // MARK: - Whether it cross-posts at all

    func testAGalleryWithCrossPostingOffWritesNoBlueskyPost() async {
        let published = await center.publish(draft(postToBluesky: false), client: client, auth: StubAuth())

        XCTAssertTrue(published)
        XCTAssertEqual(center.stage, .finished)
        XCTAssertEqual(log.count("com.atproto.repo.putRecord"), 0, "Nothing should have been posted to Bluesky")
        XCTAssertEqual(log.count("com.atproto.repo.applyWrites"), 1, "The gallery itself still commits")
    }

    /// The post is the one grain-serve words for the gallery just committed,
    /// written as it came.
    func testAGalleryWithCrossPostingOnAlsoPostsToBluesky() async {
        let outgoing = draft(postToBluesky: true)

        let published = await center.publish(outgoing, client: client, auth: StubAuth())

        XCTAssertTrue(published)
        XCTAssertEqual(log.bodies("social.grain.gallery.getCrossPost").first?["subject"] as? String, outgoing.galleryUri)
        XCTAssertEqual(log.count("com.atproto.repo.putRecord"), 1)
        let record = log.bodies("com.atproto.repo.putRecord").first?["record"] as? [String: Any]
        XCTAssertEqual(record?["text"] as? String, "Golden hour")
        XCTAssertEqual(record?["tags"] as? [String], ["grainsocial"])
    }

    /// The cross-post is written under the key and timestamp the draft
    /// assigned, so a resumed publish overwrites its own post instead of
    /// posting a second time.
    func testTheCrossPostUsesTheDraftsOwnRecordKeyAndTimestamp() async {
        let outgoing = draft(postToBluesky: true)

        _ = await center.publish(outgoing, client: client, auth: StubAuth())

        let body = log.bodies("com.atproto.repo.putRecord").first
        XCTAssertEqual(body?["rkey"] as? String, outgoing.blueskyRkey)
        XCTAssertEqual(body?["collection"] as? String, "app.bsky.feed.post")
        XCTAssertEqual(body?["repo"] as? String, "did:plc:test")
        XCTAssertEqual((body?["record"] as? [String: Any])?["createdAt"] as? String, outgoing.createdAt)
    }

    // MARK: - When Bluesky is the thing that fails

    /// The gallery is already live on the PDS by this point. A cross-post that
    /// fails must not report the whole publish as failed and send the user back
    /// to a retry that would re-commit the gallery.
    func testAFailedCrossPostStillCountsAsPublished() async throws {
        let log = try XCTUnwrap(log)
        var seenCommit = false
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            log.record(path: path, body: bodyData(of: request))
            if path.hasSuffix("com.atproto.repo.applyWrites") {
                seenCommit = true
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(#"{"results": []}"#.utf8), response)
            }
            if path.hasSuffix("com.atproto.repo.putRecord") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (Data("bluesky is down".utf8), response)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        let published = await center.publish(draft(postToBluesky: true), client: client, auth: StubAuth())

        XCTAssertTrue(seenCommit)
        XCTAssertTrue(published, "The gallery is live; a failed cross-post must not undo that")
        XCTAssertEqual(center.stage, .finished)
    }

    // MARK: - Signed out

    /// Without a context there is nothing to write with, so the publish fails
    /// rather than silently doing nothing.
    func testPublishingWithoutASessionFails() async {
        let published = await center.publish(draft(postToBluesky: true), client: client, auth: StubAuth(signedIn: false))

        XCTAssertFalse(published)
        XCTAssertEqual(log.count("com.atproto.repo.applyWrites"), 0)
        if case .failed = center.stage {
            // expected
        } else {
            XCTFail("Expected a failure stage, got \(center.stage)")
        }
    }
}

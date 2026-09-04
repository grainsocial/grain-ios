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
            ? AuthContext(accessToken: "test-token", dpop: DPoP(privateKey: P256.Signing.PrivateKey()))
            : nil
    }

    func authContext() async -> AuthContext? {
        context
    }
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
final class CrossPostPublishTests: XCTestCase {
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
            log.record(path: request.url?.path ?? "", body: bodyData(of: request))
            let body = #"{"uri": "at://did:plc:test/x/1", "cid": "bafy", "results": [], "blob": {"$type": "blob", "ref": {"$link": "bafyblob"}, "mimeType": "image/jpeg", "size": 10}}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
        XCTAssertEqual(log.count("dev.hatk.putRecord"), 0, "Nothing should have been posted to Bluesky")
        XCTAssertEqual(log.count("dev.hatk.applyWrites"), 1, "The gallery itself still commits")
    }

    func testAGalleryWithCrossPostingOnAlsoPostsToBluesky() async {
        let published = await center.publish(draft(postToBluesky: true), client: client, auth: StubAuth())

        XCTAssertTrue(published)
        XCTAssertEqual(log.count("dev.hatk.putRecord"), 1)

        let record = log.bodies("dev.hatk.putRecord").first?["record"] as? [String: Any]
        XCTAssertEqual((record?["tags"] as? [String]), ["grainsocial"])
        let text = record?["text"] as? String ?? ""
        XCTAssertTrue(text.contains("Golden hour"), "The gallery's title should carry over: \(text)")
        XCTAssertTrue(text.contains("grain.social"), "…along with a link back")
    }

    /// The cross-post is written under the key the draft assigned, so a resumed
    /// publish overwrites its own post instead of posting a second time.
    func testTheCrossPostUsesTheDraftsOwnRecordKey() async {
        let outgoing = draft(postToBluesky: true)

        _ = await center.publish(outgoing, client: client, auth: StubAuth())

        let body = log.bodies("dev.hatk.putRecord").first
        XCTAssertEqual(body?["rkey"] as? String, outgoing.blueskyRkey)
        XCTAssertEqual(body?["collection"] as? String, "app.bsky.feed.post")
        XCTAssertEqual(body?["repo"] as? String, "did:plc:test")
    }

    /// The already-uploaded blob is reused for the embed rather than uploaded
    /// again — blobs are repo-scoped, so a second upload would be waste.
    func testTheCrossPostEmbedsTheBlobTheGalleryAlreadyUploaded() async {
        _ = await center.publish(draft(postToBluesky: true), client: client, auth: StubAuth())

        let record = log.bodies("dev.hatk.putRecord").first?["record"] as? [String: Any]
        let embed = record?["embed"] as? [String: Any]
        XCTAssertEqual(embed?["$type"] as? String, "app.bsky.embed.images")

        let images = embed?["images"] as? [[String: Any]]
        XCTAssertEqual(images?.count, 1)
        XCTAssertEqual(images?.first?["alt"] as? String, "A quiet street")
        let image = images?.first?["image"] as? [String: Any]
        XCTAssertEqual((image?["ref"] as? [String: Any])?["$link"] as? String, "bafyalready")
        let ratio = images?.first?["aspectRatio"] as? [String: Any]
        XCTAssertEqual(ratio?["width"] as? Int, 3000)
    }

    func testALocationIsCarriedIntoTheCrossPostText() async {
        let located = draft(
            postToBluesky: true,
            location: GalleryDraft.Location(h3: "8a2a1072b59ffff", name: "Lisboa", address: nil)
        )

        _ = await center.publish(located, client: client, auth: StubAuth())

        let record = log.bodies("dev.hatk.putRecord").first?["record"] as? [String: Any]
        XCTAssertTrue((record?["text"] as? String ?? "").contains("Lisboa"))
    }

    /// An untitled, undescribed gallery still gets a post — just a barer one.
    func testAnEmptyGalleryStillCrossPosts() async {
        let bare = draft(postToBluesky: true, title: "", description: "")

        _ = await center.publish(bare, client: client, auth: StubAuth())

        XCTAssertEqual(log.count("dev.hatk.putRecord"), 1)
        let record = log.bodies("dev.hatk.putRecord").first?["record"] as? [String: Any]
        XCTAssertFalse((record?["text"] as? String ?? "").isEmpty)
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
            if path.hasSuffix("dev.hatk.applyWrites") {
                seenCommit = true
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(#"{"results": []}"#.utf8), response)
            }
            if path.hasSuffix("dev.hatk.putRecord") {
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
        XCTAssertEqual(log.count("dev.hatk.applyWrites"), 0)
        if case .failed = center.stage {
            // expected
        } else {
            XCTFail("Expected a failure stage, got \(center.stage)")
        }
    }
}

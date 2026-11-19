@testable import Grain
import XCTest

/// Every request the cross-post makes.
private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    func requests(_ suffix: String) -> [URLRequest] {
        lock.withLock { requests.filter { $0.url?.path.hasSuffix(suffix) == true } }
    }

    /// The JSON body of the last request whose path ends in `suffix`.
    func lastBody(_ suffix: String) -> [String: Any]? {
        guard let request = requests(suffix).last else { return nil }
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
}

/// The client's half of a Bluesky cross-post. grain-serve words the post
/// (`social.grain.gallery.getCrossPost`); the app writes it, as it came, to
/// the author's repository.
@MainActor
final class BlueskyCrossPostTests: GrainTestCase {
    private var client: XRPCClient!
    private var log: RequestLog!
    private var auth: AuthContext!
    private var did = ""

    private let subject = "at://did:plc:test/social.grain.gallery/1"

    private let servedPost = #"""
    {"$type": "app.bsky.feed.post", "text": "Golden hour\n\n#GrainSocial https://grain.social/profile/did:plc:test/gallery/1",
     "tags": ["grainsocial"], "createdAt": "2025-01-01T00:00:00.000Z",
     "embed": {"$type": "app.bsky.embed.images", "images": [{"alt": "A street", "image": {"$type": "blob", "ref": {"$link": "bafyphoto"}, "mimeType": "image/jpeg", "size": 10}}]}}
    """#

    override func setUp() async throws {
        try await super.setUp()
        did = "did:plc:bsky-\(UUID().uuidString)"
        client = XRPCClient(baseURL: URL(string: "https://appview.test")!, session: MockURLProtocol.mockSession())
        auth = try AuthContext(accessToken: "token", dpop: DPoP.loadOrCreate(for: did), did: did, pds: URL(string: "https://pds.test")!)
        log = RequestLog()
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try? DPoP.clearKey(for: did)
        try await super.tearDown()
    }

    /// Answers getCrossPost with `post` and accepts the write.
    private func serve(post: String) {
        let log = log!
        MockURLProtocol.handler = { request in
            log.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path.hasSuffix("social.grain.gallery.getCrossPost") == true {
                return (Data(#"{"post": \#(post)}"#.utf8), response)
            }
            return (Data(#"{"uri": "at://did:plc:test/app.bsky.feed.post/1", "cid": "bafy"}"#.utf8), response)
        }
    }

    private func written(_ nsid: String = "com.atproto.repo.createRecord") -> [String: Any]? {
        log.lastBody(nsid)?["record"] as? [String: Any]
    }

    // MARK: - The query

    func testTheQueryAsksGrainServeForTheSubjectWithoutAuth() async throws {
        serve(post: servedPost)

        try await BlueskyPost.create(subject: subject, client: client, repo: "did:plc:test", auth: auth)

        let query = try XCTUnwrap(log.requests("social.grain.gallery.getCrossPost").first)
        XCTAssertEqual(query.httpMethod, "GET")
        XCTAssertEqual(query.url?.host, "appview.test")
        XCTAssertNil(query.value(forHTTPHeaderField: "Authorization"))
        let items = try URLComponents(url: XCTUnwrap(query.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first { $0.name == "subject" }?.value, subject)
    }

    func testAFailedQueryWritesNothing() async throws {
        let log = try XCTUnwrap(log)
        MockURLProtocol.handler = { request in
            log.record(request)
            return (Data(#"{"error": "NotFound"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!)
        }

        do {
            try await BlueskyPost.create(subject: subject, client: client, repo: "did:plc:test", auth: auth)
            XCTFail("A missing subject should throw")
        } catch {}
        XCTAssertTrue(log.requests("com.atproto.repo.createRecord").isEmpty)
    }

    // MARK: - Writing the post

    /// The post is written exactly as grain-serve gave it.
    func testThePostIsWrittenUnchanged() async throws {
        serve(post: servedPost)

        try await BlueskyPost.create(subject: subject, client: client, repo: "did:plc:test", auth: auth)

        let record = try XCTUnwrap(written())
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(servedPost.utf8)) as? NSDictionary)
        XCTAssertEqual(record as NSDictionary, expected)
        XCTAssertEqual(log.lastBody("com.atproto.repo.createRecord")?["collection"] as? String, "app.bsky.feed.post")
        XCTAssertEqual(log.lastBody("com.atproto.repo.createRecord")?["repo"] as? String, "did:plc:test")
    }

    /// A gallery's cross-post is written under the key the draft assigned,
    /// with the draft's timestamp, so a resumed publish overwrites its own post.
    func testAKeyedCrossPostOverwritesWithTheGivenTimestamp() async throws {
        serve(post: servedPost)

        try await BlueskyPost.create(
            subject: subject,
            client: client,
            repo: "did:plc:test",
            auth: auth,
            rkey: "3jzfcijpj2z2a",
            createdAt: "2025-01-02T00:00:00.000Z"
        )

        XCTAssertTrue(log.requests("com.atproto.repo.createRecord").isEmpty)
        let body = try XCTUnwrap(log.lastBody("com.atproto.repo.putRecord"))
        XCTAssertEqual(body["rkey"] as? String, "3jzfcijpj2z2a")
        XCTAssertEqual(body["collection"] as? String, "app.bsky.feed.post")
        let record = try XCTUnwrap(body["record"] as? [String: Any])
        XCTAssertEqual(record["createdAt"] as? String, "2025-01-02T00:00:00.000Z")
        XCTAssertEqual(record["tags"] as? [String], ["grainsocial"])
    }
}

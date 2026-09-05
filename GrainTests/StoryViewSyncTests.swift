import CryptoKit
@testable import Grain
import XCTest

/// The strip is where the server's viewed state arrives, and the endpoint is
/// how ours goes back. Both ends of the round trip, against the mock transport.
@MainActor
final class StoryViewSyncTests: GrainTestCase {
    private var client: XRPCClient!
    private var storage: ViewedStoryStorage!
    private let testDID = "did:plc:storyviewsynctests"

    override func setUp() {
        super.setUp()
        AccountScopedStorage.purge(did: testDID)
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        storage = ViewedStoryStorage(did: testDID)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        AccountScopedStorage.purge(did: testDID)
        storage = nil
        super.tearDown()
    }

    func testLoadingTheStripTakesOnWhatWasWatchedElsewhere() async {
        MockURLProtocol.respondWithJSON("""
        {
            "authors": [
                {
                    "profile": {"cid": "c1", "did": "did:plc:alice", "handle": "alice.test"},
                    "storyCount": 2,
                    "latestAt": "2026-09-04T12:00:00.000Z",
                    "lastViewedAt": "2026-09-04T12:00:00.000Z",
                    "unviewedCount": 0
                },
                {
                    "profile": {"cid": "c2", "did": "did:plc:bob", "handle": "bob.test"},
                    "storyCount": 1,
                    "latestAt": "2026-09-04T11:00:00.000Z",
                    "unviewedCount": 1
                }
            ]
        }
        """)
        let cache = StoryStatusCache()
        let vm = StoryStripViewModel(client: client)

        await vm.load(auth: nil, storyStatusCache: cache, viewedStories: storage)

        XCTAssertEqual(vm.authors.map(\.profile.did), ["did:plc:alice", "did:plc:bob"])
        XCTAssertEqual(vm.authors.first?.unviewedCount, 0)
        XCTAssertTrue(storage.hasViewedAll(authorDid: "did:plc:alice", latestAt: "2026-09-04T12:00:00.000Z"))
        XCTAssertFalse(storage.hasViewedAll(authorDid: "did:plc:bob", latestAt: "2026-09-04T11:00:00.000Z"))
        XCTAssertEqual(storage.pendingUploadCount, 0, "Nothing the server said goes back up to it")
    }

    func testAStoryDecodesItsViewedFlag() throws {
        let json = """
        {
            "uri": "at://did:plc:alice/social.grain.story/s1",
            "cid": "c",
            "creator": {"cid": "c1", "did": "did:plc:alice", "handle": "alice.test"},
            "thumb": "", "fullsize": "",
            "aspectRatio": {"width": 9, "height": 16},
            "createdAt": "2026-09-04T12:00:00.000Z",
            "viewer": {"viewed": true}
        }
        """
        let story = try JSONDecoder().decode(GrainStory.self, from: Data(json.utf8))
        XCTAssertEqual(story.viewer?.viewed, true)
        XCTAssertNil(story.viewer?.fav)
    }

    func testMarkingSendsTheUrisToTheEndpoint() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(path: request.url!.path, body: RequestRecorder.body(of: request))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.markStoriesViewed(
            uris: ["at://did:plc:alice/social.grain.story/s1"],
            auth: AuthContext(accessToken: "t", dpop: DPoP(privateKey: P256.Signing.PrivateKey()))
        )

        XCTAssertEqual(recorder.paths, ["/xrpc/social.grain.unspecced.markStoriesViewed"])
        let body = try XCTUnwrap(recorder.bodies.first)
        let decoded = try JSONDecoder().decode([String: [String]].self, from: body)
        XCTAssertEqual(decoded, ["stories": ["at://did:plc:alice/social.grain.story/s1"]])
    }
}

/// Requests seen by the mock transport, safe to read from the test after the
/// handler ran on a URLSession thread.
private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPaths: [String] = []
    private var storedBodies: [Data] = []

    func record(path: String, body: Data?) {
        lock.lock()
        defer { lock.unlock() }
        storedPaths.append(path)
        if let body {
            storedBodies.append(body)
        }
    }

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedPaths
    }

    var bodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return storedBodies
    }

    /// `URLProtocol` moves the body into a stream before the handler sees it.
    static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}

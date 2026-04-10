import CryptoKit
@testable import Grain
import XCTest

@MainActor
final class StoryCommentsViewModelTests: XCTestCase {
    private var client: XRPCClient!
    private var vm: StoryCommentsViewModel!

    private let storyA = "at://did:plc:test/social.grain.story/a"
    private let storyB = "at://did:plc:test/social.grain.story/b"

    override func setUp() {
        super.setUp()
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        vm = StoryCommentsViewModel(client: client)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeDummyAuth() -> AuthContext {
        let key = P256.Signing.PrivateKey()
        let dpop = DPoP(privateKey: key)
        return AuthContext(accessToken: "test-token", dpop: dpop)
    }

    // MARK: - Preview Loading

    func testLoadPreviewSetsLatestCommentAndCount() async {
        MockURLProtocol.respondWithJSON("""
        {
            "comments": [
                {
                    "uri": "at://did:plc:a/social.grain.comment/1",
                    "cid": "c1",
                    "author": {"cid": "ca", "did": "did:plc:a", "handle": "alice.test"},
                    "text": "Great shot!",
                    "createdAt": "2024-06-15T12:00:00Z"
                }
            ],
            "totalCount": 5
        }
        """)

        await vm.loadPreview(storyUri: storyA)
        XCTAssertEqual(vm.latestComment?.text, "Great shot!")
        XCTAssertEqual(vm.totalCount, 5)
    }

    func testLoadPreviewCacheHitDoesNotFetchAgain() async {
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            let json = """
            {"comments": [{"uri": "at://did:plc:a/social.grain.comment/1", "cid": "c1", "author": {"cid": "ca", "did": "did:plc:a", "handle": "alice.test"}, "text": "Cached", "createdAt": "2024-06-15T12:00:00Z"}], "totalCount": 1}
            """
            return (json.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }

        await vm.loadPreview(storyUri: storyA)
        XCTAssertEqual(requestCount, 1)

        await vm.loadPreview(storyUri: storyA)
        XCTAssertEqual(requestCount, 1, "Second call should hit cache, not network")
    }

    func testLoadPreviewCacheMissFetchesBothStories() async {
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            let json = """
            {"comments": [{"uri": "at://did:plc:a/social.grain.comment/\\(requestCount)", "cid": "c\\(requestCount)", "author": {"cid": "ca", "did": "did:plc:a", "handle": "alice.test"}, "text": "Comment \\(requestCount)", "createdAt": "2024-06-15T12:00:00Z"}], "totalCount": \\(requestCount)}
            """
            return (json.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }

        await vm.loadPreview(storyUri: storyA)
        await vm.loadPreview(storyUri: storyB)
        XCTAssertEqual(requestCount, 2, "Different URIs should each trigger a request")
    }

    // MARK: - Full Comment Loading

    func testLoadCommentsPopulatesArray() async {
        MockURLProtocol.respondWithJSON("""
        {
            "comments": [
                {"uri": "at://did:plc:a/social.grain.comment/1", "cid": "c1", "author": {"cid": "ca", "did": "did:plc:a", "handle": "alice.test"}, "text": "Root comment", "createdAt": "2024-06-15T12:00:00Z"},
                {"uri": "at://did:plc:a/social.grain.comment/2", "cid": "c2", "author": {"cid": "cb", "did": "did:plc:b", "handle": "bob.test"}, "text": "Reply", "replyTo": "at://did:plc:a/social.grain.comment/1", "createdAt": "2024-06-15T12:01:00Z"},
                {"uri": "at://did:plc:a/social.grain.comment/3", "cid": "c3", "author": {"cid": "cc", "did": "did:plc:c", "handle": "carol.test"}, "text": "Another root", "createdAt": "2024-06-15T12:02:00Z"}
            ],
            "totalCount": 3
        }
        """)

        await vm.loadComments(storyUri: storyA)
        XCTAssertEqual(vm.comments.count, 3)
        XCTAssertEqual(vm.totalCount, 3)
        XCTAssertFalse(vm.isLoading)

        // Verify threading structure
        let roots = vm.comments.filter { $0.replyTo == nil }
        let replies = vm.comments.filter { $0.replyTo != nil }
        XCTAssertEqual(roots.count, 2)
        XCTAssertEqual(replies.count, 1)
    }

    func testLoadMoreCommentsAppends() async {
        // First load
        MockURLProtocol.respondWithJSON("""
        {"comments": [{"uri": "at://did:plc:a/social.grain.comment/1", "cid": "c1", "author": {"cid": "ca", "did": "did:plc:a", "handle": "alice.test"}, "text": "First", "createdAt": "2024-06-15T12:00:00Z"}], "cursor": "page2", "totalCount": 2}
        """)
        await vm.loadComments(storyUri: storyA)
        XCTAssertEqual(vm.comments.count, 1)

        // Paginate
        MockURLProtocol.respondWithJSON("""
        {"comments": [{"uri": "at://did:plc:a/social.grain.comment/2", "cid": "c2", "author": {"cid": "cb", "did": "did:plc:b", "handle": "bob.test"}, "text": "Second", "createdAt": "2024-06-15T12:01:00Z"}]}
        """)
        await vm.loadMoreComments(storyUri: storyA)
        XCTAssertEqual(vm.comments.count, 2)
    }

    // MARK: - CRUD

    func testPostCommentRefreshesAndInvalidatesCache() async {
        // Seed cache
        MockURLProtocol.respondWithJSON("""
        {"comments": [{"uri": "at://did:plc:a/social.grain.comment/old", "cid": "cold", "author": {"cid": "ca", "did": "did:plc:a", "handle": "alice.test"}, "text": "Old", "createdAt": "2024-06-15T12:00:00Z"}], "totalCount": 1}
        """)
        await vm.loadPreview(storyUri: storyA)
        XCTAssertEqual(vm.latestComment?.text, "Old")

        // Post triggers createRecord then loadComments refresh
        var requestPaths: [String] = []
        MockURLProtocol.handler = { request in
            requestPaths.append(request.url?.lastPathComponent ?? "")
            let json = if request.httpMethod == "POST" {
                """
                {"uri": "at://did:plc:test/social.grain.comment/new", "cid": "cnew"}
                """
            } else {
                """
                {"comments": [{"uri": "at://did:plc:a/social.grain.comment/new", "cid": "cnew", "author": {"cid": "ca", "did": "did:plc:a", "handle": "alice.test"}, "text": "Fresh", "createdAt": "2024-06-15T13:00:00Z"}], "totalCount": 2}
                """
            }
            return (json.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }

        let auth = makeDummyAuth()
        vm.switchToStory(uri: storyA)
        await vm.postComment(text: "Hello", storyUri: storyA, auth: auth)
        XCTAssertEqual(vm.latestComment?.text, "Fresh")
        XCTAssertEqual(vm.totalCount, 2)
    }

    func testDeleteCommentRemovesFromArray() async {
        // Switch first so activeStoryUri is set; the background preview task will fail silently without a mock
        vm.switchToStory(uri: storyA)
        try? await Task.sleep(for: .milliseconds(50))

        MockURLProtocol.respondWithJSON("""
        {"comments": [
            {"uri": "at://did:plc:a/social.grain.comment/1", "cid": "c1", "author": {"cid": "ca", "did": "did:plc:a", "handle": "alice.test"}, "text": "Keep", "createdAt": "2024-06-15T12:00:00Z"},
            {"uri": "at://did:plc:a/social.grain.comment/2", "cid": "c2", "author": {"cid": "cb", "did": "did:plc:b", "handle": "bob.test"}, "text": "Delete me", "createdAt": "2024-06-15T12:01:00Z"}
        ], "totalCount": 2}
        """)
        await vm.loadComments(storyUri: storyA)
        XCTAssertEqual(vm.comments.count, 2)

        // Delete the second comment
        MockURLProtocol.respondWithJSON("{}")
        let toDelete = vm.comments[1]
        let auth = makeDummyAuth()
        await vm.deleteComment(toDelete, storyUri: storyA, auth: auth)
        XCTAssertEqual(vm.comments.count, 1)
        XCTAssertEqual(vm.comments.first?.text, "Keep")
        XCTAssertEqual(vm.totalCount, 1)
    }

    // MARK: - Cache Switching

    func testSwitchToStoryCachedRestoresWithoutFetch() async {
        // Load preview for story A
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            let json = """
            {"comments": [{"uri": "at://did:plc:a/social.grain.comment/1", "cid": "c1", "author": {"cid": "ca", "did": "did:plc:a", "handle": "alice.test"}, "text": "Story A comment", "createdAt": "2024-06-15T12:00:00Z"}], "totalCount": 1}
            """
            return (json.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }

        vm.switchToStory(uri: storyA)
        // Wait for the background task to complete
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(vm.latestComment?.text, "Story A comment")

        // Switch to story B
        vm.switchToStory(uri: storyB)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(requestCount, 2)

        // Switch back to A — should use cache
        vm.switchToStory(uri: storyA)
        // No sleep needed — cache is synchronous
        XCTAssertEqual(requestCount, 2, "Switching back to A should use cache")
        XCTAssertEqual(vm.latestComment?.text, "Story A comment")
    }
}

@testable import Grain
import XCTest

/// File scope, not a static member: `MockURLProtocol.handler` runs outside the
/// main actor, so anything it reads has to live outside this @MainActor class.
private let galleryBody = """
{"gallery": {
  "uri": "at://did:plc:a/social.grain.gallery/1",
  "cid": "bafyg",
  "title": "A gallery",
  "creator": {"cid": "c1", "did": "did:plc:a", "handle": "alice.test"},
  "indexedAt": "2025-01-02T00:00:00Z"
}}
"""

private func commentsBody(ids: [Int], cursor: String?) -> String {
    let comments = ids.map { id in
        """
        {
          "uri": "at://did:plc:a/social.grain.comment/\(id)",
          "cid": "bafyc\(id)",
          "author": {"cid": "c1", "did": "did:plc:a", "handle": "alice.test"},
          "text": "Comment \(id)",
          "createdAt": "2025-01-03T00:00:00Z"
        }
        """
    }.joined(separator: ",")
    let cursorJSON = cursor.map { "\"\($0)\"" } ?? "null"
    return "{\"comments\": [\(comments)], \"cursor\": \(cursorJSON)}"
}

/// The detail screen fetches the gallery and its first page of comments
/// together, then pages the comments. Its cursor bookkeeping is the part that
/// misbehaves quietly: a stale cursor either re-appends a page or stops paging
/// a thread that still has more.
@MainActor
final class GalleryDetailViewModelTests: GrainTestCase {
    private var client: XRPCClient!
    private var vm: GalleryDetailViewModel!

    private let galleryUri = "at://did:plc:a/social.grain.gallery/1"

    override func setUp() async throws {
        try await super.setUp()
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        vm = GalleryDetailViewModel(client: client)
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try await super.tearDown()
    }

    /// Serves the gallery to the gallery endpoint and comments to the thread
    /// endpoint, so one `load()` can be driven end to end.
    private func respond(comments: [Int], cursor: String?) {
        MockURLProtocol.handler = { request in
            let body = request.url!.path.contains("getGallery")
                ? galleryBody
                : commentsBody(ids: comments, cursor: cursor)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    // MARK: - load

    func testLoadFillsTheGalleryAndItsComments() async {
        respond(comments: [1, 2], cursor: nil)

        await vm.load(uri: galleryUri)

        XCTAssertEqual(vm.gallery?.title, "A gallery")
        XCTAssertEqual(vm.comments.map(\.text), ["Comment 1", "Comment 2"])
        XCTAssertNil(vm.error)
        XCTAssertFalse(vm.isLoading)
    }

    func testAFailedLoadRecordsTheErrorAndStopsLoading() async {
        MockURLProtocol.respondWithError(statusCode: 404)

        await vm.load(uri: galleryUri)

        XCTAssertNil(vm.gallery)
        XCTAssertNotNil(vm.error)
        XCTAssertFalse(vm.isLoading)
    }

    /// Pull-to-refresh runs `load` again after a failure, and the stale error
    /// has to go or the screen keeps showing it under fresh content.
    func testASuccessfulReloadClearsAPreviousError() async {
        MockURLProtocol.respondWithError(statusCode: 500)
        await vm.load(uri: galleryUri)
        XCTAssertNotNil(vm.error)

        respond(comments: [1], cursor: nil)
        await vm.load(uri: galleryUri)

        XCTAssertNil(vm.error)
        XCTAssertNotNil(vm.gallery)
    }

    func testReloadingReplacesTheCommentsRatherThanAppending() async {
        respond(comments: [1, 2], cursor: nil)
        await vm.load(uri: galleryUri)

        respond(comments: [3], cursor: nil)
        await vm.load(uri: galleryUri)

        XCTAssertEqual(vm.comments.map(\.text), ["Comment 3"])
    }

    // MARK: - loadMoreComments

    func testLoadMoreAppendsTheNextPage() async {
        respond(comments: [1], cursor: "page2")
        await vm.load(uri: galleryUri)

        MockURLProtocol.respondWithJSON(commentsBody(ids: [2, 3], cursor: nil))
        await vm.loadMoreComments(galleryUri: galleryUri)

        XCTAssertEqual(vm.comments.map(\.text), ["Comment 1", "Comment 2", "Comment 3"])
    }

    /// Scroll-triggered paging fires repeatedly at the bottom of a thread, so
    /// the last page has to be terminal.
    func testPagingStopsOnceTheServerRunsOut() async {
        respond(comments: [1], cursor: "page2")
        await vm.load(uri: galleryUri)

        MockURLProtocol.respondWithJSON(commentsBody(ids: [2], cursor: nil))
        await vm.loadMoreComments(galleryUri: galleryUri)

        var extraRequests = 0
        MockURLProtocol.handler = { request in
            extraRequests += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(commentsBody(ids: [99], cursor: nil).utf8), response)
        }
        await vm.loadMoreComments(galleryUri: galleryUri)

        XCTAssertEqual(extraRequests, 0)
        XCTAssertEqual(vm.comments.count, 2)
    }

    /// A first page that already exhausted the thread leaves no cursor to page
    /// with at all.
    func testThereIsNothingToPageWhenTheFirstPageWasTheWholeThread() async {
        respond(comments: [1], cursor: nil)
        await vm.load(uri: galleryUri)

        var requestMade = false
        MockURLProtocol.handler = { request in
            requestMade = true
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(commentsBody(ids: [2], cursor: nil).utf8), response)
        }
        await vm.loadMoreComments(galleryUri: galleryUri)

        XCTAssertFalse(requestMade)
        XCTAssertEqual(vm.comments.count, 1)
    }

    /// The initial load and a paging request share the flag, so paging must
    /// stand down while the first load is still in flight.
    func testPagingIsSkippedWhileAnotherLoadIsRunning() async {
        respond(comments: [1], cursor: "page2")
        await vm.load(uri: galleryUri)
        vm.isLoading = true

        var requestMade = false
        MockURLProtocol.handler = { request in
            requestMade = true
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(commentsBody(ids: [2], cursor: nil).utf8), response)
        }
        await vm.loadMoreComments(galleryUri: galleryUri)

        XCTAssertFalse(requestMade)
    }

    /// A failed page must leave what's already on screen alone.
    func testAFailedPageKeepsTheCommentsAlreadyLoaded() async {
        respond(comments: [1], cursor: "page2")
        await vm.load(uri: galleryUri)

        MockURLProtocol.respondWithError(statusCode: 500)
        await vm.loadMoreComments(galleryUri: galleryUri)

        XCTAssertEqual(vm.comments.map(\.text), ["Comment 1"])
        XCTAssertNotNil(vm.error)
        XCTAssertFalse(vm.isLoading)
    }
}

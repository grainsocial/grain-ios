@testable import Grain
import XCTest

/// Off the test class on purpose: the mock's handler runs on the URL loading
/// thread, and a `static let` on a main-actor class is main-actor state.
private enum ExploreFixtures {
    static let firstPage = """
    {"items": [\(Fixtures.gallery)], "cursor": "c1"}
    """

    static let secondPage = """
    {"items": [{
      "uri": "at://did:plc:test/social.grain.gallery/2",
      "cid": "bafy2",
      "title": "Second",
      "creator": \(Fixtures.profile),
      "items": [\(Fixtures.photo)],
      "indexedAt": "2025-01-03T00:00:00Z"
    }], "cursor": null}
    """

    /// Answers by endpoint, from any thread.
    static func respond(feed: String = firstPage, camerasStatus: Int = 200) -> (URLRequest) throws -> (Data, HTTPURLResponse) {
        { request in
            let path = request.url!.path
            let status = path.contains("getCameras") ? camerasStatus : 200
            let body = path.contains("getCameras") ? Fixtures.cameras
                : path.contains("getLocations") ? Fixtures.locations
                : feed
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}

/// What the handler saw, readable back on the main actor. Locked because the
/// handler runs on the URL loading thread.
private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func record(_ request: URLRequest) {
        lock.withLock { urls.append(request.url!) }
    }

    var count: Int {
        lock.withLock { urls.count }
    }

    func lastQueryValue(_ name: String) -> String? {
        lock.withLock {
            guard let url = urls.last else { return nil }
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
        }
    }

    func lastQueryValue(_ name: String, onPathContaining fragment: String) -> String? {
        lock.withLock {
            guard let url = urls.last(where: { $0.path.contains(fragment) }) else { return nil }
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
        }
    }
}

/// Explore: the recent feed paged like any other, plus two chip rows that
/// arrive and fail on their own.
@MainActor
final class ExploreViewModelTests: GrainTestCase {
    private var client: XRPCClient!
    private var vm: ExploreViewModel!

    override func setUp() async throws {
        try await super.setUp()
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        vm = ExploreViewModel(client: client)
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try await super.tearDown()
    }

    func testTheFirstLoadFillsChipsAndTheRecentGrid() async {
        let log = RequestCapture()
        let respond = ExploreFixtures.respond()
        MockURLProtocol.handler = { request in
            log.record(request)
            return try respond(request)
        }

        await vm.loadIfNeeded()

        XCTAssertEqual(vm.cameras.map(\.camera), ["Fujifilm X100V", "Leica M6"])
        XCTAssertEqual(vm.locations.map(\.name), ["Lisboa", "Porto"])
        XCTAssertEqual(vm.galleries.map(\.title), ["A test gallery"])
        XCTAssertEqual(log.lastQueryValue("feed", onPathContaining: "getFeed"), "recent")
        XCTAssertFalse(vm.isLoading)
    }

    func testOneIndexFailingLeavesTheOthers() async {
        MockURLProtocol.handler = ExploreFixtures.respond(camerasStatus: 500)

        await vm.loadIfNeeded()

        XCTAssertTrue(vm.cameras.isEmpty)
        XCTAssertEqual(vm.locations.count, 2)
        XCTAssertEqual(vm.galleries.count, 1)
        XCTAssertFalse(vm.isLoading)
    }

    func testMoreGalleriesAppendBehindTheCursor() async {
        MockURLProtocol.handler = ExploreFixtures.respond()
        await vm.loadIfNeeded()

        let log = RequestCapture()
        let respond = ExploreFixtures.respond(feed: ExploreFixtures.secondPage)
        MockURLProtocol.handler = { request in
            log.record(request)
            return try respond(request)
        }
        await vm.loadMore()

        XCTAssertEqual(log.lastQueryValue("cursor"), "c1")
        XCTAssertEqual(vm.galleries.map(\.title), ["A test gallery", "Second"])
        XCTAssertFalse(vm.isLoadingMore)

        // No cursor came back with the second page: the feed is done.
        await vm.loadMore()
        XCTAssertEqual(vm.galleries.count, 2)
        XCTAssertEqual(log.count, 1)
    }

    func testASecondLookDoesNotReloadButARefreshDoes() async {
        let log = RequestCapture()
        let respond = ExploreFixtures.respond()
        MockURLProtocol.handler = { request in
            log.record(request)
            return try respond(request)
        }

        await vm.loadIfNeeded()
        XCTAssertEqual(log.count, 3)
        await vm.loadIfNeeded()
        XCTAssertEqual(log.count, 3)
        await vm.refresh()
        XCTAssertEqual(log.count, 6)
    }
}

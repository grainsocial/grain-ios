@testable import Grain
import XCTest

/// Off the test class on purpose: the mock's handler runs on the URL loading
/// thread, and a `static let` on a main-actor class is main-actor state.
private enum PlaceFixtures {
    static let tiles = """
    {"locations": [{"name": "Lisboa", "h3Index": "8a2a1072b59ffff", "galleryCount": 12, "thumbs": ["https://test.local/1.jpg"]}]}
    """

    static let pins = """
    {"locations": [
      {"name": "Lisboa", "h3Index": "8a2a1072b59ffff", "galleryCount": 12},
      {"name": "Porto", "h3Index": "8a2a1072b58ffff", "galleryCount": 4}
    ]}
    """

    static let firstPage = """
    {"items": [\(Fixtures.gallery)], "cursor": "c1"}
    """

    static let secondPage = """
    {"items": [{"uri": "at://did:plc:test/social.grain.gallery/2", "cid": "b2", "title": "Second", "creator": \(Fixtures.profile), "indexedAt": "2025-01-03T00:00:00Z"}], "cursor": null}
    """

    static let empty = #"{"items": [], "cursor": null}"#

    /// Tiles and pins come from one endpoint told apart by a query parameter,
    /// so the answer has to depend on the request. Everything else is the feed.
    static func respond(
        feed: String = firstPage,
        feedStatus: Int = 200,
        log: RequestCapture? = nil
    ) -> (URLRequest) throws -> (Data, HTTPURLResponse) {
        { request in
            log?.record(request)
            let url = request.url!
            if url.path.contains("getLocations") {
                let wantsPins = url.query?.contains("pins=true") == true
                return (Data((wantsPins ? pins : tiles).utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            if url.path.contains("getCameras") {
                return (Data(Fixtures.cameras.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return (Data(feed.utf8), HTTPURLResponse(url: url, statusCode: feedStatus, httpVersion: nil, headerFields: nil)!)
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

    func lastQueryValue(_ name: String, onPathContaining fragment: String? = nil) -> String? {
        lock.withLock {
            guard let url = urls.last(where: { fragment.map($0.path.contains) ?? true }) else { return nil }
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
        }
    }
}

/// The two index screens behind explore's "See all": the cameras grid, and
/// the map whose sheet swaps to a picked place's galleries.
@MainActor
final class BrowseIndexViewModelsTests: GrainTestCase {
    private var client: XRPCClient!

    override func setUp() async throws {
        try await super.setUp()
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try await super.tearDown()
    }

    // MARK: - Cameras

    func testCamerasArriveWithTheirThumbnails() async {
        MockURLProtocol.respondWithJSON(#"{"cameras": [{"camera": "Leica M6", "photoCount": 120, "thumbs": ["https://test.local/1.jpg"]}]}"#)
        let vm = CamerasViewModel(client: client)

        await vm.load()

        XCTAssertEqual(vm.cameras.map(\.camera), ["Leica M6"])
        XCTAssertEqual(vm.cameras.first?.thumbs?.count, 1)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.failed)
    }

    func testAFailedCamerasLoadSaysSo() async {
        MockURLProtocol.respondWithError(statusCode: 500)
        let vm = CamerasViewModel(client: client)

        await vm.load()

        XCTAssertTrue(vm.cameras.isEmpty)
        XCTAssertTrue(vm.failed)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Locations

    func testLocationsAskForTilesAndPinsSeparately() async {
        MockURLProtocol.handler = PlaceFixtures.respond()
        let vm = LocationsViewModel(client: client)

        await vm.load()

        XCTAssertEqual(vm.places.map(\.name), ["Lisboa"])
        XCTAssertEqual(vm.places.first?.thumbs?.count, 1)
        XCTAssertEqual(vm.pins.map(\.name), ["Lisboa", "Porto"])
        XCTAssertEqual(vm.pins.first?.galleryCount, 12)
        XCTAssertFalse(vm.isLoading)
    }

    func testPickingAPlaceLoadsItsGalleriesWithoutLeavingTheIndex() async {
        MockURLProtocol.handler = PlaceFixtures.respond()
        let vm = LocationsViewModel(client: client)
        await vm.load()

        let log = RequestCapture()
        MockURLProtocol.handler = PlaceFixtures.respond(log: log)
        vm.select(cell: "8a2a1072b59ffff", name: "Lisboa", galleryCount: 12)
        XCTAssertEqual(vm.selected?.name, "Lisboa")
        XCTAssertEqual(vm.selected?.isLoading, true)

        await waitUntil { vm.selected?.isLoading == false }

        XCTAssertEqual(vm.selected?.galleries.map(\.title), ["A test gallery"])
        XCTAssertEqual(vm.selected?.galleryCount, 12)
        XCTAssertNotNil(vm.selected?.coordinate)
        XCTAssertEqual(log.lastQueryValue("feed", onPathContaining: "getFeed"), "location")
        XCTAssertEqual(log.lastQueryValue("location", onPathContaining: "getFeed"), "8a2a1072b59ffff")
        // The index is still there underneath.
        XCTAssertEqual(vm.places.count, 1)
    }

    func testPickingThePlaceAlreadyShownDoesNotReload() async {
        MockURLProtocol.handler = PlaceFixtures.respond()
        let vm = LocationsViewModel(client: client)
        vm.select(cell: "8a2a1072b59ffff", name: "Lisboa", galleryCount: 12)
        await waitUntil { vm.selected?.isLoading == false }

        let log = RequestCapture()
        MockURLProtocol.handler = PlaceFixtures.respond(log: log)
        vm.select(cell: "8a2a1072b59ffff", name: "Lisboa", galleryCount: 12)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(log.count, 0)
    }

    func testMoreOfAPlacesGalleriesAppendBehindTheCursor() async {
        MockURLProtocol.handler = PlaceFixtures.respond()
        let vm = LocationsViewModel(client: client)
        vm.select(cell: "8a2a1072b59ffff", name: "Lisboa", galleryCount: 12)
        await waitUntil { vm.selected?.isLoading == false }

        let log = RequestCapture()
        MockURLProtocol.handler = PlaceFixtures.respond(feed: PlaceFixtures.secondPage, log: log)
        await vm.loadMoreGalleries()

        XCTAssertEqual(log.lastQueryValue("cursor"), "c1")
        XCTAssertEqual(vm.selected?.galleries.map(\.title), ["A test gallery", "Second"])
        XCTAssertEqual(vm.selected?.isLoadingMore, false)
    }

    func testClearingTheSelectionBringsTheIndexBack() async {
        MockURLProtocol.handler = PlaceFixtures.respond(feed: PlaceFixtures.empty)
        let vm = LocationsViewModel(client: client)
        vm.select(cell: "8a2a1072b59ffff", name: "Lisboa", galleryCount: 12)
        await waitUntil { vm.selected?.isLoading == false }
        XCTAssertEqual(vm.selected?.isEmpty, true)

        vm.clearSelection()

        XCTAssertNil(vm.selected)
    }

    func testAFailedGalleryLoadLeavesThePlaceEmptyRatherThanStuck() async {
        MockURLProtocol.handler = PlaceFixtures.respond(feedStatus: 500)
        let vm = LocationsViewModel(client: client)
        vm.select(cell: "8a2a1072b59ffff", name: "Lisboa", galleryCount: 12)

        await waitUntil { vm.selected?.isLoading == false }

        XCTAssertEqual(vm.selected?.isEmpty, true)
    }

    // MARK: - Helpers

    /// Block until `condition` holds, or fail after a second. The galleries
    /// land on a task the view model owns, which nothing here can await.
    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(1)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out waiting", file: file, line: line)
    }
}

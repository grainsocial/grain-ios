@testable import Grain
import XCTest

/// Search and discovery both swallow their errors so the tab degrades to an
/// empty state rather than an alert. That makes the failure paths worth pinning
/// down explicitly — a regression there is silent by design.
@MainActor
final class SearchViewModelTests: XCTestCase {
    private var client: XRPCClient!
    private var vm: SearchViewModel!

    override func setUp() async throws {
        try await super.setUp()
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        vm = SearchViewModel(client: client)
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try await super.tearDown()
    }

    private static let galleryResults = """
    {
      "items": [{
        "uri": "at://did:plc:a/social.grain.gallery/1",
        "cid": "bafyg",
        "title": "Found gallery",
        "creator": {"cid": "c1", "did": "did:plc:a", "handle": "alice.test"},
        "indexedAt": "2025-01-02T00:00:00Z"
      }],
      "cursor": null
    }
    """

    private static let profileResults = """
    {
      "items": [
        {"did": "did:plc:a", "handle": "alice.test", "displayName": "Alice"},
        {"did": "did:plc:b", "handle": "bob.test"}
      ],
      "cursor": null
    }
    """

    // MARK: - Tabs

    func testItStartsOnGalleriesWithBothTabsAvailable() {
        XCTAssertEqual(vm.selectedTab, .galleries)
        XCTAssertEqual(SearchViewModel.SearchTab.allCases, [.galleries, .profiles])
        XCTAssertEqual(SearchViewModel.SearchTab.galleries.rawValue, "Galleries")
        XCTAssertEqual(SearchViewModel.SearchTab.profiles.rawValue, "Profiles")
    }

    // MARK: - search

    func testSearchingOnTheGalleriesTabFillsGalleryResults() async {
        MockURLProtocol.respondWithJSON(Self.galleryResults)
        vm.searchText = "film"

        await vm.search()

        XCTAssertEqual(vm.galleryResults.map(\.title), ["Found gallery"])
        XCTAssertTrue(vm.profileResults.isEmpty, "The galleries tab shouldn't populate the profiles tab")
        XCTAssertFalse(vm.isSearching)
    }

    func testSearchingOnTheProfilesTabFillsProfileResults() async {
        MockURLProtocol.respondWithJSON(Self.profileResults)
        vm.selectedTab = .profiles
        vm.searchText = "ali"

        await vm.search()

        XCTAssertEqual(vm.profileResults.map(\.did), ["did:plc:a", "did:plc:b"])
        XCTAssertTrue(vm.galleryResults.isEmpty)
        XCTAssertFalse(vm.isSearching)
    }

    /// Whitespace is what a user leaves behind after clearing the field, and it
    /// must not cost a request.
    func testAnEmptyOrBlankQueryNeverHitsTheNetwork() async {
        var requestMade = false
        MockURLProtocol.handler = { request in
            requestMade = true
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        vm.searchText = ""
        await vm.search()
        vm.searchText = "   \n "
        await vm.search()

        XCTAssertFalse(requestMade)
        XCTAssertFalse(vm.isSearching, "Bailing early must not leave the spinner up")
    }

    func testAFailedSearchLeavesNoResultsAndStopsTheSpinner() async {
        MockURLProtocol.respondWithError(statusCode: 500)
        vm.searchText = "film"

        await vm.search()

        XCTAssertTrue(vm.galleryResults.isEmpty)
        XCTAssertFalse(vm.isSearching)
    }

    /// A search that comes back with nothing has to clear the previous results,
    /// or the tab keeps showing matches for a query that is no longer on screen.
    func testASearchWithNoMatchesClearsThePreviousResults() async {
        MockURLProtocol.respondWithJSON(Self.galleryResults)
        vm.searchText = "film"
        await vm.search()
        XCTAssertEqual(vm.galleryResults.count, 1)

        MockURLProtocol.respondWithJSON(#"{"items": [], "cursor": null}"#)
        vm.searchText = "nothing matches this"
        await vm.search()

        XCTAssertTrue(vm.galleryResults.isEmpty)
    }

    /// A response that omits `items` entirely is not the same as one that sends
    /// an empty array, and both have to end up as no results.
    func testAResponseWithNoItemsKeyIsTreatedAsNoResults() async {
        MockURLProtocol.respondWithJSON("{}")
        vm.searchText = "film"

        await vm.search()

        XCTAssertTrue(vm.galleryResults.isEmpty)
    }

    // MARK: - loadDiscovery

    func testDiscoveryLoadsLocationsAndCameras() async {
        MockURLProtocol.handler = { request in
            let body = request.url!.path.contains("getLocations")
                ? #"{"locations": [{"name": "Lisboa", "h3Index": "8a2a", "galleryCount": 12}]}"#
                : #"{"cameras": [{"camera": "Fujifilm X100V", "photoCount": 40}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }

        await vm.loadDiscovery()

        XCTAssertEqual(vm.locations.map(\.name), ["Lisboa"])
        XCTAssertEqual(vm.locations.first?.id, "8a2a", "Locations are identified by their H3 index")
        XCTAssertEqual(vm.cameras.map(\.camera), ["Fujifilm X100V"])
        XCTAssertEqual(vm.cameras.first?.id, "Fujifilm X100V")
    }

    /// Discovery is decoration on the search tab; failing it must leave the tab
    /// usable rather than half-populated.
    func testAFailedDiscoveryLeavesBothListsEmpty() async {
        MockURLProtocol.respondWithError(statusCode: 500)

        await vm.loadDiscovery()

        XCTAssertTrue(vm.locations.isEmpty)
        XCTAssertTrue(vm.cameras.isEmpty)
    }

    /// Cameras are fetched after locations, so a failure on the second call
    /// must not silently keep the first call's results either — they're set
    /// together or not at all.
    func testCamerasFailingLeavesLocationsUnset() async {
        MockURLProtocol.handler = { request in
            guard request.url!.path.contains("getLocations") else {
                throw URLError(.timedOut)
            }
            let body = #"{"locations": [{"name": "Lisboa", "h3Index": "8a2a", "galleryCount": 12}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }

        await vm.loadDiscovery()

        XCTAssertTrue(vm.locations.isEmpty)
        XCTAssertTrue(vm.cameras.isEmpty)
    }
}

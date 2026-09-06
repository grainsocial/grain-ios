@testable import Grain
import SwiftUI
import XCTest

/// The explore page and the screens behind its chips, rendered against a
/// healthy server. Plus the two small helpers the map's label and the tile
/// counts lean on.
@MainActor
final class ExploreRenderTests: GrainTestCase {
    private var account: TestAccount!

    override func setUp() async throws {
        try await super.setUp()
        account = TestAccount()
        var routes = Fixtures.routes
        routes["getCameras"] = #"{"cameras": [{"camera": "Leica M6", "photoCount": 120, "thumbs": ["https://test.local/1.jpg", "https://test.local/2.jpg", "https://test.local/3.jpg"]}]}"#
        routes["getLocations"] = #"{"locations": [{"name": "Lisboa, PT", "h3Index": "8a2a1072b59ffff", "galleryCount": 12, "thumbs": ["https://test.local/1.jpg"]}]}"#
        MockURLProtocol.respondByPath(routes)
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        account.restore()
        try await super.tearDown()
    }

    private let settle: TimeInterval = 0.35

    func testRendersExploreWithChipsAndTheRecentGrid() {
        let env = TestEnvironment()
        ViewRender.render(NavigationStack { ExploreView(client: env.client) }.withTestEnvironment(env), settle: settle)
    }

    func testRendersTheSearchTabOnExploreBeforeAnythingIsTyped() {
        let env = TestEnvironment()
        ViewRender.render(SearchView(client: env.client).withTestEnvironment(env), settle: settle)
    }

    func testRendersTheCamerasIndex() {
        let env = TestEnvironment()
        ViewRender.render(NavigationStack { CamerasView(client: env.client) }.withTestEnvironment(env), settle: settle)
    }

    func testRendersTheLocationsSheetOnTheIndexAndOnAPlace() throws {
        let env = TestEnvironment()
        let vm = LocationsViewModel(client: env.client)
        ViewRender.render(IndexSheet(viewModel: vm) { _ in }.withTestEnvironment(env), settle: settle)

        var place = SelectedPlace(name: "Lisboa, PT", h3Index: "8a2a1072b59ffff", galleryCount: 12, coordinate: nil)
        place.isLoading = false
        place.galleries = try [JSONDecoder().decode(GrainGallery.self, from: Data(Fixtures.gallery.utf8))]
        ViewRender.render(
            PlaceSheet(place: place, onBack: {}, onOpenGallery: { _ in }, onLoadMore: {}).withTestEnvironment(env),
            settle: settle
        )
    }

    func testTheMapLabelIsTheLocalityAlone() {
        XCTAssertEqual(localityOf("Nazaré, Leiria, PT"), "Nazaré")
        XCTAssertEqual(localityOf("Lisbon, PT"), "Lisbon")
        XCTAssertEqual(localityOf("Portugal"), "Portugal")
        XCTAssertEqual(localityOf(", PT"), ", PT")
    }

    func testCountsReadAsWords() {
        XCTAssertEqual(counted(1, "photo", "photos"), "1 photo")
        XCTAssertEqual(counted(2, "gallery", "galleries"), "2 galleries")
    }

    func testFlowLayoutWrapsWhatDoesNotFit() {
        // Four 100pt chips in 250pt: two rows of two, each as tall as a chip.
        let layout = FlowLayout(spacing: 10)
        let host = UIHostingController(rootView: layout {
            ForEach(0 ..< 4, id: \.self) { _ in Color.red.frame(width: 100, height: 20) }
        }.frame(width: 250))
        let size = host.sizeThatFits(in: CGSize(width: 250, height: 1000))
        XCTAssertEqual(size.height, 50, accuracy: 1)
    }
}

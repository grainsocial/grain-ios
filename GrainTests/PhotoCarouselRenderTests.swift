@testable import Grain
import SwiftUI
import XCTest

/// The carousel above the photo strip in the create sheet. It is the only place
/// a chosen photo is shown at full width, and it decodes a screen-sized preview
/// per photo to do it.
@MainActor
final class PhotoCarouselRenderTests: XCTestCase {
    private var account: TestAccount!

    /// Async overrides: the synchronous `setUp`/`tearDown` are nonisolated, so
    /// touching main-actor state from them warns.
    override func setUp() async throws {
        try await super.setUp()
        account = TestAccount()
        MockURLProtocol.interceptSharedSession()
        MockURLProtocol.respondByPath(Fixtures.routes)
    }

    override func tearDown() async throws {
        MockURLProtocol.stopInterceptingSharedSession()
        MockURLProtocol.handler = nil
        account.restore()
        try await super.tearDown()
    }

    private func makeItems(_ count: Int, mixedRatios: Bool = false, withExif: Bool = false, alt: Bool = false) -> [PhotoItem] {
        let exif = ExifSummary(
            camera: "Fujifilm X100V",
            lens: "23mm f/2",
            exposure: nil,
            shutterSpeed: "1/500s",
            iso: "ISO 400",
            focalLength: "35mm",
            aperture: "f/2"
        )
        return (0 ..< count).map { index in
            let size = mixedRatios && !index.isMultiple(of: 2)
                ? CGSize(width: 60, height: 90)
                : CGSize(width: 120, height: 80)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                context.cgContext.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
                context.cgContext.fill(CGRect(origin: .zero, size: size))
            }
            return PhotoItem(
                thumbnail: image,
                carouselPreview: image,
                source: .camera(image, metadata: nil),
                alt: alt ? "Alt text for photo \(index)" : "",
                exifSummary: withExif ? exif : nil
            )
        }
    }

    private func renderCarousel(
        items: [PhotoItem],
        selected: UUID?,
        sendExif: Bool = true,
        settle: TimeInterval = 0.25
    ) {
        var bound = selected
        ViewRender.render(
            PhotoCarouselView(
                items: items,
                selectedPhotoID: Binding(get: { bound }, set: { bound = $0 }),
                sendExif: sendExif
            )
            .withTestEnvironment(TestEnvironment()),
            settle: settle
        )
    }

    /// The carousel is what the create sheet shows above the strip, and it
    /// decodes a screen-width preview per photo on the way.
    func testRendersTheCarouselWithSeveralPhotos() {
        let items = makeItems(4)
        renderCarousel(items: items, selected: items.first?.id)
    }

    /// Mixed aspect ratios make the carousel size to a common ratio rather than
    /// to each page, which is a separate measurement path.
    func testRendersTheCarouselWithMixedAspectRatios() {
        let items = makeItems(4, mixedRatios: true)
        renderCarousel(items: items, selected: items.first?.id)
    }

    /// Exif turns on a whole row under the photo; alt text turns on a badge.
    func testRendersTheCarouselWithExifAndAltText() {
        let items = makeItems(3, withExif: true, alt: true)
        renderCarousel(items: items, selected: items.first?.id)
        renderCarousel(items: items, selected: items.first?.id, sendExif: false)
    }

    /// Paging to a later photo is what the strip does on selection.
    func testRendersTheCarouselOnALaterPhoto() {
        let items = makeItems(5)
        renderCarousel(items: items, selected: items[3].id)
        renderCarousel(items: items, selected: items.last?.id)
    }

    /// A selection that no longer exists — the photo it named was deleted — has
    /// to clamp rather than index out of bounds.
    func testTheCarouselSurvivesASelectionThatIsGone() {
        renderCarousel(items: makeItems(3), selected: UUID())
    }

    func testTheCarouselWithASinglePhotoHasNoPager() {
        let items = makeItems(1)
        renderCarousel(items: items, selected: items.first?.id)
    }

    /// Built before the picker returns, so it has to lay out nothing.
    func testTheCarouselWithNoPhotosDrawsNothing() {
        let empty = UIHostingController(
            rootView: PhotoCarouselView(items: [], selectedPhotoID: .constant(nil), sendExif: true)
        ).sizeThatFits(in: CGSize(width: 402, height: 874))
        let filled = UIHostingController(
            rootView: PhotoCarouselView(items: makeItems(2), selectedPhotoID: .constant(nil), sendExif: true)
        ).sizeThatFits(in: CGSize(width: 402, height: 874))

        XCTAssertLessThan(empty.height, filled.height)
    }
}

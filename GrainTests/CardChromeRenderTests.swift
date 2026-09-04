@testable import Grain
import SwiftUI
import XCTest

/// The small pieces drawn around a gallery card: the page dots, the toasts a
/// share or a copy puts up, the long-press action sheet, and the thumbnails in
/// a profile grid.
@MainActor
final class CardChromeRenderTests: XCTestCase {
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

    /// The dots collapse past five, and the current one is drawn larger, so the
    /// indicator is rendered at each shape it takes.
    func testRendersThePageIndicatorAtEachShape() {
        func photos(_ count: Int, portrait: Bool = false) -> [GrainPhoto] {
            (0 ..< count).map { index in
                GrainPhoto(
                    uri: "at://did:plc:test/social.grain.photo/\(index)",
                    cid: "bafy\(index)",
                    thumb: "https://test.local/t.jpg",
                    fullsize: "https://test.local/f.jpg",
                    aspectRatio: portrait ? AspectRatio(width: 2, height: 3) : AspectRatio(width: 3, height: 2)
                )
            }
        }

        // One photo draws nothing; three fits; eight has to window.
        ViewRender.render(PageIndicatorView(photos: photos(1), currentPage: 0, hasPortrait: false), settle: 0)
        ViewRender.render(PageIndicatorView(photos: photos(3), currentPage: 1, hasPortrait: false), settle: 0)
        for page in [0, 3, 7] {
            ViewRender.render(PageIndicatorView(photos: photos(8), currentPage: page, hasPortrait: false), settle: 0)
        }
        // A portrait photo in the set flips the dots to a darker tint.
        ViewRender.render(PageIndicatorView(photos: photos(4), currentPage: 0, hasPortrait: true), settle: 0)
        ViewRender.render(
            PageIndicatorView(photos: photos(4, portrait: true), currentPage: 0, hasPortrait: true), settle: 0
        )
    }

    /// A single photo has nothing to page between, so the indicator has to take
    /// no space rather than draw one lonely dot.
    func testThePageIndicatorIsEmptyForASinglePhoto() {
        let single = [GrainPhoto(
            uri: "at://did:plc:test/social.grain.photo/1", cid: "c",
            thumb: "https://test.local/t.jpg", fullsize: "https://test.local/f.jpg",
            aspectRatio: AspectRatio(width: 3, height: 2)
        )]

        let one = UIHostingController(rootView: PageIndicatorView(photos: single, currentPage: 0, hasPortrait: false))
            .sizeThatFits(in: CGSize(width: 402, height: 100))
        let many = UIHostingController(
            rootView: PageIndicatorView(photos: single + single, currentPage: 0, hasPortrait: false)
        ).sizeThatFits(in: CGSize(width: 402, height: 100))

        XCTAssertLessThan(one.height, many.height)
    }

    func testRendersTheCopiedToast() {
        ViewRender.render(CopiedToastView(), settle: 0)
    }

    func testRendersTheCopiedCheckmarkToast() {
        ViewRender.render(CopiedCheckmarkToast(), settle: 0)
    }

    /// The long-press menu on a card — report on someone else's, delete on your
    /// own, and both absent when neither applies.
    func testRendersTheCardActionsSheetForEachOwner() {
        ViewRender.render(GalleryActionsSheet(onReport: {}, onDelete: nil), settle: 0)
        ViewRender.render(GalleryActionsSheet(onReport: nil, onDelete: {}), settle: 0)
        ViewRender.render(GalleryActionsSheet(onReport: {}, onDelete: {}), settle: 0)
        ViewRender.render(GalleryActionsSheet(), settle: 0)
    }

    /// Profile grid thumbnails are drawn from Nuke's cache when it has them and
    /// loaded lazily when it doesn't.
    func testRendersAProfileGridThumbnail() {
        ViewRender.render(ProfileGridThumbnail(urlString: "https://test.local/thumb.jpg"), settle: 0.2)
        ViewRender.render(ProfileGridThumbnail(urlString: ""), settle: 0.1)
        ViewRender.render(ProfileGridThumbnail(urlString: "not a url"), settle: 0.1)
    }
}

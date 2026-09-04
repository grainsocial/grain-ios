@testable import Grain
import SwiftUI
import XCTest

/// The create sheet once photos have been chosen, and the profile on each of
/// its tabs. Both are most of a screen that only exists past a step a render
/// can't take — picking from the library, or tapping a tab.
@MainActor
final class CreateSheetRenderTests: XCTestCase {
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

    private let settle: TimeInterval = 0.4

    private func makeItems(_ count: Int, withExif: Bool = false, alt: Bool = false) -> [PhotoItem] {
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
            let size = index.isMultiple(of: 2)
                ? CGSize(width: 120, height: 80)
                : CGSize(width: 80, height: 120)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                context.cgContext.setFillColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)
                context.cgContext.fill(CGRect(origin: .zero, size: size))
            }
            return PhotoItem(
                thumbnail: image,
                carouselPreview: image,
                source: .camera(image, metadata: nil),
                alt: alt ? "Alt text for photo \(index)" : "",
                exifSummary: withExif && index.isMultiple(of: 2) ? exif : nil
            )
        }
    }

    private func renderSheet(_ items: [PhotoItem], env: TestEnvironment) {
        ViewRender.render(
            CreateGalleryView(client: env.client, onCreated: {}, photoItems: items)
                .withTestEnvironment(env),
            settle: settle
        )
    }

    // MARK: - Create sheet

    /// The state the sheet is actually used in: photos picked, editor up, Post
    /// enabled.
    func testRendersTheCreateSheetWithPhotosChosen() {
        let env = TestEnvironment()

        renderSheet(makeItems(4), env: env)
    }

    /// Exif and alt text each add a row under the carousel.
    func testRendersTheCreateSheetWithExifAndAltText() {
        let env = TestEnvironment()

        renderSheet(makeItems(3, withExif: true, alt: true), env: env)
    }

    /// One photo has no strip to scroll; a full gallery does.
    func testRendersTheCreateSheetAtBothEndsOfItsRange() {
        let env = TestEnvironment()

        renderSheet(makeItems(1), env: env)
        renderSheet(makeItems(9), env: env)
    }

    /// Before the picker returns, which is the state it opens in.
    func testRendersTheCreateSheetWithNothingChosenYet() {
        let env = TestEnvironment()

        renderSheet([], env: env)
    }

    /// A resumed publish puts the pending bar up over the sheet.
    func testRendersTheCreateSheetWhileAGalleryIsStillGoingOut() {
        let env = TestEnvironment()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("createsheet-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = GalleryDraftStore(root: root)
        store.save(GalleryDraft(
            repo: "did:plc:test",
            title: "Still going",
            description: "",
            labels: [],
            location: nil,
            includeExif: false,
            postToBluesky: false,
            createdAt: DateFormatting.nowISO(),
            galleryRkey: TID.next(),
            blueskyRkey: TID.next(),
            photos: []
        ))
        env.uploadCenter.accountChanged(to: "did:plc:test")

        renderSheet(makeItems(2), env: env)
    }

    // MARK: - Profile tabs

    /// Each tab is a different grid with a different fetch behind it; the
    /// profile opens on the first, so the others are otherwise unreachable.
    func testRendersEachProfileTab() {
        let env = TestEnvironment()

        for mode in ProfileViewMode.allCases {
            ViewRender.render(
                ProfileView(client: env.client, did: "did:plc:test", isRoot: true, viewMode: mode)
                    .withTestEnvironment(env),
                settle: settle
            )
        }
    }

    /// Someone else's profile has no archive of your own stories and a
    /// different set of actions.
    func testRendersEachTabOfSomeoneElsesProfile() {
        let env = TestEnvironment()

        for mode in ProfileViewMode.allCases {
            ViewRender.render(
                ProfileView(client: env.client, did: "did:plc:other", isRoot: false, viewMode: mode)
                    .withTestEnvironment(env),
                settle: settle
            )
        }
    }

    /// A tab whose fetch fails shows its own empty state rather than blanking
    /// the whole profile.
    func testRendersAProfileTabWhoseContentFailsToLoad() {
        MockURLProtocol.respondByPath(["getActorProfile": Fixtures.profileDetailed], fallback: "{}")
        let env = TestEnvironment()

        for mode in ProfileViewMode.allCases {
            ViewRender.render(
                ProfileView(client: env.client, did: "did:plc:test", isRoot: true, viewMode: mode)
                    .withTestEnvironment(env),
                settle: 0.3
            )
        }
    }

    /// The favorites tab is the one with the disk cache behind it, so it can
    /// have content before its fetch lands.
    func testRendersTheFavoritesTabForYourOwnProfile() {
        let env = TestEnvironment()

        ViewRender.render(
            ProfileView(client: env.client, did: "did:plc:test", isRoot: true, viewMode: .favorites)
                .withTestEnvironment(env),
            settle: 0.5
        )
    }

    func testRendersTheProfileModesRawValues() {
        XCTAssertEqual(ProfileViewMode.allCases.map(\.rawValue), ["grid", "favorites", "stories"])
    }
}

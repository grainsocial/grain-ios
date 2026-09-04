@testable import Grain
import SwiftUI
import XCTest

/// The create flow's chrome: the editor that morphs between three layouts, and
/// the publish overlay that covers the sheet while a gallery goes out. Both are
/// driven entirely by bindings and values, so they can be put into every state
/// they have without a picker or a network.
@MainActor
final class CreateFlowRenderTests: GrainTestCase {
    private var account: TestAccount!

    /// Async overrides: the synchronous `setUp`/`tearDown` are nonisolated, so
    /// touching main-actor state from them warns.
    override func setUp() async throws {
        try await super.setUp()
        account = TestAccount()
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        account.restore()
        try await super.tearDown()
    }

    // MARK: - Items

    private func makeItems(_ count: Int, withExif: Bool = false) -> [PhotoItem] {
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
            // Alternate portrait and landscape so both mask-fill branches run.
            let size = index.isMultiple(of: 2)
                ? CGSize(width: 90, height: 60)
                : CGSize(width: 60, height: 90)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                context.cgContext.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
                context.cgContext.fill(CGRect(origin: .zero, size: size))
            }
            return PhotoItem(
                thumbnail: image,
                carouselPreview: image,
                source: .camera(image, metadata: nil),
                alt: index.isMultiple(of: 3) ? "Alt text for photo \(index)" : "",
                exifSummary: withExif && index.isMultiple(of: 2) ? exif : nil
            )
        }
    }

    private func renderEditor(
        items: [PhotoItem],
        mode: EditorMode,
        selected: UUID?,
        isReordering: Bool = false,
        sendExif: Bool = true,
        onDelete: ((PhotoItem) -> Void)? = nil,
        settle: TimeInterval = 0.05
    ) {
        var boundItems = items
        var boundSelected = selected
        var boundReordering = isReordering
        var boundAnimating = false
        var boundMode = mode

        ViewRender.render(
            GalleryEditor(
                items: Binding(get: { boundItems }, set: { boundItems = $0 }),
                selectedPhotoID: Binding(get: { boundSelected }, set: { boundSelected = $0 }),
                isReordering: Binding(get: { boundReordering }, set: { boundReordering = $0 }),
                isAnimatingMode: Binding(get: { boundAnimating }, set: { boundAnimating = $0 }),
                mode: Binding(get: { boundMode }, set: { boundMode = $0 }),
                sendExif: sendExif,
                onDeleteItem: onDelete
            )
            .withTestEnvironment(TestEnvironment()),
            settle: settle
        )
    }

    // MARK: - Gallery editor

    /// Enough photos that the strip overflows and the grid needs three rows,
    /// which is the shape the editor is actually used in.
    func testRendersTheEditorInEveryModeWithAFullGallery() {
        let items = makeItems(8, withExif: true)
        for mode in EditorMode.allCases {
            renderEditor(items: items, mode: mode, selected: items.first?.id)
        }
    }

    /// Nothing selected is the state the editor opens in before a tap.
    func testRendersTheEditorWithNothingSelected() {
        for mode in EditorMode.allCases {
            renderEditor(items: makeItems(4), mode: mode, selected: nil)
        }
    }

    /// A selection late in the strip forces it to scroll to bring the cell into
    /// view, which is different arithmetic from the first cell.
    func testRendersTheEditorWithALateSelection() {
        let items = makeItems(9)
        renderEditor(items: items, mode: .preview, selected: items.last?.id, settle: 0.2)
        renderEditor(items: items, mode: .reorder, selected: items[5].id, settle: 0.2)
    }

    /// Reordering locks the surrounding scroll views and swaps the cell chrome.
    func testRendersTheEditorWhileReordering() {
        let items = makeItems(6)
        renderEditor(items: items, mode: .reorder, selected: items[1].id, isReordering: true, settle: 0.2)
    }

    /// With exif off the chips go grey rather than disappearing, so the row
    /// doesn't reflow when the toggle moves.
    func testRendersTheEditorWithExifTurnedOff() {
        let items = makeItems(4, withExif: true)
        renderEditor(items: items, mode: .captions, selected: items.first?.id, sendExif: false)
    }

    /// A single photo has no strip to scroll and no grid to speak of.
    func testRendersTheEditorWithASinglePhoto() {
        let items = makeItems(1)
        for mode in EditorMode.allCases {
            renderEditor(items: items, mode: mode, selected: items.first?.id)
        }
    }

    /// The editor is built before the picker returns, so it has to survive
    /// being asked to lay out nothing.
    func testRendersTheEditorWithNoPhotosYet() {
        for mode in EditorMode.allCases {
            renderEditor(items: [], mode: mode, selected: nil)
        }
    }

    func testRendersTheEditorWithADeleteHandler() {
        let items = makeItems(3)
        renderEditor(items: items, mode: .preview, selected: items.first?.id, onDelete: { _ in })
    }

    // MARK: - Captions prototype

    func testRendersTheCaptionsListPrototype() {
        ViewRender.render(CaptionsListPrototype(), settle: 0.2)
    }

    // MARK: - Publish overlay

    /// The overlay covers the whole sheet, so every stage has to draw something
    /// — an indeterminate spinner, a determinate bar, or the failure.
    func testRendersThePublishOverlayForEveryStage() {
        let stages: [GalleryUploadCenter.Stage] = [
            .idle,
            .preparing(completed: 0, total: 8),
            .preparing(completed: 4, total: 8),
            .uploading(completed: 0, total: 8),
            .uploading(completed: 7, total: 8),
            .publishing,
            .finished,
            .failed(message: "The connection dropped. Nothing was lost — trying again picks up where it stopped."),
        ]

        for stage in stages {
            ViewRender.render(
                GalleryPublishOverlay(stage: stage, onRetry: {}, onPostLater: {}),
                settle: 0
            )
        }
    }

    /// A zero-photo total would divide by zero in the progress fraction.
    func testRendersThePublishOverlayWithNoPhotosToCount() {
        ViewRender.render(
            GalleryPublishOverlay(stage: .uploading(completed: 0, total: 0), onRetry: {}, onPostLater: {}),
            settle: 0
        )
    }

    // MARK: - Pending gallery bar

    /// The bar is what "post later" leads to. It shows progress while the
    /// resume runs, an error when it fails again, and nothing at all when
    /// there's nothing outstanding.
    func testRendersThePendingBarForEveryStage() {
        let cases: [(GalleryUploadCenter.Stage, Int)] = [
            (.uploading(completed: 2, total: 5), 1),
            (.publishing, 1),
            (.preparing(completed: 1, total: 3), 1),
            (.failed(message: "Couldn't finish"), 1),
            (.idle, 1),
            (.idle, 0),
            (.failed(message: "Couldn't finish"), 0),
            (.finished, 0),
        ]

        for (stage, pendingCount) in cases {
            ViewRender.render(
                PendingGalleryBar(stage: stage, pendingCount: pendingCount, onRetry: {}, onDiscard: {}),
                settle: 0
            )
        }
    }

    /// With nothing pending and nothing in flight the bar must add no chrome —
    /// it sits directly above the tab bar.
    func testThePendingBarIsEmptyWhenThereIsNothingToSay() {
        let empty = UIHostingController(
            rootView: PendingGalleryBar(stage: .idle, pendingCount: 0, onRetry: {}, onDiscard: {})
        ).sizeThatFits(in: CGSize(width: 402, height: 200))
        let busy = UIHostingController(
            rootView: PendingGalleryBar(
                stage: .uploading(completed: 1, total: 3), pendingCount: 1, onRetry: {}, onDiscard: {}
            )
        ).sizeThatFits(in: CGSize(width: 402, height: 200))

        XCTAssertLessThan(empty.height, busy.height)
    }

    // MARK: - Create sheet

    /// The sheet before any photo has been picked — the state it opens in.
    func testRendersTheCreateGallerySheet() {
        MockURLProtocol.respondByPath(Fixtures.routes)
        defer { MockURLProtocol.handler = nil }
        let env = TestEnvironment()

        ViewRender.render(CreateGalleryView(client: env.client).withTestEnvironment(env), settle: 0.3)
    }

    func testRendersTheStoryCreateSheet() {
        MockURLProtocol.respondByPath(Fixtures.routes)
        defer { MockURLProtocol.handler = nil }
        let env = TestEnvironment()

        ViewRender.render(StoryCreateView(client: env.client).withTestEnvironment(env), settle: 0.3)
    }
}

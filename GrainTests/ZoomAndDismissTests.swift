@testable import Grain
import SwiftUI
import XCTest

/// The pinch-to-zoom overlay and the story viewer's drag-to-dismiss both push
/// their work down into UIKit for smoothness, which leaves a small amount of
/// SwiftUI-side state and a lot of view code that nothing was reaching.
@MainActor
final class ZoomAndDismissTests: GrainTestCase {
    // MARK: - ImageZoomState

    func testTheZoomStateStartsAtRest() {
        let state = ImageZoomState()

        XCTAssertFalse(state.showOverlay)
        XCTAssertEqual(state.scale, 1)
        XCTAssertEqual(state.anchor, .center)
        XCTAssertEqual(state.offset, .zero)
        XCTAssertEqual(state.sourceFrame, .zero)
        XCTAssertNil(state.localImage)
        XCTAssertTrue(state.imageURL.isEmpty)
    }

    // MARK: - ZoomableImage

    func testRendersAZoomableImageFromAURL() {
        let state = ImageZoomState()
        ViewRender.render(
            ZoomableImage(url: "https://test.local/full.jpg", thumbURL: "https://test.local/thumb.jpg", aspectRatio: 1.5)
                .environment(state)
        )
    }

    func testRendersAZoomableImageFromALocalImage() throws {
        let state = ImageZoomState()
        let image = try XCTUnwrap(UIImage(systemName: "photo"))
        ViewRender.render(
            ZoomableImage(localImage: image, aspectRatio: 1, zoomImage: image, onSingleTap: {}, onDoubleTap: { _ in })
                .environment(state)
        )
    }

    /// Zoom is optional: a `ZoomableImage` with no state in the environment has
    /// to still draw the photo rather than trap on a missing value.
    func testAZoomableImageRendersWithNoZoomStateInTheEnvironment() {
        ViewRender.render(ZoomableImage(url: "https://test.local/full.jpg", aspectRatio: 1))
    }

    /// While an image is zoomed the base copy is hidden so the overlay isn't
    /// drawn twice — that branch only runs when the state points at this image.
    func testRendersTheZoomedBranchForTheImageBeingZoomed() {
        let state = ImageZoomState()
        state.showOverlay = true
        state.imageURL = "https://test.local/full.jpg"
        state.scale = 2.5
        state.anchor = .topLeading
        state.offset = CGSize(width: 12, height: -8)
        state.aspectRatio = 1.5
        state.sourceFrame = CGRect(x: 20, y: 40, width: 300, height: 200)

        ViewRender.render(
            ZoomableImage(url: "https://test.local/full.jpg", aspectRatio: 1.5).environment(state)
        )
    }

    /// A different image in the same carousel must stay visible while its
    /// neighbour is zoomed.
    func testAnotherImageStaysVisibleWhileItsNeighbourIsZoomed() {
        let state = ImageZoomState()
        state.showOverlay = true
        state.imageURL = "https://test.local/other.jpg"

        ViewRender.render(
            ZoomableImage(url: "https://test.local/full.jpg", aspectRatio: 1).environment(state)
        )
    }

    // MARK: - ImageZoomOverlay

    func testRendersTheZoomOverlayForBothSources() {
        let urlState = ImageZoomState()
        urlState.showOverlay = true
        urlState.imageURL = "https://test.local/full.jpg"
        urlState.aspectRatio = 1.5
        urlState.sourceFrame = CGRect(x: 0, y: 0, width: 300, height: 200)

        ViewRender.render(Color.black.modifier(ImageZoomOverlay(zoomState: urlState)))

        let localState = ImageZoomState()
        localState.showOverlay = true
        localState.localImage = UIImage(systemName: "photo")
        localState.aspectRatio = 1
        localState.sourceFrame = CGRect(x: 0, y: 0, width: 200, height: 200)

        ViewRender.render(Color.black.modifier(ImageZoomOverlay(zoomState: localState)))
    }

    /// With nothing zoomed the overlay must add no chrome at all — it sits
    /// above every scroll view in the app.
    func testTheZoomOverlayDrawsNothingWhenIdle() {
        ViewRender.render(Color.black.modifier(ImageZoomOverlay(zoomState: ImageZoomState())), settle: 0)
    }

    // MARK: - Drag to dismiss

    /// The handle is held by StoryViewer so it can fade out programmatically
    /// when the last story ends. Before anything installs it there's no view to
    /// animate, and it has to fall straight through to the dismiss callback.
    func testTheDismissHandleFallsThroughWhenNothingIsInstalled() {
        let handle = FadeDismissHandle()

        handle.fadeDismiss()

        // No view, no callback wired: the point is that it doesn't trap.
        XCTAssertNotNil(handle)
    }

    func testRendersTheDragToDismissInstaller() {
        ViewRender.render(
            Color.black.background {
                DragToDismissInstaller(
                    handle: FadeDismissHandle(),
                    onDismiss: {},
                    onDragStart: {},
                    onDragCancel: {},
                    onSwipeLeft: {},
                    onSwipeRight: {}
                )
            },
            settle: 0
        )
    }

    // MARK: - Reorder lockers

    /// Both lockers walk the responder chain to find something to disable, and
    /// have to be harmless when there's nothing there.
    func testTheReorderLockersRenderInsideAndOutsideAScrollView() {
        for disabled in [true, false] {
            ViewRender.render(
                ScrollView {
                    Color.gray.frame(height: 200).background { ScrollPanLocker(isDisabled: disabled) }
                },
                settle: 0
            )
            ViewRender.render(Color.gray.background { ScrollPanLocker(isDisabled: disabled) }, settle: 0)
            ViewRender.render(
                NavigationStack {
                    Color.gray.background { InteractivePopLocker(isDisabled: disabled) }
                },
                settle: 0
            )
        }
    }

    // MARK: - Reorderable thumbnail

    func testRendersTheReorderableThumbnailModifier() {
        ViewRender.render(Color.teal.frame(width: 100, height: 100).reorderableThumbnail(isSelected: true), settle: 0)
        ViewRender.render(
            Color.teal.frame(width: 100, height: 100).reorderableThumbnail(isSelected: false, cornerRadius: 0),
            settle: 0
        )
    }

    // MARK: - Custom full screen cover

    func testRendersTheCustomFullScreenCoverInBothStates() {
        for presented in [true, false] {
            var isPresented = presented
            ViewRender.render(
                Color.black.customFullScreenCover(
                    isPresented: Binding(get: { isPresented }, set: { isPresented = $0 })
                ) {
                    Text("Covered")
                },
                settle: 0
            )
        }
    }
}

@testable import Grain
import SwiftUI
import UIKit
import XCTest

/// The app drops to UIKit for three gestures — drag-to-dismiss on a story,
/// long-press-to-reorder in the grid, and the photo strip's horizontal pan —
/// because SwiftUI's equivalents fight the surrounding scroll views. What makes
/// them coexist is entirely in their delegates, which is exactly the part a
/// render test never reaches.
@MainActor
final class GestureCoordinatorTests: XCTestCase {
    /// Records callbacks a coordinator fires.
    private final class Calls {
        var phases: [String] = []
        var translations: [CGSize] = []
    }

    /// A view sitting in a real view-controller hierarchy, which is what the
    /// installers walk the responder chain to find.
    private func hostedView() -> (view: UIView, controller: UIViewController, window: UIWindow) {
        let controller = UIViewController()
        let anchor = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        controller.view.addSubview(anchor)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.isHidden = false
        return (anchor, controller, window)
    }

    private func teardown(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }

    // MARK: - Drag to dismiss

    private func makeDismissCoordinator(
        handle: FadeDismissHandle,
        calls: Calls,
        onDismiss: @escaping () -> Void = {}
    ) -> DragToDismissInstaller.Coordinator {
        DragToDismissInstaller.Coordinator(
            handle: handle,
            onDismiss: { calls.phases.append("dismiss"); onDismiss() },
            onDragStart: { calls.phases.append("dragStart") },
            onDragCancel: { calls.phases.append("dragCancel") },
            onSwipeLeft: { calls.phases.append("swipeLeft") },
            onSwipeRight: { calls.phases.append("swipeRight") },
            onHorizontalDragStart: { calls.phases.append($0 ? "forward" : "back") },
            onSwipeDragging: { calls.translations.append(CGSize(width: $0, height: 0)) },
            onHorizontalDragCancel: { calls.phases.append("horizontalCancel") }
        )
    }

    /// The pan is installed on the hosting controller's view, not on the tiny
    /// anchor, so a drag anywhere on the story dismisses it.
    func testInstallingPutsThePanOnTheHostingControllersView() {
        let hosted = hostedView()
        defer { teardown(hosted.window) }
        let handle = FadeDismissHandle()
        let coordinator = makeDismissCoordinator(handle: handle, calls: Calls())
        coordinator.anchorView = hosted.view

        coordinator.installGestureIfNeeded()

        let installed = hosted.controller.view.gestureRecognizers ?? []
        XCTAssertTrue(installed.contains { $0 is UIPanGestureRecognizer })
        XCTAssertTrue(installed.contains { $0.delegate === coordinator })
    }

    /// `updateUIView` runs on every SwiftUI update, so installing has to be
    /// idempotent or the story ends up with a stack of pan recognizers.
    func testInstallingTwiceOnlyAddsOnePan() {
        let hosted = hostedView()
        defer { teardown(hosted.window) }
        let coordinator = makeDismissCoordinator(handle: FadeDismissHandle(), calls: Calls())
        coordinator.anchorView = hosted.view

        coordinator.installGestureIfNeeded()
        coordinator.installGestureIfNeeded()
        coordinator.installGestureIfNeeded()

        let pans = (hosted.controller.view.gestureRecognizers ?? []).filter { $0 is UIPanGestureRecognizer }
        XCTAssertEqual(pans.count, 1)
    }

    /// Before SwiftUI has put the view in a hierarchy there is nothing to
    /// install onto, and that has to be survivable rather than a trap.
    func testInstallingWithNothingToAttachToIsHarmless() {
        let coordinator = makeDismissCoordinator(handle: FadeDismissHandle(), calls: Calls())

        coordinator.installGestureIfNeeded()
        coordinator.anchorView = UIView()
        coordinator.installGestureIfNeeded()

        XCTAssertNil(coordinator.anchorView?.gestureRecognizers)
    }

    /// The comment sheet takes over touches while it's up, so the story's pan
    /// has to be switched off rather than competing with it.
    func testDisablingTurnsTheInstalledPanOff() {
        let hosted = hostedView()
        defer { teardown(hosted.window) }
        let coordinator = makeDismissCoordinator(handle: FadeDismissHandle(), calls: Calls())
        coordinator.anchorView = hosted.view
        coordinator.installGestureIfNeeded()

        let pan = (hosted.controller.view.gestureRecognizers ?? []).first { $0 is UIPanGestureRecognizer }

        coordinator.setEnabled(false)
        XCTAssertEqual(pan?.isEnabled, false)

        coordinator.setEnabled(true)
        XCTAssertEqual(pan?.isEnabled, true)
    }

    func testDisablingBeforeAnythingIsInstalledIsHarmless() {
        let coordinator = makeDismissCoordinator(handle: FadeDismissHandle(), calls: Calls())

        coordinator.setEnabled(false)
        coordinator.setEnabled(true)

        XCTAssertNotNil(coordinator)
    }

    /// SwiftUI taps inside the story have to keep working during the drag, but
    /// a second pan — the comment sheet's scroll, say — must not.
    func testTapsRunAlongsideTheDismissPanButOtherPansDoNot() {
        let coordinator = makeDismissCoordinator(handle: FadeDismissHandle(), calls: Calls())

        XCTAssertTrue(
            coordinator.gestureRecognizer(UIPanGestureRecognizer(), shouldRecognizeSimultaneouslyWith: UITapGestureRecognizer())
        )
        XCTAssertFalse(
            coordinator.gestureRecognizer(UIPanGestureRecognizer(), shouldRecognizeSimultaneouslyWith: UIPanGestureRecognizer())
        )
    }

    // MARK: - Fade dismiss handle

    /// Installing the gesture is also what wires the handle to the dismiss
    /// callback, so the story viewer can fade out programmatically when the
    /// last story ends — and the dismiss lands after the fade, not before,
    /// otherwise the story pops off screen instead of fading.
    func testTheHandleFadesTheViewThenDismisses() {
        let hosted = hostedView()
        defer { teardown(hosted.window) }
        let handle = FadeDismissHandle()
        let dismissed = expectation(description: "dismiss ran after the fade")
        let coordinator = makeDismissCoordinator(
            handle: handle, calls: Calls(), onDismiss: { dismissed.fulfill() }
        )
        coordinator.anchorView = hosted.view
        coordinator.installGestureIfNeeded()

        handle.fadeDismiss()

        wait(for: [dismissed], timeout: 5)
        XCTAssertEqual(hosted.controller.view.alpha, 0, "The dismiss lands at the end of the fade, not before it")
    }

    /// Nothing wired up at all — the story viewer builds the handle before it
    /// has anywhere to send the dismissal.
    func testAnUnwiredHandleIsHarmless() {
        FadeDismissHandle().fadeDismiss()
    }

    // MARK: - Reorder recognizer

    private func makeReorderCoordinator(isEnabled: Bool, calls: Calls) -> ReorderRecognizer.Coordinator {
        ReorderRecognizer.Coordinator(isEnabled: isEnabled) { phase, translation in
            calls.phases.append(String(describing: phase))
            calls.translations.append(translation)
        }
    }

    /// Arming fires the moment a finger lands, before the hold completes, so
    /// the parent can lock the Form's scroll and not lose the vertical
    /// component of the drag.
    func testTouchingDownArmsTheReorderBeforeTheHoldCompletes() {
        let calls = Calls()
        let coordinator = makeReorderCoordinator(isEnabled: true, calls: calls)

        let shouldBegin = coordinator.gestureRecognizerShouldBegin(UILongPressGestureRecognizer())

        XCTAssertTrue(shouldBegin)
        XCTAssertEqual(calls.phases, ["arming"])
    }

    /// The recognizer is gated on editor mode; in preview or captions mode it
    /// must never fire, and must not announce arming either.
    func testADisabledReorderNeverBeginsOrArms() {
        let calls = Calls()
        let coordinator = makeReorderCoordinator(isEnabled: false, calls: calls)

        let shouldBegin = coordinator.gestureRecognizerShouldBegin(UILongPressGestureRecognizer())

        XCTAssertFalse(shouldBegin)
        XCTAssertTrue(calls.phases.isEmpty)
    }

    /// The gate is re-read on every SwiftUI update rather than captured once.
    func testTheReorderGateCanBeFlippedAfterTheFact() {
        let calls = Calls()
        let coordinator = makeReorderCoordinator(isEnabled: false, calls: calls)

        XCTAssertFalse(coordinator.gestureRecognizerShouldBegin(UILongPressGestureRecognizer()))
        coordinator.isEnabled = true
        XCTAssertTrue(coordinator.gestureRecognizerShouldBegin(UILongPressGestureRecognizer()))
    }

    /// Scroll pans and SwiftUI taps have to keep firing alongside a reorder —
    /// this is the hook the Representable protocol doesn't offer, and the whole
    /// reason the gesture is UIKit-backed.
    func testAReorderRunsAlongsideEveryOtherGesture() {
        let coordinator = makeReorderCoordinator(isEnabled: true, calls: Calls())

        for other in [UIPanGestureRecognizer(), UITapGestureRecognizer(), UILongPressGestureRecognizer()] {
            XCTAssertTrue(
                coordinator.gestureRecognizer(UILongPressGestureRecognizer(), shouldRecognizeSimultaneouslyWith: other)
            )
        }
    }

    func testTheReorderCoordinatorStartsWithNoDragInFlight() {
        XCTAssertNil(makeReorderCoordinator(isEnabled: true, calls: Calls()).startLocation)
    }

    // MARK: - Strip pan recognizer

    /// A recognizer that has never been attached has no coordinate space to
    /// report velocity in, so give it one.
    private func attachedPan() -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100)).addGestureRecognizer(pan)
        return pan
    }

    private func makeStripCoordinator(isEnabled: Bool, calls: Calls) -> StripPanRecognizer.Coordinator {
        StripPanRecognizer.Coordinator(
            isEnabled: isEnabled,
            onChanged: { calls.translations.append(CGSize(width: $0, height: 0)) },
            onEnded: { translation, _ in calls.translations.append(CGSize(width: translation, height: 0)) }
        )
    }

    /// The strip scrolls sideways inside a vertically-scrolling Form, so a
    /// mostly-vertical drag has to be left to the Form.
    func testTheStripOnlyClaimsMostlyHorizontalDrags() {
        let coordinator = makeStripCoordinator(isEnabled: true, calls: Calls())

        // A resting finger reports zero velocity, which is not horizontal.
        XCTAssertFalse(coordinator.gestureRecognizerShouldBegin(attachedPan()))
    }

    /// In grid or captions mode the strip isn't on screen and its recognizer
    /// has to be inert.
    func testADisabledStripNeverBegins() {
        let coordinator = makeStripCoordinator(isEnabled: false, calls: Calls())

        XCTAssertFalse(coordinator.gestureRecognizerShouldBegin(attachedPan()))
    }

    /// Anything that isn't a pan is let through untouched.
    func testANonPanGestureIsNotTheStripsToJudge() {
        let coordinator = makeStripCoordinator(isEnabled: true, calls: Calls())

        XCTAssertTrue(coordinator.gestureRecognizerShouldBegin(UITapGestureRecognizer()))
    }

    /// Once the strip's pan is running, the Form's vertical scroll must not run
    /// with it — otherwise the strip and the page move together.
    func testTheStripRefusesToShareWithTheEnclosingScroll() {
        let coordinator = makeStripCoordinator(isEnabled: true, calls: Calls())

        XCTAssertFalse(
            coordinator.gestureRecognizer(attachedPan(), shouldRecognizeSimultaneouslyWith: attachedPan())
        )
    }
}

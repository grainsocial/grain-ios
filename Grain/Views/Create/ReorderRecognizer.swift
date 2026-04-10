import SwiftUI
import UIKit

/// UIKit-backed long-press-then-drag gesture for reorderable cells inside Form rows.
///
/// SwiftUI's `LongPressGesture.sequenced(DragGesture)` doesn't cooperate with
/// `UIScrollView`'s pan recognizer on real touch hardware — even with
/// `.simultaneousGesture`, it stalls scroll AND blocks inner `.onTapGesture` during
/// its arming window. Dropping to UIKit lets us:
///   • set `cancelsTouchesInView = false` so taps still bubble up
///   • set `delaysTouchesBegan = false` so scrolls aren't held back
///   • assign a `UIGestureRecognizerDelegate` that returns `true` from
///     `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` so scroll pans and
///     SwiftUI tap recognizers fire alongside this one
///
/// `UIGestureRecognizerRepresentable` (iOS 18+) intentionally has no
/// simultaneous-recognition hook on the protocol itself — the only way to wire it is
/// via the recognizer's UIKit delegate. The Coordinator does double duty: it both
/// stores the gesture's start location AND acts as the delegate.
///
/// `UILongPressGestureRecognizer` continues sending `.changed` events as the finger
/// moves after the long press fires, so a single recognizer handles the entire
/// long-press → drag → release lifecycle without sequencing two gestures.
struct ReorderRecognizer: UIGestureRecognizerRepresentable {
    enum Phase {
        /// Fired the moment a touch begins on the cell — before the 0.18s hold
        /// completes. Lets the parent lock scroll immediately so the Form can't
        /// steal the vertical component of a reorder drag.
        case arming
        case began
        case changed
        case ended
        case cancelled
    }

    let minimumPressDuration: TimeInterval
    /// When false, `gestureRecognizerShouldBegin` returns false so the
    /// recognizer never fires. Used to gate on editor mode.
    var isEnabled: Bool
    let onChange: (Phase, CGSize) -> Void

    init(
        minimumPressDuration: TimeInterval = 0.18,
        isEnabled: Bool = true,
        onChange: @escaping (Phase, CGSize) -> Void
    ) {
        self.minimumPressDuration = minimumPressDuration
        self.isEnabled = isEnabled
        self.onChange = onChange
    }

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(isEnabled: isEnabled, onChange: onChange)
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumPressDuration
        // Tight arming tolerance — if the finger drifts more than this during
        // the pre-fire window, UIKit fails the recognizer and the parent
        // scroll pan takes over. Without this (previously unbounded), a user
        // trying to flick-scroll the grid would still commit the long press
        // at 0.18s and accidentally start a reorder drag. Note: this is the
        // ARMING tolerance only; once `.began` fires the finger can move
        // freely (UILongPressGestureRecognizer stops consulting
        // allowableMovement after recognition succeeds).
        recognizer.allowableMovement = 10
        // Critical for coexistence with SwiftUI taps and scroll pans:
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        // The delegate is what unlocks scroll + tap working alongside us. The
        // Representable protocol has NO simultaneous-recognition hook, so the only
        // way to get this is the UIKit delegate (verified against iOS 26 SDK
        // swiftinterface).
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.minimumPressDuration = minimumPressDuration
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onChange = onChange
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let coordinator = context.coordinator
        let location = recognizer.location(in: recognizer.view)

        switch recognizer.state {
        case .began:
            coordinator.startLocation = location
            coordinator.onChange(.began, .zero)
        case .changed:
            guard let start = coordinator.startLocation else { return }
            let translation = CGSize(
                width: location.x - start.x,
                height: location.y - start.y
            )
            coordinator.onChange(.changed, translation)
        case .ended:
            coordinator.onChange(.ended, .zero)
            coordinator.startLocation = nil
        case .cancelled, .failed:
            coordinator.onChange(.cancelled, .zero)
            coordinator.startLocation = nil
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var startLocation: CGPoint?
        var isEnabled: Bool
        var onChange: (Phase, CGSize) -> Void

        init(isEnabled: Bool, onChange: @escaping (Phase, CGSize) -> Void) {
            self.isEnabled = isEnabled
            self.onChange = onChange
        }

        nonisolated func gestureRecognizerShouldBegin(
            _: UIGestureRecognizer
        ) -> Bool {
            MainActor.assumeIsolated {
                if isEnabled { onChange(.arming, .zero) }
                return isEnabled
            }
        }

        nonisolated func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

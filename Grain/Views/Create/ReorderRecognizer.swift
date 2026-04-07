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
///   • implement `shouldRecognizeSimultaneouslyWith` to coexist with scroll pans
///
/// `UILongPressGestureRecognizer` continues sending `.changed` events as the finger
/// moves after the long press fires, so a single recognizer handles the entire
/// long-press → drag → release lifecycle without sequencing two gestures.
struct ReorderRecognizer: UIGestureRecognizerRepresentable {
    enum Phase {
        case began
        case changed
        case ended
        case cancelled
    }

    let minimumPressDuration: TimeInterval
    let onChange: (Phase, CGSize) -> Void

    init(minimumPressDuration: TimeInterval = 0.18, onChange: @escaping (Phase, CGSize) -> Void) {
        self.minimumPressDuration = minimumPressDuration
        self.onChange = onChange
    }

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context _: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumPressDuration
        // Effectively unbounded — once the long-press fires we don't want UIKit to
        // cancel it just because the finger moved a long way.
        recognizer.allowableMovement = .greatestFiniteMagnitude
        // Critical for coexistence with SwiftUI taps and scroll pans:
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context _: Context) {
        recognizer.minimumPressDuration = minimumPressDuration
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let coordinator = context.coordinator
        let location = recognizer.location(in: recognizer.view)

        switch recognizer.state {
        case .began:
            coordinator.startLocation = location
            onChange(.began, .zero)
        case .changed:
            guard let start = coordinator.startLocation else { return }
            let translation = CGSize(
                width: location.x - start.x,
                height: location.y - start.y
            )
            onChange(.changed, translation)
        case .ended:
            onChange(.ended, .zero)
            coordinator.startLocation = nil
        case .cancelled, .failed:
            onChange(.cancelled, .zero)
            coordinator.startLocation = nil
        default:
            break
        }
    }

    /// Allow scroll views and SwiftUI taps to recognize alongside this recognizer.
    /// Without this, holding-then-dragging on a cell would either eat the tap or
    /// block the parent Form's vertical scroll.
    func shouldRecognizeSimultaneously(
        with _: UIGestureRecognizer,
        in _: Context
    ) -> Bool {
        true
    }

    @MainActor
    final class Coordinator {
        var startLocation: CGPoint?
    }
}

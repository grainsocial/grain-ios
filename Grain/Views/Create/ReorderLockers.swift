import SwiftUI
import UIKit

/// Disables the nearest ancestor `UIScrollView`'s pan gesture recognizer when
/// `isDisabled` is true. Unlike SwiftUI's `.scrollDisabled`, this only blocks
/// USER-driven panning — programmatic `setContentOffset` / `ScrollViewProxy.scrollTo`
/// continues to work, which is essential for the strip's auto-scroll during a
/// reorder drag.
///
/// Attach as `.background { ScrollPanLocker(isDisabled: isReordering) }` on the
/// SwiftUI view that lives inside the scroll view whose pan you want to lock.
struct ScrollPanLocker: UIViewRepresentable {
    let isDisabled: Bool

    func makeUIView(context _: Context) -> RecognizerFinderView {
        let view = RecognizerFinderView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: RecognizerFinderView, context _: Context) {
        let disabled = isDisabled
        DispatchQueue.main.async {
            guard let scrollView = uiView.enclosingScrollView() else { return }
            // Toggling isEnabled on the pan recognizer immediately cancels any
            // in-flight drag and blocks new user pans, but leaves programmatic
            // setContentOffset untouched.
            scrollView.panGestureRecognizer.isEnabled = !disabled
        }
    }

    final class RecognizerFinderView: UIView {
        func enclosingScrollView() -> UIScrollView? {
            var responder: UIResponder? = self
            while let next = responder?.next {
                if let scrollView = next as? UIScrollView {
                    return scrollView
                }
                responder = next
            }
            return nil
        }
    }
}

/// Disables the enclosing `UINavigationController`'s interactive-pop gesture
/// recognizer when `isDisabled` is true. Use to prevent iOS's edge-swipe-to-pop
/// from firing while the user is in a reorder drag.
///
/// Attach as `.background { InteractivePopLocker(isDisabled: isReordering) }`
/// on the root view of the pushed view controller.
struct InteractivePopLocker: UIViewRepresentable {
    let isDisabled: Bool

    func makeUIView(context _: Context) -> ResponderFinderView {
        let view = ResponderFinderView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: ResponderFinderView, context _: Context) {
        let disabled = isDisabled
        DispatchQueue.main.async {
            guard let nav = uiView.enclosingNavigationController() else { return }
            nav.interactivePopGestureRecognizer?.isEnabled = !disabled
        }
    }

    final class ResponderFinderView: UIView {
        func enclosingNavigationController() -> UINavigationController? {
            var responder: UIResponder? = self
            while let next = responder?.next {
                if let vc = next as? UIViewController {
                    return vc.navigationController
                }
                responder = next
            }
            return nil
        }
    }
}

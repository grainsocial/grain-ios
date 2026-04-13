import SwiftUI

/// Shared handle so StoryViewer can trigger a fade-dismiss programmatically
/// (e.g. when all stories finish) using the same UIKit path as the drag gesture.
@MainActor
final class FadeDismissHandle {
    fileprivate weak var targetView: UIView?
    fileprivate var performDismiss: (() -> Void)?

    func fadeDismiss() {
        guard let view = targetView else {
            performDismiss?()
            return
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: {
            view.alpha = 0
            view.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }) { _ in
            if let vc = view.findViewController(),
               let presented = vc.presentedViewController ?? (vc.isBeingPresented ? vc : nil)
            {
                presented.dismiss(animated: false) {
                    view.alpha = 1
                    view.transform = .identity
                    self.performDismiss?()
                }
            } else {
                view.isHidden = true
                self.performDismiss?()
            }
        }
    }
}

/// Installs a UIKit UIPanGestureRecognizer on the hosting view controller's view
/// and applies CGAffineTransform directly — bypassing SwiftUI's rendering pipeline
/// for buttery smooth drag-to-dismiss.
struct DragToDismissInstaller: UIViewRepresentable {
    let handle: FadeDismissHandle
    let onDismiss: () -> Void
    let onDragStart: () -> Void
    let onDragCancel: () -> Void
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    var onSwipeUp: (() -> Void)?
    var onHorizontalDragStart: ((Bool) -> Void)? // true = swiping left (forward)
    var onSwipeDragging: ((CGFloat) -> Void)? // raw translation.x during drag
    var onHorizontalDragCancel: (() -> Void)?
    /// When false, the pan gesture is disabled so another presented view (e.g.
    /// a comment sheet) can own touches without interference.
    var isEnabled: Bool = true

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.anchorView = view
        DispatchQueue.main.async {
            context.coordinator.installGestureIfNeeded()
        }
        return view
    }

    func updateUIView(_: UIView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        context.coordinator.onDragStart = onDragStart
        context.coordinator.onDragCancel = onDragCancel
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
        context.coordinator.onSwipeUp = onSwipeUp
        context.coordinator.onHorizontalDragStart = onHorizontalDragStart
        context.coordinator.onSwipeDragging = onSwipeDragging
        context.coordinator.onHorizontalDragCancel = onHorizontalDragCancel
        context.coordinator.setEnabled(isEnabled)
        handle.performDismiss = onDismiss
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            handle: handle,
            onDismiss: onDismiss,
            onDragStart: onDragStart,
            onDragCancel: onDragCancel,
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            onHorizontalDragStart: onHorizontalDragStart,
            onSwipeDragging: onSwipeDragging,
            onHorizontalDragCancel: onHorizontalDragCancel
        )
    }

    private enum DragDirection {
        case none, vertical, horizontal
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let handle: FadeDismissHandle
        var onDismiss: () -> Void
        var onDragStart: () -> Void
        var onDragCancel: () -> Void
        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void
        var onSwipeUp: (() -> Void)?
        var onHorizontalDragStart: ((Bool) -> Void)?
        var onSwipeDragging: ((CGFloat) -> Void)?
        var onHorizontalDragCancel: (() -> Void)?

        weak var anchorView: UIView?
        private weak var targetView: UIView?
        private var panGesture: UIPanGestureRecognizer?
        private var direction: DragDirection = .none

        init(
            handle: FadeDismissHandle,
            onDismiss: @escaping () -> Void,
            onDragStart: @escaping () -> Void,
            onDragCancel: @escaping () -> Void,
            onSwipeLeft: @escaping () -> Void,
            onSwipeRight: @escaping () -> Void,
            onHorizontalDragStart: ((Bool) -> Void)? = nil,
            onSwipeDragging: ((CGFloat) -> Void)? = nil,
            onHorizontalDragCancel: (() -> Void)? = nil
        ) {
            self.handle = handle
            self.onDismiss = onDismiss
            self.onDragStart = onDragStart
            self.onDragCancel = onDragCancel
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
            onSwipeUp = nil
            self.onHorizontalDragStart = onHorizontalDragStart
            self.onSwipeDragging = onSwipeDragging
            self.onHorizontalDragCancel = onHorizontalDragCancel
        }

        func installGestureIfNeeded() {
            guard panGesture == nil, let anchor = anchorView else { return }
            guard let vc = anchor.findViewController() else { return }
            let target = vc.view!
            targetView = target
            handle.targetView = target
            handle.performDismiss = onDismiss
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            pan.delegate = self
            target.addGestureRecognizer(pan)
            panGesture = pan
        }

        func setEnabled(_ enabled: Bool) {
            panGesture?.isEnabled = enabled
        }

        /// Allow SwiftUI tap gestures to work simultaneously
        func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(other is UIPanGestureRecognizer)
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = targetView else { return }
            let translation = gesture.translation(in: view.superview ?? view)
            let velocity = gesture.velocity(in: view.superview ?? view)

            switch gesture.state {
            case .began:
                direction = .none

            case .changed:
                // Lock direction after enough movement
                if direction == .none {
                    let absX = abs(translation.x)
                    let absY = abs(translation.y)
                    if absX > 15 || absY > 15 {
                        if absY > absX, translation.y > 0 {
                            direction = .vertical
                            onDragStart()
                        } else if absY > absX, translation.y < 0, onSwipeUp != nil {
                            direction = .vertical
                        } else if absX > absY {
                            direction = .horizontal
                            onHorizontalDragStart?(translation.x < 0)
                        }
                    }
                }

                if direction == .vertical {
                    let ty = max(translation.y, 0)
                    let progress = min(ty / 300, 1)
                    let scale = 1 - progress * 0.1
                    view.transform = CGAffineTransform(translationX: 0, y: ty)
                        .scaledBy(x: scale, y: scale)
                    view.layer.cornerRadius = progress * 24
                    view.clipsToBounds = true
                } else if direction == .horizontal {
                    onSwipeDragging?(translation.x)
                }

            case .ended, .cancelled:
                if direction == .vertical, translation.y < -80 || velocity.y < -500 {
                    onSwipeUp?()
                    direction = .none
                    return
                }

                if direction == .vertical {
                    let ty = max(translation.y, 0)

                    let dismissThreshold = view.bounds.height * 0.35
                    if ty > dismissThreshold || velocity.y > 1200 {
                        // Throw downward off screen
                        let screenHeight = view.bounds.height
                        let speed = max(velocity.y, 800)
                        let remaining = screenHeight - ty + 100
                        let duration = min(max(Double(remaining / speed), 0.15), 0.3)
                        UIView.animate(withDuration: duration, delay: 0, options: .curveEaseIn) {
                            view.transform = CGAffineTransform(translationX: 0, y: screenHeight + 100)
                                .scaledBy(x: 0.9, y: 0.9)
                        } completion: { _ in
                            if let vc = view.findViewController(),
                               let presented = vc.presentedViewController ?? (vc.isBeingPresented ? vc : nil)
                            {
                                presented.dismiss(animated: false) {
                                    view.alpha = 1
                                    view.transform = .identity
                                    view.layer.cornerRadius = 0
                                    view.clipsToBounds = false
                                    self.onDismiss()
                                }
                            } else {
                                view.isHidden = true
                                self.onDismiss()
                            }
                        }
                    } else {
                        // Spring back
                        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
                            view.transform = .identity
                            view.layer.cornerRadius = 0
                            view.clipsToBounds = false
                        }
                        onDragCancel()
                    }
                } else if direction == .horizontal {
                    if translation.x < -80 || velocity.x < -500 {
                        onSwipeLeft()
                    } else if translation.x > 80 || velocity.x > 500 {
                        onSwipeRight()
                    } else {
                        onHorizontalDragCancel?()
                    }
                }

                direction = .none

            default:
                break
            }
        }
    }
}

private extension UIView {
    func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController {
                return vc
            }
            responder = next
        }
        return nil
    }
}

#Preview {
    // DragToDismiss is a UIKit-backed gesture modifier — preview shows it applied.
    @Previewable @State var dismissed = false
    ZStack {
        Color.black.ignoresSafeArea()
        Text(dismissed ? "Dismissed" : "Drag down to dismiss")
            .foregroundStyle(.white)
    }
}

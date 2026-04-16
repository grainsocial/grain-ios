import SwiftUI

/// UIKit gesture overlay for the crop view.
///
/// Replaces SwiftUI's `DragGesture` / `MagnifyGesture` with UIKit recognizers
/// so we can read the pinch location for anchor-based zoom. Handles:
/// - 1-finger drag: hit-test determines handle resize / crop move / image pan
/// - Pinch: anchor-based zoom with natural pan tracking
///
/// Frame is set to fitWidth+88 × fitHeight+88 so touches up to 44pt outside
/// the image reach handles at the boundary. `touchInset` converts raw gesture
/// locations back to image-local coordinates.
struct CropGestureOverlay: UIViewRepresentable {
    let state: CropState
    let frameSize: CGSize
    /// Extra padding beyond the image frame for edge/corner touch targets.
    var touchInset: CGFloat = 44

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let drag = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDrag(_:))
        )
        drag.minimumNumberOfTouches = 1
        drag.maximumNumberOfTouches = 1
        drag.delegate = context.coordinator
        view.addGestureRecognizer(drag)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_: UIView, context: Context) {
        context.coordinator.frameSize = frameSize
        context.coordinator.touchInset = touchInset
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, frameSize: frameSize, touchInset: touchInset)
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let state: CropState
        var frameSize: CGSize
        /// The gesture view extends this far beyond the image frame on each
        /// side. Subtracted from raw touch locations to get image-local coords.
        var touchInset: CGFloat

        // Pinch tracking
        private var pinchStartScale: CGFloat = 1
        private var pinchStartOffset: CGSize = .zero
        private var pinchStartLocation: CGPoint = .zero
        /// The overlay-space point that was under the initial pinch centroid.
        /// Kept fixed so the image zooms around this point.
        private var pinchAnchorOverlay: CGPoint = .zero

        init(state: CropState, frameSize: CGSize, touchInset: CGFloat) {
            self.state = state
            self.frameSize = frameSize
            self.touchInset = touchInset
        }

        /// Convert a raw gesture location to image-local coordinates
        /// by removing the touchInset padding.
        private func imagePoint(from gesture: UIGestureRecognizer) -> CGPoint {
            let raw = gesture.location(in: gesture.view)
            return CGPoint(x: raw.x - touchInset, y: raw.y - touchInset)
        }

        /// Allow pinch + drag to coexist (different touch counts, no conflict).
        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // MARK: 1-finger drag

        @objc func handleDrag(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                let viewPoint = imagePoint(from: gesture)

                // Check move indicator in screen space first — it may be
                // outside the image bounds and is never promoted to panImage.
                if state.moveIndicatorScreenRect.contains(viewPoint) {
                    state.activeHandle = .moveIndicator
                    state.dragStartCropRect = state.cropRect
                    state.dragStartImageOffset = state.imageOffset
                    return
                }

                let overlayPoint = state.viewToOverlayPoint(viewPoint)
                var handle = state.hitTest(point: overlayPoint)

                // When zoomed past 1x, promote interior to panImage
                // so panning is easy. Edges and corners stay active
                // for crop adjustment while zoomed.
                if state.imageScale > 1.0, handle == .moveCrop {
                    handle = .panImage
                }

                state.activeHandle = handle
                state.dragStartCropRect = state.cropRect
                state.dragStartImageOffset = state.imageOffset

            case .changed:
                guard let handle = state.activeHandle else { return }
                let translation = gesture.translation(in: gesture.view)
                let size = CGSize(width: translation.x, height: translation.y)

                switch handle {
                case .panImage:
                    state.handleImagePan(translation: size)
                case .moveCrop, .moveIndicator:
                    let overlay = state.viewToOverlayTranslation(size)
                    state.handleCropMove(translation: overlay)
                default:
                    let overlay = state.viewToOverlayTranslation(size)
                    state.handleDrag(handle: handle, translation: overlay)
                }

            case .ended, .cancelled, .failed:
                state.activeHandle = nil

            default:
                break
            }
        }

        // MARK: Pinch (anchor-based zoom)

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchStartScale = state.imageScale
                pinchStartOffset = state.imageOffset
                pinchStartLocation = imagePoint(from: gesture)

                // Find the overlay-space point under the pinch so we can
                // keep it visually fixed as scale changes.
                let cx = frameSize.width / 2
                let cy = frameSize.height / 2
                pinchAnchorOverlay = CGPoint(
                    x: cx + (pinchStartLocation.x - cx - pinchStartOffset.width) / pinchStartScale,
                    y: cy + (pinchStartLocation.y - cy - pinchStartOffset.height) / pinchStartScale
                )

            case .changed:
                let currentLoc = imagePoint(from: gesture)
                let rawScale = pinchStartScale * gesture.scale
                let maxScale = state.maxImageScale
                let newScale: CGFloat
                if rawScale > maxScale {
                    // Rubber-band past max: diminishing returns (30% of excess).
                    let excess = rawScale / maxScale - 1
                    newScale = maxScale * (1 + excess * 0.3)
                } else {
                    // Allow dipping below 1.0 for rubber-band feel, floor at 0.5.
                    newScale = max(rawScale, 0.5)
                }
                state.imageScale = newScale

                // Offset that keeps pinchAnchorOverlay at currentLoc.
                // Derivation: viewPos = center + (overlayPos - center) * S + O
                // We want currentLoc = center + (anchor - center) * S + O
                // ⟹ O = currentLoc - center - (anchor - center) * S
                let cx = frameSize.width / 2
                let cy = frameSize.height / 2
                let dx = pinchAnchorOverlay.x - cx
                let dy = pinchAnchorOverlay.y - cy
                var newOffset = CGSize(
                    width: currentLoc.x - cx - dx * newScale,
                    height: currentLoc.y - cy - dy * newScale
                )

                if newScale >= 1.0 {
                    newOffset = state.clampImageOffset(newOffset)
                }
                state.imageOffset = newOffset

            case .ended, .cancelled, .failed:
                let maxScale = state.maxImageScale
                if state.imageScale < 1.0 {
                    // Spring back from under-zoom (rubber-band discoverability).
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        state.imageScale = 1.0
                        state.imageOffset = .zero
                    }
                } else if state.imageScale < 1.12 {
                    // Small accidental zoom — snap back to 1x.
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        state.imageScale = 1.0
                        state.imageOffset = .zero
                    }
                } else if state.imageScale > maxScale {
                    // Over max — spring back with no bounce (damping = 1).
                    withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) {
                        state.imageScale = maxScale
                        state.imageOffset = state.clampImageOffset(state.imageOffset)
                    }
                } else {
                    state.imageOffset = state.clampImageOffset(state.imageOffset)
                }

            default:
                break
            }
        }
    }
}

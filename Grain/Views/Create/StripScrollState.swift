import os
import SwiftUI
import UIKit

private let stripSignposter = OSSignposter(subsystem: "social.grain.grain", category: "Animation.Strip")

// MARK: - Strip scroll state

/// Manages horizontal scroll position for the photo strip. Extracted from
/// PhotoStrip so the state persists across mode switches (owned by GalleryEditor).
///
/// `@Observable` so per-property mutations (e.g. dragTranslation every frame)
/// only invalidate views that read that specific property.
@Observable
@MainActor
final class StripScrollState {
    var baseOffset: CGFloat = 0
    var dragTranslation: CGFloat = 0

    var currentOffset: CGFloat {
        baseOffset + dragTranslation
    }

    static let thumbSize: CGFloat = 72
    static let spacing: CGFloat = 20

    // MARK: - Pure layout math

    /// Centered offset for cell at `idx` within container width `width`.
    static func offset(forIndex idx: Int, itemCount: Int, containerWidth width: CGFloat) -> CGFloat {
        guard itemCount > 0, width > 0 else { return 0 }
        let stride = thumbSize + spacing
        let halfCell = thumbSize / 2
        let unclamped = width / 2 - halfCell - CGFloat(idx) * stride
        return clamp(unclamped, itemCount: itemCount, containerWidth: width)
    }

    /// Clamp offset so HStack can't scroll past its own bounds.
    static func clamp(_ offset: CGFloat, itemCount: Int, containerWidth width: CGFloat) -> CGFloat {
        guard itemCount > 0, width > 0 else { return 0 }
        let contentWidth = CGFloat(itemCount) * thumbSize + CGFloat(max(0, itemCount - 1)) * spacing
        let minOffset = min(0, width - contentWidth)
        return max(minOffset, min(0, offset))
    }

    // MARK: - Actions

    func handleDragEnded(
        translation: CGFloat,
        predictedEnd: CGFloat,
        containerWidth width: CGFloat,
        itemCount: Int
    ) {
        let originalBase = baseOffset
        let committed = Self.clamp(originalBase + translation, itemCount: itemCount, containerWidth: width)
        baseOffset = committed
        dragTranslation = 0

        let projected = Self.clamp(originalBase + predictedEnd, itemCount: itemCount, containerWidth: width)
        let nearest = (0 ..< itemCount).min(by: {
            abs(Self.offset(forIndex: $0, itemCount: itemCount, containerWidth: width) - projected)
                < abs(Self.offset(forIndex: $1, itemCount: itemCount, containerWidth: width) - projected)
        }) ?? 0

        stripSignposter.emitEvent("StripDragEnded", "snap=\(nearest)")
        withAnimation(.snappy) {
            baseOffset = Self.offset(forIndex: nearest, itemCount: itemCount, containerWidth: width)
        }
    }

    func scrollToIndex(_ idx: Int, itemCount: Int, containerWidth: CGFloat, animated: Bool = true) {
        let target = Self.offset(forIndex: idx, itemCount: itemCount, containerWidth: containerWidth)
        guard abs(target - baseOffset) >= 0.5 else { return }
        if animated {
            withAnimation(.smooth) { baseOffset = target }
        } else {
            baseOffset = target
        }
    }

    /// X-button fade opacity based on cell's screen position relative to the
    /// container edges. Fades over one xRadius of margin so the button vanishes
    /// exactly as it reaches the clip boundary.
    func deleteOpacity(cellIndex idx: Int, containerWidth width: CGFloat) -> CGFloat {
        let cellLeft = currentOffset + CGFloat(idx) * (Self.thumbSize + Self.spacing)
        let offLeft = -cellLeft
        let offRight = (cellLeft + Self.thumbSize) - width
        let xCenterX = cellLeft + Self.thumbSize
        let xRadius: CGFloat = 11
        let xPadding: CGFloat = 2

        if offLeft > 0 {
            let dist = xCenterX
            return dist >= xRadius + xPadding ? 1 : max(0, (dist - xPadding) / xRadius)
        } else if offRight > 0 {
            let dist = width - cellLeft
            return dist >= xRadius + xPadding ? 1 : max(0, (dist - xPadding) / xRadius)
        }
        return 1
    }
}

// MARK: - UIKit-backed pan recognizer

/// Horizontal pan for strip scroll. UIKit-backed so the Form's vertical
/// scroll still works. `isEnabled` gates on mode so the recognizer is
/// inert when the layout is in grid or captions mode.
struct StripPanRecognizer: UIGestureRecognizerRepresentable {
    var isEnabled: Bool = true
    let onChanged: (CGFloat) -> Void
    let onEnded: (_ translation: CGFloat, _ predictedEnd: CGFloat) -> Void

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(isEnabled: isEnabled, onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let coordinator = context.coordinator
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .changed:
            coordinator.onChanged(translation)
        case .ended:
            let velocity = recognizer.velocity(in: recognizer.view).x
            coordinator.onEnded(translation, translation + velocity * 0.25)
        case .cancelled, .failed:
            coordinator.onEnded(translation, translation)
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled: Bool
        var onChanged: (CGFloat) -> Void
        var onEnded: (_ translation: CGFloat, _ predictedEnd: CGFloat) -> Void

        init(
            isEnabled: Bool,
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping (_ translation: CGFloat, _ predictedEnd: CGFloat) -> Void
        ) {
            self.isEnabled = isEnabled
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        nonisolated func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            MainActor.assumeIsolated {
                guard isEnabled else { return false }
                guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
                let velocity = pan.velocity(in: pan.view)
                return abs(velocity.x) > abs(velocity.y)
            }
        }

        nonisolated func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            // Prevent simultaneous H+V scrolling: once our horizontal pan begins,
            // the List's vertical scroll recognizer cannot also activate.
            // Vertical swipes never reach here — gestureRecognizerShouldBegin
            // returns false for them, so list scroll still works normally.
            false
        }
    }
}

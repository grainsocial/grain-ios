import SwiftUI

// MARK: - Active handle

/// Which handle (or region) the current drag gesture is operating on.
enum CropHandle: Equatable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight
    /// Drag inside the crop rect or while zoomed → pan image.
    case panImage
}

// MARK: - Aspect ratio presets

enum AspectRatioPreset: Equatable, Identifiable {
    case free
    case original
    case square
    case ratio4x3
    case ratio4x5
    case ratio16x9

    var id: String {
        label
    }

    var label: String {
        switch self {
        case .free: "Free"
        case .original: "Original"
        case .square: "1:1"
        case .ratio4x3: "4:3"
        case .ratio4x5: "4:5"
        case .ratio16x9: "16:9"
        }
    }

    /// Base width/height ratio (landscape). Flipped by the orientation toggle.
    var baseRatio: CGFloat? {
        switch self {
        case .free, .original: nil
        case .square: 1
        case .ratio4x3: 4.0 / 3.0
        case .ratio4x5: 4.0 / 5.0
        case .ratio16x9: 16.0 / 9.0
        }
    }

    static let allPresets: [AspectRatioPreset] = [
        .free, .original, .square, .ratio4x3, .ratio4x5, .ratio16x9,
    ]
}

// MARK: - Crop state

@Observable
@MainActor
final class CropState {
    /// Crop rect in VIEW SPACE (points, relative to the image display frame).
    var cropRect: CGRect = .zero

    // -- Image transform (view space) --
    var imageOffset: CGSize = .zero
    var imageScale: CGFloat = 1.0

    /// -- Gesture tracking --
    var activeHandle: CropHandle?
    var dragStartCropRect: CGRect = .zero
    var dragStartImageOffset: CGSize = .zero
    var pinchStartScale: CGFloat = 1.0

    // -- Aspect ratio --
    var selectedPreset: AspectRatioPreset = .free
    var isRatioLocked: Bool = false
    var lockedRatio: CGFloat?
    var isPortrait: Bool = false
    var originalImageRatio: CGFloat = 1.0

    /// -- Rotation --
    /// Cumulative clockwise rotation in degrees. Animated continuously
    /// (not clamped to 0–360) so SwiftUI always rotates the short way.
    var rotationAngle: Double = 0

    /// Discrete rotation for crop math (always 0, 90, 180, 270).
    var rotationDegrees: Int {
        let mod = Int(rotationAngle.truncatingRemainder(dividingBy: 360))
        return (mod + 360) % 360
    }

    /// -- Display --
    var showGrid: Bool = true

    /// -- Layout reference --
    var imageDisplayFrame: CGRect = .zero

    var effectiveLockedRatio: CGFloat? {
        if selectedPreset == .original {
            return originalImageRatio
        }
        if let base = selectedPreset.baseRatio {
            return isPortrait ? 1.0 / base : base
        }
        if isRatioLocked { return lockedRatio }
        return nil
    }

    // MARK: - Initialization

    func resetCrop() {
        cropRect = imageDisplayFrame
        imageOffset = .zero
        imageScale = 1.0
    }

    func resetAll() {
        rotationAngle = 0
        selectedPreset = .free
        isRatioLocked = false
        lockedRatio = nil
        isPortrait = false
        resetCrop()
    }

    // MARK: - Aspect ratio

    func selectPreset(_ preset: AspectRatioPreset) {
        selectedPreset = preset
        if let ratio = effectiveLockedRatio {
            lockedRatio = ratio
            applyCropRatio(ratio)
        } else if !isRatioLocked {
            lockedRatio = nil
            // Even free-form: validate current crop against image bounds
            cropRect = nearestValidCrop(cropRect)
        }
    }

    func toggleOrientation() {
        isPortrait.toggle()
        if let ratio = effectiveLockedRatio {
            lockedRatio = ratio
            applyCropRatio(ratio)
        }
    }

    func toggleRatioLock() {
        isRatioLocked.toggle()
        if isRatioLocked {
            let w = cropRect.width
            let h = cropRect.height
            guard h > 0 else { return }
            lockedRatio = w / h
        } else if selectedPreset == .free {
            lockedRatio = nil
        }
    }

    var showOrientationToggle: Bool {
        selectedPreset.baseRatio != nil && selectedPreset != .square
    }

    private func applyCropRatio(_ ratio: CGFloat) {
        let bounds = transformedImageBounds()
        let maxW = bounds.width
        let maxH = bounds.height
        guard maxW > 0, maxH > 0 else { return }

        var newW = maxW
        var newH = newW / ratio
        if newH > maxH {
            newH = maxH
            newW = newH * ratio
        }

        let x = bounds.origin.x + (maxW - newW) / 2
        let y = bounds.origin.y + (maxH - newH) / 2
        cropRect = clampCropToImage(CGRect(x: x, y: y, width: newW, height: newH))
    }

    // MARK: - Crop validation

    /// Whether the current crop rect is fully contained within the transformed image bounds.
    func isCropValid() -> Bool {
        let bounds = transformedImageBounds()
        return bounds.contains(cropRect)
    }

    /// Returns the nearest valid crop rect that fits within the transformed image bounds,
    /// optionally enforcing an aspect ratio. Preserves size when possible, shifts position
    /// to fit; shrinks only if necessary.
    func nearestValidCrop(_ rect: CGRect, ratio: CGFloat? = nil) -> CGRect {
        let bounds = transformedImageBounds()
        guard bounds.width > 0, bounds.height > 0 else { return rect }

        var r = rect

        // Apply ratio if requested
        if let ratio {
            let currentRatio = r.width / max(r.height, 1)
            if abs(currentRatio - ratio) > 0.001 {
                // Adjust height to match ratio, keeping width
                let newH = r.width / ratio
                if newH <= bounds.height {
                    r.size.height = newH
                } else {
                    r.size.height = bounds.height
                    r.size.width = bounds.height * ratio
                }
            }
        }

        // Shrink to fit within bounds if needed
        if r.width > bounds.width {
            r.size.width = bounds.width
            if let ratio { r.size.height = r.width / ratio }
        }
        if r.height > bounds.height {
            r.size.height = bounds.height
            if let ratio { r.size.width = r.height * ratio }
        }

        // Enforce minimum size
        r.size.width = max(r.width, minCropSize)
        r.size.height = max(r.height, minCropSize)

        // Shift position so rect is inside bounds
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }

        return r
    }

    // MARK: - Handle hit testing

    private let handleHitRadius: CGFloat = 30

    /// Hit-test a point to determine the gesture mode.
    ///
    /// Priority: corners → full edge lines → inside crop rect (pan) → nil.
    /// Dragging in the dim zone far from any edge does nothing (returns nil).
    func hitTest(point: CGPoint) -> CropHandle? {
        let r = cropRect

        // Corners (highest priority — overlap with edges)
        let corners: [(CropHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: r.minX, y: r.minY)),
            (.topRight, CGPoint(x: r.maxX, y: r.minY)),
            (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)),
        ]
        for (handle, pos) in corners {
            if distance(point, pos) < handleHitRadius { return handle }
        }

        // Full edge LINES (not just midpoints) — drag anywhere along an edge
        let hr = handleHitRadius
        if abs(point.y - r.minY) < hr, point.x >= r.minX - hr, point.x <= r.maxX + hr {
            return .top
        }
        if abs(point.y - r.maxY) < hr, point.x >= r.minX - hr, point.x <= r.maxX + hr {
            return .bottom
        }
        if abs(point.x - r.minX) < hr, point.y >= r.minY - hr, point.y <= r.maxY + hr {
            return .left
        }
        if abs(point.x - r.maxX) < hr, point.y >= r.minY - hr, point.y <= r.maxY + hr {
            return .right
        }

        // Inside crop rect → pan image
        if r.contains(point) { return .panImage }

        // Dim zone, far from edges → no gesture
        return nil
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: - Handle drag

    private let minCropSize: CGFloat = 60

    func handleDrag(handle: CropHandle, translation: CGSize) {
        // If user drags a handle while a preset is selected but lock is off,
        // switch to free-form so they can reshape freely.
        if !isRatioLocked, selectedPreset != .free {
            selectedPreset = .free
            lockedRatio = nil
        }

        var r = dragStartCropRect
        let dx = translation.width
        let dy = translation.height

        switch handle {
        case .topLeft:
            r.origin.x += dx
            r.origin.y += dy
            r.size.width -= dx
            r.size.height -= dy
        case .top:
            r.origin.y += dy
            r.size.height -= dy
        case .topRight:
            r.size.width += dx
            r.origin.y += dy
            r.size.height -= dy
        case .left:
            r.origin.x += dx
            r.size.width -= dx
        case .right:
            r.size.width += dx
        case .bottomLeft:
            r.origin.x += dx
            r.size.width -= dx
            r.size.height += dy
        case .bottom:
            r.size.height += dy
        case .bottomRight:
            r.size.width += dx
            r.size.height += dy
        case .panImage:
            return
        }

        if r.width < minCropSize {
            r.size.width = minCropSize
            if handle == .topLeft || handle == .left || handle == .bottomLeft {
                r.origin.x = dragStartCropRect.maxX - minCropSize
            }
        }
        if r.height < minCropSize {
            r.size.height = minCropSize
            if handle == .topLeft || handle == .top || handle == .topRight {
                r.origin.y = dragStartCropRect.maxY - minCropSize
            }
        }

        if let ratio = effectiveLockedRatio {
            r = applyAspectRatio(ratio, to: r, anchor: handle)
            cropRect = clampCropToImage(r, maintainRatio: ratio)
        } else {
            cropRect = clampCropToImage(r)
        }
    }

    private func applyAspectRatio(_ ratio: CGFloat, to rect: CGRect, anchor: CropHandle) -> CGRect {
        var r = rect
        let currentRatio = r.width / max(r.height, 1)

        if currentRatio > ratio {
            let newWidth = r.height * ratio
            switch anchor {
            case .topLeft, .left, .bottomLeft:
                r.origin.x = r.maxX - newWidth
            default:
                break
            }
            r.size.width = newWidth
        } else {
            let newHeight = r.width / ratio
            switch anchor {
            case .topLeft, .top, .topRight:
                r.origin.y = r.maxY - newHeight
            default:
                break
            }
            r.size.height = newHeight
        }

        return r
    }

    // MARK: - Image pan

    func handleImagePan(translation: CGSize) {
        let newOffset = CGSize(
            width: dragStartImageOffset.width + translation.width,
            height: dragStartImageOffset.height + translation.height
        )
        imageOffset = clampImageOffset(newOffset)
    }

    // MARK: - Clamping

    private func clampCropToImage(_ rect: CGRect, maintainRatio: CGFloat? = nil) -> CGRect {
        let imageBounds = transformedImageBounds()
        var r = rect

        if let ratio = maintainRatio {
            // When ratio-locked, shrink to fit rather than breaking the ratio.
            if r.width > imageBounds.width {
                r.size.width = imageBounds.width
                r.size.height = r.width / ratio
            }
            if r.height > imageBounds.height {
                r.size.height = imageBounds.height
                r.size.width = r.height * ratio
            }
            // Shift into bounds
            if r.minX < imageBounds.minX { r.origin.x = imageBounds.minX }
            if r.minY < imageBounds.minY { r.origin.y = imageBounds.minY }
            if r.maxX > imageBounds.maxX { r.origin.x = imageBounds.maxX - r.width }
            if r.maxY > imageBounds.maxY { r.origin.y = imageBounds.maxY - r.height }
        } else {
            if r.minX < imageBounds.minX { r.origin.x = imageBounds.minX }
            if r.minY < imageBounds.minY { r.origin.y = imageBounds.minY }
            if r.maxX > imageBounds.maxX { r.size.width = imageBounds.maxX - r.origin.x }
            if r.maxY > imageBounds.maxY { r.size.height = imageBounds.maxY - r.origin.y }
        }

        return r
    }

    /// Limit panning so the scaled image never shows empty space.
    /// At scale 1.0 offset is locked to zero; at 2× the image extends
    /// half-a-frame past each edge.
    func clampImageOffset(_ offset: CGSize) -> CGSize {
        let maxX = imageDisplayFrame.width * (imageScale - 1) / 2
        let maxY = imageDisplayFrame.height * (imageScale - 1) / 2
        return CGSize(
            width: max(-maxX, min(maxX, offset.width)),
            height: max(-maxY, min(maxY, offset.height))
        )
    }

    /// In overlay space the image always fills the display frame —
    /// zoom/pan are applied as view-level transforms outside the overlay.
    func transformedImageBounds() -> CGRect {
        imageDisplayFrame
    }

    // MARK: - Coordinate transform (view ↔ overlay)

    /// Convert a view-space point to overlay (image-local) space,
    /// undoing the scaleEffect + offset applied to the overlay container.
    func viewToOverlayPoint(_ point: CGPoint) -> CGPoint {
        let cx = imageDisplayFrame.width / 2
        let cy = imageDisplayFrame.height / 2
        return CGPoint(
            x: cx + (point.x - cx - imageOffset.width) / imageScale,
            y: cy + (point.y - cy - imageOffset.height) / imageScale
        )
    }

    /// Convert a view-space translation delta to overlay space.
    func viewToOverlayTranslation(_ translation: CGSize) -> CGSize {
        CGSize(
            width: translation.width / imageScale,
            height: translation.height / imageScale
        )
    }
}

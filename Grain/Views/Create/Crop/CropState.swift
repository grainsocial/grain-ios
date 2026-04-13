import SwiftUI

// MARK: - Active handle

/// Which handle (or region) the current drag gesture is operating on.
enum CropHandle: Equatable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight
    /// Drag inside the crop rect → reposition the mask.
    case moveCrop
    /// Move indicator above top edge — always moves crop, never promoted to panImage.
    case moveIndicator
    /// Pan the image (drag in masked/dim area, or 2-finger pan while zoomed).
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

    /// -- Baseline (incoming crop state, used for hasModifications / resetAll) --
    /// Normalized crop rect from the incoming CropResult (0…1 in post-rotation space).
    /// Full image = (0, 0, 1, 1).
    private(set) var baselineNormalizedCrop: CGRect = .init(x: 0, y: 0, width: 1, height: 1)
    /// Incoming rotation in degrees (0, 90, 180, 270).
    private(set) var baselineRotation: Double = 0

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

    /// Store the incoming crop state as baseline for hasModifications / resetAll.
    func setBaseline(rotation: Double, normalizedCrop: CGRect) {
        baselineRotation = rotation
        baselineNormalizedCrop = normalizedCrop
    }

    func resetCrop() {
        cropRect = imageDisplayFrame
        imageOffset = .zero
        imageScale = 1.0
    }

    /// Restores state to the incoming (baseline) crop, not the uncropped original.
    func resetAll() {
        selectedPreset = .free
        isRatioLocked = false
        lockedRatio = nil
        isPortrait = false
        imageOffset = .zero
        imageScale = 1.0
        rotationAngle = baselineRotation
        // Restore crop rect from baseline normalized coordinates.
        // imageDisplayFrame may change after rotation — caller must handle
        // the frame update via onGeometryChange if rotation changed.
        let frame = imageDisplayFrame
        cropRect = CGRect(
            x: frame.origin.x + baselineNormalizedCrop.origin.x * frame.width,
            y: frame.origin.y + baselineNormalizedCrop.origin.y * frame.height,
            width: baselineNormalizedCrop.width * frame.width,
            height: baselineNormalizedCrop.height * frame.height
        )
    }

    /// Resets only zoom and pan, preserving crop rect and rotation.
    func resetView() {
        imageOffset = .zero
        imageScale = 1.0
    }

    /// True when image is zoomed or panned from default state.
    var isViewModified: Bool {
        imageScale != 1.0 || imageOffset != .zero
    }

    /// Current crop as a normalized rect (0…1) in the image display frame.
    var normalizedCropRect: CGRect {
        let frame = imageDisplayFrame
        guard frame.width > 0, frame.height > 0 else { return .zero }
        return CGRect(
            x: (cropRect.minX - frame.minX) / frame.width,
            y: (cropRect.minY - frame.minY) / frame.height,
            width: cropRect.width / frame.width,
            height: cropRect.height / frame.height
        )
    }

    /// True when any crop, rotation, or zoom change has been made
    /// relative to the incoming (baseline) state.
    var hasModifications: Bool {
        // Rotation changed?
        let rotDiff = (rotationAngle - baselineRotation).truncatingRemainder(dividingBy: 360)
        if abs(rotDiff) > 0.1 { return true }

        // Zoom/pan?
        if isViewModified { return true }

        // Crop rect changed? Compare normalized to avoid frame-size dependency.
        let norm = normalizedCropRect
        let base = baselineNormalizedCrop
        if abs(norm.minX - base.minX) > 0.005
            || abs(norm.minY - base.minY) > 0.005
            || abs(norm.width - base.width) > 0.005
            || abs(norm.height - base.height) > 0.005
        { return true }

        return false
    }

    /// Zoom and pan so the current crop rect fills the frame, centered.
    func zoomToCrop() {
        let frame = imageDisplayFrame
        let padding: CGFloat = 8
        let targetW = frame.width - padding * 2
        let targetH = frame.height - padding * 2
        guard targetW > 0, targetH > 0,
              cropRect.width > 0, cropRect.height > 0 else { return }

        let scaleX = targetW / cropRect.width
        let scaleY = targetH / cropRect.height
        let newScale = max(1.0, min(scaleX, scaleY))

        let cx = frame.width / 2
        let cy = frame.height / 2

        imageScale = newScale
        // Center the crop area on screen — allow offset beyond normal
        // clamping range so the crop is truly centered even near edges.
        let idealOffset = CGSize(
            width: (cx - cropRect.midX) * newScale,
            height: (cy - cropRect.midY) * newScale
        )
        // Only clamp enough to keep the IMAGE visible (not the crop).
        let maxX = frame.width * (newScale - 1) / 2
        let maxY = frame.height * (newScale - 1) / 2
        imageOffset = CGSize(
            width: max(-maxX, min(maxX, idealOffset.width)),
            height: max(-maxY, min(maxY, idealOffset.height))
        )
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
        guard bounds.width > 0, bounds.height > 0 else { return }

        // Preserve the current crop's area: solve for new dimensions
        // that match the target ratio while keeping area ≈ constant.
        let area = cropRect.width * cropRect.height
        var newW = sqrt(area * ratio)
        var newH = sqrt(area / ratio)

        // Clamp to image bounds
        if newW > bounds.width {
            newW = bounds.width
            newH = newW / ratio
        }
        if newH > bounds.height {
            newH = bounds.height
            newW = newH * ratio
        }

        // Enforce minimum
        newW = max(newW, minCropSize)
        newH = max(newH, minCropSize)

        // Center on the current crop's center, clamped to bounds
        let cx = cropRect.midX
        let cy = cropRect.midY
        let x = max(bounds.minX, min(bounds.maxX - newW, cx - newW / 2))
        let y = max(bounds.minY, min(bounds.maxY - newH, cy - newH / 2))
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

    /// Hit radius proportional to the screen-space crop rect, so touch targets
    /// scale with handle visuals. Converted to overlay space for hit testing.
    private var scaledHitRadius: CGFloat {
        let screenShort = min(screenCropRect.width, screenCropRect.height)
        let screenRadius = max(22, min(screenShort * 0.08, 40))
        return screenRadius / imageScale
    }

    /// Hit-test a point to determine the gesture mode.
    ///
    /// Priority: corners → edges (bottom/left/right) → inside crop (move) → outside (pan).
    /// Top edge is handled by the move indicator (screen-space check in coordinator).
    /// Always returns a handle — every touch point has a purpose.
    func hitTest(point: CGPoint) -> CropHandle {
        let r = cropRect
        let hr = scaledHitRadius
        let bounds = transformedImageBounds()

        // Corners (highest priority). Use 1.5× radius so corners always
        // win over adjacent edge zones — prevents single-axis lock near corners.
        let cornerHR = hr * 1.5
        let corners: [(CropHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: r.minX, y: r.minY)),
            (.topRight, CGPoint(x: r.maxX, y: r.minY)),
            (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)),
        ]
        for (handle, pos) in corners {
            if distance(point, pos) < cornerHR { return handle }
        }

        // Edge midpoint bars only — hit zone covers the visible bar, not
        // the entire edge. Hidden when crop rect is too small (matches
        // CropHandlesView threshold: 3× bar length + padding).
        let scr = screenCropRect
        let screenShort = min(scr.width, scr.height)
        let screenBarLen = min(max(screenShort * 0.12, 28), 44)
        let edgeMinSize = screenBarLen * 3 + screenBarLen
        let barHalf = (screenBarLen / imageScale) / 2 + hr
        // No top edge — move indicator handles that zone.
        let bottomInward: CGFloat = (bounds.maxY - r.maxY) < hr ? hr * 1.6 : hr
        let leftInward: CGFloat = (r.minX - bounds.minX) < hr ? hr * 1.6 : hr
        let rightInward: CGFloat = (bounds.maxX - r.maxX) < hr ? hr * 1.6 : hr

        // Bottom bar — only if crop is wide enough
        if scr.width >= edgeMinSize,
           point.y >= r.maxY - bottomInward, point.y <= r.maxY + hr,
           point.x >= r.midX - barHalf, point.x <= r.midX + barHalf
        {
            return .bottom
        }
        // Left bar — only if crop is tall enough
        if scr.height >= edgeMinSize,
           point.x >= r.minX - hr, point.x <= r.minX + leftInward,
           point.y >= r.midY - barHalf, point.y <= r.midY + barHalf
        {
            return .left
        }
        // Right bar — only if crop is tall enough
        if scr.height >= edgeMinSize,
           point.x >= r.maxX - rightInward, point.x <= r.maxX + hr,
           point.y >= r.midY - barHalf, point.y <= r.midY + barHalf
        {
            return .right
        }

        // Inside crop rect → move the crop mask
        if r.contains(point) { return .moveCrop }

        // Masked/dim zone → pan image
        return .panImage
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: - Handle drag

    /// Minimum crop dimension in overlay points (~132px at 3x).
    private let minCropSize: CGFloat = 44

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
        case .moveCrop, .moveIndicator, .panImage:
            return
        }

        // CGRect.width/.height return absolute values, so negative sizes
        // wouldn't trigger a `< minCropSize` check. Use size.width/height
        // directly to catch negative (inverted) dimensions.
        if r.size.width < minCropSize {
            r.size.width = minCropSize
            if handle == .topLeft || handle == .left || handle == .bottomLeft {
                r.origin.x = dragStartCropRect.maxX - minCropSize
            }
        }
        if r.size.height < minCropSize {
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

        // For single-axis edges, the user changed ONE dimension — adjust the
        // OTHER to maintain ratio. Without this, the unchanged axis forces
        // the changed axis back to its original value, canceling the drag.
        switch anchor {
        case .top, .bottom:
            // Height was dragged → adjust width
            let newWidth = r.height * ratio
            let cx = r.midX
            r.origin.x = cx - newWidth / 2
            r.size.width = newWidth
            return r
        case .left, .right:
            // Width was dragged → adjust height
            let newHeight = r.width / ratio
            let cy = r.midY
            r.origin.y = cy - newHeight / 2
            r.size.height = newHeight
            return r
        default:
            break
        }

        // Corners: both axes changed. Snap whichever is further from ratio.
        let currentRatio = r.width / max(r.height, 1)
        if currentRatio > ratio {
            let newWidth = r.height * ratio
            switch anchor {
            case .topLeft, .bottomLeft:
                r.origin.x = r.maxX - newWidth
            default:
                break
            }
            r.size.width = newWidth
        } else {
            let newHeight = r.width / ratio
            switch anchor {
            case .topLeft, .topRight:
                r.origin.y = r.maxY - newHeight
            default:
                break
            }
            r.size.height = newHeight
        }

        return r
    }

    // MARK: - Crop move

    func handleCropMove(translation: CGSize) {
        let bounds = transformedImageBounds()
        var r = dragStartCropRect.offsetBy(dx: translation.width, dy: translation.height)
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        cropRect = r
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

    /// Convert an overlay-space point to view/screen space,
    /// applying the scaleEffect + offset transforms.
    func overlayToScreenPoint(_ point: CGPoint) -> CGPoint {
        let cx = imageDisplayFrame.width / 2
        let cy = imageDisplayFrame.height / 2
        return CGPoint(
            x: cx + (point.x - cx) * imageScale + imageOffset.width,
            y: cy + (point.y - cy) * imageScale + imageOffset.height
        )
    }

    /// The crop rect projected into view/screen space.
    var screenCropRect: CGRect {
        let tl = overlayToScreenPoint(CGPoint(x: cropRect.minX, y: cropRect.minY))
        let br = overlayToScreenPoint(CGPoint(x: cropRect.maxX, y: cropRect.maxY))
        return CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
    }

    /// Screen-space hit rect for the move indicator.
    /// Mirrors the clamping in CropHandlesView.moveIndicatorCY so the hit
    /// zone stays on top of the pill visual regardless of crop position.
    var moveIndicatorScreenRect: CGRect {
        let topCenter = overlayToScreenPoint(CGPoint(x: cropRect.midX, y: cropRect.minY))
        let rawCY = topCenter.y - 14
        let minCY: CGFloat = 11 + 4 // pillHeight/2 + 4 margin (matches CropHandlesView)
        let cy = max(rawCY, minCY)
        return CGRect(x: topCenter.x - 40, y: cy - 22, width: 80, height: 44)
    }
}

import SwiftUI

// MARK: - Active handle

/// Which handle (or region) the current drag gesture is operating on.
enum CropHandle: Equatable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight
    /// Drag started inside the crop rect but not near any handle → pan image.
    case panImage
}

// MARK: - Aspect ratio presets

enum AspectRatioPreset: String, CaseIterable, Identifiable {
    case free = "Free"
    case square = "1:1"
    case fourFive = "4:5"
    case threeFour = "3:4"
    case sixteenNine = "16:9"
    case nineSixteen = "9:16"

    var id: String {
        rawValue
    }

    /// Returns width/height ratio, or nil for free-form.
    var ratio: CGFloat? {
        switch self {
        case .free: nil
        case .square: 1
        case .fourFive: 4.0 / 5.0
        case .threeFour: 3.0 / 4.0
        case .sixteenNine: 16.0 / 9.0
        case .nineSixteen: 9.0 / 16.0
        }
    }
}

// MARK: - Crop state

@Observable
@MainActor
final class CropState {
    /// -- Crop rect in VIEW SPACE (points, relative to the image display frame) --
    var cropRect: CGRect = .zero

    // -- Image transform (view space) --
    var imageOffset: CGSize = .zero
    var imageScale: CGFloat = 1.0

    /// -- Gesture tracking --
    var activeHandle: CropHandle?
    /// Snapshot of cropRect when a handle drag begins.
    var dragStartCropRect: CGRect = .zero
    /// Snapshot of imageOffset when an image pan begins.
    var dragStartImageOffset: CGSize = .zero
    /// Snapshot of imageScale when a pinch begins.
    var pinchStartScale: CGFloat = 1.0

    // -- Aspect ratio --
    var selectedPreset: AspectRatioPreset = .free
    var isRatioLocked: Bool = false
    /// The locked ratio (w/h). Set from preset or from current crop rect dimensions.
    var lockedRatio: CGFloat?

    /// -- Rotation --
    /// Cumulative clockwise rotation in degrees: 0, 90, 180, 270.
    var rotation: Int = 0

    /// -- Layout reference --
    /// The frame the image occupies on screen (set by geometry reader).
    var imageDisplayFrame: CGRect = .zero

    /// Effective locked ratio: from preset if not free, else from manual lock.
    var effectiveLockedRatio: CGFloat? {
        if let preset = selectedPreset.ratio { return preset }
        if isRatioLocked { return lockedRatio }
        return nil
    }

    // MARK: - Initialization

    /// Reset crop rect to cover the full image display frame.
    func resetCrop() {
        cropRect = imageDisplayFrame
        imageOffset = .zero
        imageScale = 1.0
    }

    /// Reset everything including rotation.
    func resetAll() {
        rotation = 0
        selectedPreset = .free
        isRatioLocked = false
        lockedRatio = nil
        resetCrop()
    }

    // MARK: - Aspect ratio

    func selectPreset(_ preset: AspectRatioPreset) {
        selectedPreset = preset
        if let ratio = preset.ratio {
            lockedRatio = ratio
            applyCropRatio(ratio)
        } else if !isRatioLocked {
            lockedRatio = nil
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

    /// Snap crop rect to a given w/h ratio, centered, max size that fits.
    private func applyCropRatio(_ ratio: CGFloat) {
        let maxW = imageDisplayFrame.width
        let maxH = imageDisplayFrame.height
        guard maxW > 0, maxH > 0 else { return }

        var newW = maxW
        var newH = newW / ratio
        if newH > maxH {
            newH = maxH
            newW = newH * ratio
        }

        let x = imageDisplayFrame.origin.x + (maxW - newW) / 2
        let y = imageDisplayFrame.origin.y + (maxH - newH) / 2
        cropRect = CGRect(x: x, y: y, width: newW, height: newH)

        imageOffset = .zero
        imageScale = 1.0
    }

    // MARK: - Handle hit testing

    private let handleHitRadius: CGFloat = 30

    /// Determine which handle (if any) a gesture start point is near.
    func hitTest(point: CGPoint) -> CropHandle? {
        let r = cropRect

        // Corners first (they overlap with edge zones)
        let corners: [(CropHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: r.minX, y: r.minY)),
            (.topRight, CGPoint(x: r.maxX, y: r.minY)),
            (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)),
        ]
        for (handle, pos) in corners {
            if distance(point, pos) < handleHitRadius { return handle }
        }

        // Edge midpoints
        let edges: [(CropHandle, CGPoint)] = [
            (.top, CGPoint(x: r.midX, y: r.minY)),
            (.bottom, CGPoint(x: r.midX, y: r.maxY)),
            (.left, CGPoint(x: r.minX, y: r.midY)),
            (.right, CGPoint(x: r.maxX, y: r.midY)),
        ]
        for (handle, pos) in edges {
            if distance(point, pos) < handleHitRadius { return handle }
        }

        // Inside crop rect → pan image
        if r.contains(point) { return .panImage }

        return nil
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: - Handle drag

    private let minCropSize: CGFloat = 60

    /// Update crop rect based on a handle drag translation.
    func handleDrag(handle: CropHandle, translation: CGSize) {
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

        // Enforce minimum size
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

        // Enforce aspect ratio lock
        if let ratio = effectiveLockedRatio {
            r = applyAspectRatio(ratio, to: r, anchor: handle)
        }

        cropRect = clampCropToImage(r)
    }

    /// Adjust rect to match the target aspect ratio, anchoring to the opposite edge.
    private func applyAspectRatio(_ ratio: CGFloat, to rect: CGRect, anchor: CropHandle) -> CGRect {
        var r = rect
        let currentRatio = r.width / max(r.height, 1)

        if currentRatio > ratio {
            // Too wide — shrink width
            let newWidth = r.height * ratio
            switch anchor {
            case .topLeft, .left, .bottomLeft:
                r.origin.x = r.maxX - newWidth
            default:
                break
            }
            r.size.width = newWidth
        } else {
            // Too tall — shrink height
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

    /// Clamp crop rect so it stays within the transformed image bounds.
    private func clampCropToImage(_ rect: CGRect) -> CGRect {
        let imageBounds = transformedImageBounds()
        var r = rect

        if r.minX < imageBounds.minX { r.origin.x = imageBounds.minX }
        if r.minY < imageBounds.minY { r.origin.y = imageBounds.minY }
        if r.maxX > imageBounds.maxX { r.size.width = imageBounds.maxX - r.origin.x }
        if r.maxY > imageBounds.maxY { r.size.height = imageBounds.maxY - r.origin.y }

        return r
    }

    /// Clamp image offset so the image always covers the entire crop rect.
    func clampImageOffset(_ offset: CGSize) -> CGSize {
        let scaledW = imageDisplayFrame.width * imageScale
        let scaledH = imageDisplayFrame.height * imageScale

        let centerX = imageDisplayFrame.midX + offset.width
        let centerY = imageDisplayFrame.midY + offset.height

        let imgMinX = centerX - scaledW / 2
        let imgMaxX = centerX + scaledW / 2
        let imgMinY = centerY - scaledH / 2
        let imgMaxY = centerY + scaledH / 2

        var clamped = offset

        if imgMinX > cropRect.minX {
            clamped.width -= (imgMinX - cropRect.minX)
        }
        if imgMaxX < cropRect.maxX {
            clamped.width += (cropRect.maxX - imgMaxX)
        }
        if imgMinY > cropRect.minY {
            clamped.height -= (imgMinY - cropRect.minY)
        }
        if imgMaxY < cropRect.maxY {
            clamped.height += (cropRect.maxY - imgMaxY)
        }

        return clamped
    }

    /// The image bounds in view space after scale and offset are applied.
    func transformedImageBounds() -> CGRect {
        let scaledW = imageDisplayFrame.width * imageScale
        let scaledH = imageDisplayFrame.height * imageScale
        let centerX = imageDisplayFrame.midX + imageOffset.width
        let centerY = imageDisplayFrame.midY + imageOffset.height
        return CGRect(
            x: centerX - scaledW / 2,
            y: centerY - scaledH / 2,
            width: scaledW,
            height: scaledH
        )
    }
}

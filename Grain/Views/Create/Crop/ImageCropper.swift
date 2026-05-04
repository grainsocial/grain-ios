import os
import UIKit

private let cropSignposter = OSSignposter(subsystem: "social.grain.grain", category: "ImageCropper")

/// Pure utility — no views, no state. Handles coordinate space conversions
/// and the actual pixel-level crop/rotate operations.
enum ImageCropper {
    /// Normalize a UIImage so its pixel data matches its visual orientation.
    /// After this, `imageOrientation` is `.up` and CGImage operations work
    /// in visual coordinates.
    static func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let spid = cropSignposter.makeSignpostID()
        let state = cropSignposter.beginInterval("normalizeOrientation", id: spid, "\(Int(image.size.width))x\(Int(image.size.height))")
        defer { cropSignposter.endInterval("normalizeOrientation", state) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(at: .zero)
        }
    }

    /// Rotate a UIImage by 90° increments (clockwise).
    /// `degrees` must be 0, 90, 180, or 270.
    static func rotate(_ image: UIImage, degrees: Int) -> UIImage {
        guard degrees != 0 else { return image }
        let spid = cropSignposter.makeSignpostID()
        let state = cropSignposter.beginInterval("rotate", id: spid, "\(degrees)° \(Int(image.size.width))x\(Int(image.size.height))")
        defer { cropSignposter.endInterval("rotate", state) }
        let radians = CGFloat(degrees) * .pi / 180

        let swapDimensions = degrees == 90 || degrees == 270
        let newSize = swapDimensions
            ? CGSize(width: image.size.height, height: image.size.width)
            : image.size

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            ctx.cgContext.rotate(by: radians)
            image.draw(at: CGPoint(x: -image.size.width / 2, y: -image.size.height / 2))
        }
    }

    /// Apply a crop to the original image.
    ///
    /// **Order of operations:** normalize orientation → rotate → crop.
    ///
    /// - Parameters:
    ///   - image: The original, unmodified image.
    ///   - normalizedRect: Crop rect in 0…1 coordinates, relative to the
    ///     POST-ROTATION image.
    ///   - rotation: Clockwise degrees (0, 90, 180, 270) applied BEFORE cropping.
    static func applyCrop(to image: UIImage, normalizedRect: CGRect, rotation: Int) -> UIImage {
        let spid = cropSignposter.makeSignpostID()
        let state = cropSignposter.beginInterval("applyCrop", id: spid, "\(Int(image.size.width))x\(Int(image.size.height)) rot=\(rotation)")
        defer { cropSignposter.endInterval("applyCrop", state) }

        let normalized = normalizeOrientation(image)
        let rotated = rotate(normalized, degrees: rotation)

        let pixelRect = normalizedRectToPixels(normalizedRect, imageSize: rotated.size)

        guard let cgImage = rotated.cgImage,
              let cropped = cgImage.cropping(to: pixelRect)
        else {
            return rotated
        }

        return UIImage(cgImage: cropped, scale: rotated.scale, orientation: .up)
    }

    // MARK: - Coordinate conversions

    /// Convert a view-space crop rect to normalized 0…1 coordinates
    /// relative to the image content.
    ///
    /// Accounts for image pan offset and zoom scale so the normalized rect
    /// describes the visible region of the actual image, not the screen layout.
    static func viewRectToNormalized(
        _ viewRect: CGRect,
        imageDisplayFrame: CGRect,
        imageOffset: CGSize,
        imageScale: CGFloat
    ) -> CGRect {
        // Image bounds in view-space after transform
        let scaledW = imageDisplayFrame.width * imageScale
        let scaledH = imageDisplayFrame.height * imageScale
        let imgOriginX = imageDisplayFrame.midX + imageOffset.width - scaledW / 2
        let imgOriginY = imageDisplayFrame.midY + imageOffset.height - scaledH / 2

        // Crop rect → image-relative 0…1
        let relX = (viewRect.origin.x - imgOriginX) / scaledW
        let relY = (viewRect.origin.y - imgOriginY) / scaledH
        let relW = viewRect.width / scaledW
        let relH = viewRect.height / scaledH

        return CGRect(x: relX, y: relY, width: relW, height: relH)
    }

    /// Convert a normalized 0…1 rect to pixel coordinates for `CGImage.cropping(to:)`.
    static func normalizedRectToPixels(_ normalized: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: normalized.origin.x * imageSize.width,
            y: normalized.origin.y * imageSize.height,
            width: normalized.width * imageSize.width,
            height: normalized.height * imageSize.height
        )
    }
}

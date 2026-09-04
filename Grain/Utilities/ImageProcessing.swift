import ImageIO
import UIKit

enum ImageProcessing {
    /// Resize `image` to fit within `maxDimension` and compress it to at most
    /// `maxBytes`, returning the JPEG and the pixel size it was encoded at.
    ///
    /// Quality is given up before resolution, since softening is less visible
    /// than shrinking. When even the lowest quality at a given size is still
    /// too big, the image is scaled down and the search runs again — and again,
    /// because one pass is not enough for a photograph JPEG struggles with.
    ///
    /// Staying under the ceiling matters: the PDS rejects an oversized blob
    /// only after the upload has already been paid for, so an image that goes
    /// over costs the user the whole transfer and then fails the post.
    static func resizeImage(_ image: UIImage, maxDimension: CGFloat, maxBytes: Int) -> (Data, CGSize) {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let scaleFactor = min(maxDimension / pixelWidth, maxDimension / pixelHeight, 1)
        var size = CGSize(width: round(pixelWidth * scaleFactor), height: round(pixelHeight * scaleFactor))

        var best = Data()
        var bestSize = size

        while true {
            let scaled = redraw(image, at: size)
            let attempt = compress(scaled, maxBytes: maxBytes)
            best = attempt.data
            bestSize = size

            if attempt.fitsCeiling {
                break
            }

            // Halve the pixel count and try again. The floor is there so a
            // ceiling nothing could meet ends in a small image rather than an
            // endless loop.
            let next = CGSize(
                width: round(size.width * Self.downscaleStep),
                height: round(size.height * Self.downscaleStep)
            )
            guard min(next.width, next.height) >= Self.minDimension else { break }
            size = next
        }

        return (best, bestSize)
    }

    /// Scales the pixel count by half each pass.
    private static let downscaleStep: CGFloat = 0.7071

    /// Below this a photo is too small to be worth posting, so an unreachable
    /// ceiling stops here rather than degrading to a thumbnail.
    private static let minDimension: CGFloat = 240

    /// JPEG's own floor — below this the artefacts cost more than the bytes save.
    private static let minQuality: CGFloat = 0.01

    private static func redraw(_ image: UIImage, at size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// The highest-quality encoding of `image` that fits in `maxBytes`.
    ///
    /// `fitsCeiling` is false when even `minQuality` is too big, in which case
    /// the data returned is the smallest this size can produce — the caller's
    /// cue to scale down rather than to ship it.
    private static func compress(_ image: UIImage, maxBytes: Int) -> (data: Data, fitsCeiling: Bool) {
        let smallest = image.jpegData(compressionQuality: minQuality) ?? Data()
        guard smallest.count <= maxBytes else { return (smallest, false) }

        var best = smallest
        var low = minQuality
        var high: CGFloat = 1

        for _ in 0 ..< 10 {
            let mid = (low + high) / 2
            guard let data = image.jpegData(compressionQuality: mid) else { break }
            if data.count <= maxBytes {
                best = data
                low = mid
            } else {
                high = mid
            }
        }

        return (best, true)
    }

    /// Extract GPS coordinates from image data. Returns (latitude, longitude) or nil.
    static func extractGPS(from data: Data) -> (latitude: Double, longitude: Double)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let gpsDict = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        else {
            return nil
        }

        guard let latitude = gpsDict[kCGImagePropertyGPSLatitude as String] as? Double,
              let latRef = gpsDict[kCGImagePropertyGPSLatitudeRef as String] as? String,
              let longitude = gpsDict[kCGImagePropertyGPSLongitude as String] as? Double,
              let lonRef = gpsDict[kCGImagePropertyGPSLongitudeRef as String] as? String
        else {
            return nil
        }

        let lat = latRef == "S" ? -latitude : latitude
        let lon = lonRef == "W" ? -longitude : longitude
        return (lat, lon)
    }
}

import ImageIO
import OSLog
import UIKit

private let imageProcessingSignposter = OSSignposter(subsystem: "social.grain.grain", category: "ImageProcessing")

enum ImageProcessing {
    /// Resize image to fit within maxDimension and binary-search JPEG quality to stay under maxBytes.
    /// Always runs the rasterize + encode work on a detached userInitiated task — safe to call from
    /// any context (MainActor or not) without blocking the caller's thread.
    static func resizeImage(_ image: UIImage, maxDimension: CGFloat, maxBytes: Int) async -> (Data, CGSize) {
        await Task.detached(priority: .userInitiated) {
            resizeImageSync(image, maxDimension: maxDimension, maxBytes: maxBytes)
        }.value
    }

    private static func resizeImageSync(_ image: UIImage, maxDimension: CGFloat, maxBytes: Int) -> (Data, CGSize) {
        let signpostID = imageProcessingSignposter.makeSignpostID()
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let resizeState = imageProcessingSignposter.beginInterval(
            "ResizeImage",
            id: signpostID,
            "in=\(Int(pixelWidth))x\(Int(pixelHeight)) maxDim=\(Int(maxDimension)) maxBytes=\(maxBytes)"
        )

        let scaleFactor = min(maxDimension / pixelWidth, maxDimension / pixelHeight, 1)
        var newSize = CGSize(width: round(pixelWidth * scaleFactor), height: round(pixelHeight * scaleFactor))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let rasterizeState = imageProcessingSignposter.beginInterval(
            "Rasterize",
            id: signpostID,
            "out=\(Int(newSize.width))x\(Int(newSize.height))"
        )
        var scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        imageProcessingSignposter.endInterval("Rasterize", rasterizeState)

        let searchState = imageProcessingSignposter.beginInterval("JPEGBinarySearch", id: signpostID)
        var best = scaled.jpegData(compressionQuality: 0.01) ?? Data()
        var lo: CGFloat = 0
        var hi: CGFloat = 1
        var iterations = 0
        let goodEnoughBytes = Int(Double(maxBytes) * 0.95)

        for _ in 0 ..< 10 {
            iterations += 1
            let mid = (lo + hi) / 2
            let encodeState = imageProcessingSignposter.beginInterval("JPEGEncode", id: signpostID, "q=\(mid)")
            guard let data = scaled.jpegData(compressionQuality: mid) else {
                imageProcessingSignposter.endInterval("JPEGEncode", encodeState, "result=nil")
                break
            }
            imageProcessingSignposter.endInterval("JPEGEncode", encodeState, "bytes=\(data.count)")
            if data.count <= maxBytes {
                best = data
                if data.count >= goodEnoughBytes { break }
                lo = mid
            } else {
                hi = mid
            }
        }
        imageProcessingSignposter.endInterval("JPEGBinarySearch", searchState, "iters=\(iterations) bestBytes=\(best.count)")

        if best.count > maxBytes {
            let fallbackState = imageProcessingSignposter.beginInterval("FallbackDownscale", id: signpostID)
            let downScale = sqrt(Double(maxBytes) / Double(best.count))
            newSize = CGSize(width: round(newSize.width * downScale), height: round(newSize.height * downScale))
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            renderer = UIGraphicsImageRenderer(size: newSize, format: fmt)
            scaled = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            best = scaled.jpegData(compressionQuality: 0.8) ?? Data()
            imageProcessingSignposter.endInterval(
                "FallbackDownscale",
                fallbackState,
                "out=\(Int(newSize.width))x\(Int(newSize.height)) bytes=\(best.count)"
            )
        }

        imageProcessingSignposter.endInterval(
            "ResizeImage",
            resizeState,
            "out=\(Int(newSize.width))x\(Int(newSize.height)) bytes=\(best.count)"
        )
        return (best, newSize)
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

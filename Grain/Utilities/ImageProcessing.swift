import ImageIO
import UIKit

enum ImageProcessing {
    /// Resize image to fit within maxDimension and binary-search JPEG quality to stay under maxBytes.
    static func resizeImage(_ image: UIImage, maxDimension: CGFloat, maxBytes: Int) -> (Data, CGSize) {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let scaleFactor = min(maxDimension / pixelWidth, maxDimension / pixelHeight, 1)
        var newSize = CGSize(width: round(pixelWidth * scaleFactor), height: round(pixelHeight * scaleFactor))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        var scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        var best = scaled.jpegData(compressionQuality: 0.01) ?? Data()
        var lo: CGFloat = 0
        var hi: CGFloat = 1

        for _ in 0 ..< 10 {
            let mid = (lo + hi) / 2
            guard let data = scaled.jpegData(compressionQuality: mid) else { break }
            if data.count <= maxBytes {
                best = data
                lo = mid
            } else {
                hi = mid
            }
        }

        if best.count > maxBytes {
            let downScale = sqrt(Double(maxBytes) / Double(best.count))
            newSize = CGSize(width: round(newSize.width * downScale), height: round(newSize.height * downScale))
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            renderer = UIGraphicsImageRenderer(size: newSize, format: fmt)
            scaled = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            best = scaled.jpegData(compressionQuality: 0.8) ?? Data()
        }

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

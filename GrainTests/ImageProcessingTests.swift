@testable import Grain
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest

/// Everything a photo goes through between the picker and the PDS. The resize
/// is the app's only real CPU work outside layout, and its byte ceiling is a
/// hard requirement — a blob over the limit is rejected by the server after the
/// upload has already been paid for.
@MainActor
final class ImageProcessingTests: GrainTestCase {
    // MARK: - Fixtures

    /// High-frequency detail, so JPEG can't compress it down to nothing and the
    /// byte ceiling is actually exercised. Derived from the coordinates rather
    /// than a random source, so a failure here reproduces.
    private func noisyImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let step = 4
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            for y in stride(from: 0, to: height, by: step) {
                for x in stride(from: 0, to: width, by: step) {
                    context.cgContext.setFillColor(
                        red: CGFloat((x &* 7 &+ y &* 13) % 256) / 255,
                        green: CGFloat((x &* 31 &+ y &* 3) % 256) / 255,
                        blue: CGFloat((x &* 17 &+ y &* 29) % 256) / 255,
                        alpha: 1
                    )
                    context.cgContext.fill(CGRect(x: x, y: y, width: step, height: step))
                }
            }
        }
    }

    /// A smooth gradient — compressible the way a real photograph is, so the
    /// quality search can actually reach a byte ceiling.
    private func gradientImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let colours = [
                UIColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1).cgColor,
                UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1).cgColor,
            ]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray, locations: nil
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: width, y: height), options: []
            )
        }
    }

    private func flatImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            context.cgContext.setFillColor(red: 0.2, green: 0.6, blue: 0.7, alpha: 1)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    // MARK: - resizeImage

    func testAnImageAlreadyUnderTheLimitIsNotEnlarged() {
        let (data, size) = ImageProcessing.resizeImage(
            flatImage(width: 800, height: 600), maxDimension: 2000, maxBytes: 900_000
        )

        XCTAssertEqual(size, CGSize(width: 800, height: 600))
        XCTAssertFalse(data.isEmpty)
    }

    func testAnOversizedImageIsScaledToFitTheLongEdge() {
        let (_, size) = ImageProcessing.resizeImage(
            flatImage(width: 4000, height: 3000), maxDimension: 2000, maxBytes: 900_000
        )

        XCTAssertEqual(max(size.width, size.height), 2000, accuracy: 1)
        XCTAssertEqual(size.width / size.height, 4.0 / 3.0, accuracy: 0.01, "Resizing must not distort the photo")
    }

    func testAPortraitImageIsScaledOnItsLongEdgeToo() {
        let (_, size) = ImageProcessing.resizeImage(
            flatImage(width: 3000, height: 4000), maxDimension: 2000, maxBytes: 900_000
        )

        XCTAssertEqual(max(size.width, size.height), 2000, accuracy: 1)
        XCTAssertEqual(size.height / size.width, 4.0 / 3.0, accuracy: 0.01)
    }

    /// The byte ceiling is the point of the whole routine: the PDS rejects a
    /// blob over its limit only after the upload has been paid for.
    func testAPhotographStaysUnderTheByteCeiling() {
        let (data, _) = ImageProcessing.resizeImage(
            gradientImage(width: 3000, height: 2000), maxDimension: 2000, maxBytes: 200_000
        )

        XCTAssertLessThanOrEqual(data.count, 200_000)
    }

    /// A lower ceiling must never produce a bigger file.
    func testTighterCeilingsNeverProduceLargerFiles() {
        let source = gradientImage(width: 2400, height: 1600)
        let sizes = [900_000, 400_000, 120_000].map {
            ImageProcessing.resizeImage(source, maxDimension: 2000, maxBytes: $0).0.count
        }

        XCTAssertEqual(sizes, sizes.sorted(by: >), "Byte counts should fall as the ceiling does: \(sizes)")
        for (size, ceiling) in zip(sizes, [900_000, 400_000, 120_000]) {
            XCTAssertLessThanOrEqual(size, ceiling)
        }
    }

    /// Detail JPEG can't compress is the case that used to break the ceiling:
    /// the quality search bottomed out, the routine scaled down once, re-encoded
    /// at a fixed quality and shipped it unchecked — landing five times over the
    /// limit. It now keeps scaling down until the encoding actually fits.
    func testAnIncompressibleImageStaysUnderTheCeilingToo() {
        let source = noisyImage(width: 3000, height: 2000)

        let (data, size) = ImageProcessing.resizeImage(source, maxDimension: 2000, maxBytes: 200_000)

        XCTAssertLessThanOrEqual(data.count, 200_000)
        XCTAssertLessThan(size.width, 2000, "Quality alone couldn't get there, so it had to scale down")
    }

    /// Resolution is given up only after quality has been, since softening is
    /// less visible than shrinking.
    func testQualityIsGivenUpBeforeResolution() {
        let source = gradientImage(width: 3000, height: 2000)

        let (_, size) = ImageProcessing.resizeImage(source, maxDimension: 2000, maxBytes: 200_000)

        XCTAssertEqual(size.width, 2000, accuracy: 1, "A compressible photo shouldn't lose any resolution")
    }

    /// A ceiling nothing could ever meet has to end somewhere rather than
    /// grinding the image down to a thumbnail or looping forever.
    func testAnUnreachableCeilingStopsAtAFloorRatherThanLooping() {
        let source = noisyImage(width: 2000, height: 2000)

        let (data, size) = ImageProcessing.resizeImage(source, maxDimension: 2000, maxBytes: 1)

        XCTAssertFalse(data.isEmpty, "It still has to return something postable")
        XCTAssertGreaterThanOrEqual(min(size.width, size.height), 240)
        XCTAssertLessThan(size.width, 2000)
    }

    func testTheResultIsDecodableJPEG() throws {
        let (data, size) = ImageProcessing.resizeImage(
            flatImage(width: 1200, height: 900), maxDimension: 600, maxBytes: 900_000
        )

        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(decoded.size.width, size.width, accuracy: 1)
        XCTAssertEqual(decoded.size.height, size.height, accuracy: 1)
    }

    // MARK: - extractGPS

    /// Builds a JPEG carrying the GPS tags a camera would write.
    private func jpegWithGPS(
        latitude: Double, latRef: String, longitude: Double, lonRef: String
    ) -> Data {
        let source = flatImage(width: 40, height: 40)
        let jpeg = source.jpegData(compressionQuality: 0.8)!
        let imageSource = CGImageSourceCreateWithData(jpeg as CFData, nil)!

        let gps: [String: Any] = [
            kCGImagePropertyGPSLatitude as String: latitude,
            kCGImagePropertyGPSLatitudeRef as String: latRef,
            kCGImagePropertyGPSLongitude as String: longitude,
            kCGImagePropertyGPSLongitudeRef as String: lonRef,
        ]

        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImageFromSource(
            destination, imageSource, 0,
            [kCGImagePropertyGPSDictionary as String: gps] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination), "Failed to build the GPS fixture")
        return output as Data
    }

    func testGPSIsReadFromAPhotoThatCarriesIt() {
        let data = jpegWithGPS(latitude: 38.72, latRef: "N", longitude: 9.14, lonRef: "W")

        let coordinate = ImageProcessing.extractGPS(from: data)

        XCTAssertEqual(coordinate?.latitude ?? 0, 38.72, accuracy: 0.0001)
        XCTAssertEqual(coordinate?.longitude ?? 0, -9.14, accuracy: 0.0001, "A western longitude must come back negative")
    }

    /// EXIF stores magnitudes with a hemisphere letter beside them, so both
    /// southern and western references have to flip the sign.
    func testSouthernAndWesternHemispheresAreNegated() {
        let southWest = ImageProcessing.extractGPS(
            from: jpegWithGPS(latitude: 33.86, latRef: "S", longitude: 151.2, lonRef: "W")
        )
        XCTAssertEqual(southWest?.latitude ?? 0, -33.86, accuracy: 0.0001)
        XCTAssertEqual(southWest?.longitude ?? 0, -151.2, accuracy: 0.0001)

        let northEast = ImageProcessing.extractGPS(
            from: jpegWithGPS(latitude: 33.86, latRef: "N", longitude: 151.2, lonRef: "E")
        )
        XCTAssertEqual(northEast?.latitude ?? 0, 33.86, accuracy: 0.0001)
        XCTAssertEqual(northEast?.longitude ?? 0, 151.2, accuracy: 0.0001)
    }

    /// Most photos in a library have no GPS at all — screenshots, scans,
    /// anything stripped by another app.
    func testAPhotoWithNoGPSReturnsNothing() throws {
        let plain = try XCTUnwrap(flatImage(width: 40, height: 40).jpegData(compressionQuality: 0.8))

        XCTAssertNil(ImageProcessing.extractGPS(from: plain))
    }

    func testDataThatIsNotAnImageReturnsNothing() {
        XCTAssertNil(ImageProcessing.extractGPS(from: Data("not an image".utf8)))
        XCTAssertNil(ImageProcessing.extractGPS(from: Data()))
    }
}

@testable import Grain
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest

/// The exif line under a photo in the create sheet. Separate from the record
/// extraction in `GalleryDraftBuilder` — this one is display-only, and gets to
/// leave out anything it can't format rather than storing a partial record.
@MainActor
final class ExifSummaryTests: XCTestCase {
    private func metadata(
        make: String? = "  FUJIFILM ",
        model: String? = "X100V ",
        lensModel: String? = " 23mm f/2 ",
        exposureTime: Double? = 0.002,
        fNumber: Double? = 2.0,
        iso: Int? = 400,
        focal: Any? = 35
    ) -> [String: Any] {
        var tiff: [String: Any] = [:]
        if let make {
            tiff[kCGImagePropertyTIFFMake as String] = make
        }
        if let model {
            tiff[kCGImagePropertyTIFFModel as String] = model
        }

        var exif: [String: Any] = [:]
        if let exposureTime {
            exif[kCGImagePropertyExifExposureTime as String] = exposureTime
        }
        if let fNumber {
            exif[kCGImagePropertyExifFNumber as String] = fNumber
        }
        if let iso {
            exif[kCGImagePropertyExifISOSpeedRatings as String] = [NSNumber(value: iso)]
        }
        if let focal {
            exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] = focal
        }

        var out: [String: Any] = [:]
        if !tiff.isEmpty {
            out[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        if !exif.isEmpty {
            out[kCGImagePropertyExifDictionary as String] = exif
        }
        if let lensModel {
            out[kCGImagePropertyExifAuxDictionary as String] = ["LensModel": lensModel]
        }
        return out
    }

    // MARK: - Camera name

    func testTheCameraNameJoinsMakeAndModel() throws {
        let summary = try XCTUnwrap(makeExifSummary(from: metadata(make: "Nikon", model: "Z6")))

        XCTAssertEqual(summary.camera, "Nikon Z6")
    }

    /// Most cameras already repeat the make in the model — "FUJIFILM X100V" —
    /// and printing it twice reads badly.
    func testAModelThatAlreadyNamesTheMakeIsNotDoubled() throws {
        let summary = try XCTUnwrap(makeExifSummary(from: metadata(make: "FUJIFILM", model: "FUJIFILM X100V")))

        XCTAssertEqual(summary.camera, "FUJIFILM X100V")
    }

    /// The check is case-insensitive, because the two fields rarely agree.
    func testTheDoubledMakeCheckIgnoresCase() throws {
        let summary = try XCTUnwrap(makeExifSummary(from: metadata(make: "fujifilm", model: "FUJIFILM X100V")))

        XCTAssertEqual(summary.camera, "FUJIFILM X100V")
    }

    func testMakeAndModelAreTrimmed() throws {
        let summary = try XCTUnwrap(makeExifSummary(from: metadata()))

        XCTAssertEqual(summary.camera, "FUJIFILM X100V")
    }

    /// A scan or an export often has a model and no make.
    func testAModelWithNoMakeStandsAlone() throws {
        let summary = try XCTUnwrap(makeExifSummary(from: metadata(make: nil, model: "X100V")))

        XCTAssertEqual(summary.camera, "X100V")
    }

    /// Without a model there is nothing to call the camera, whatever the make
    /// says.
    func testAMakeWithNoModelYieldsNoCameraName() throws {
        let summary = try XCTUnwrap(makeExifSummary(from: metadata(model: nil)))

        XCTAssertNil(summary.camera)
    }

    // MARK: - Lens

    func testTheLensNameIsTrimmed() throws {
        let summary = try XCTUnwrap(makeExifSummary(from: metadata()))

        XCTAssertEqual(summary.lens, "23mm f/2")
    }

    /// Not every camera writes the aux dictionary, so the plain exif field is
    /// the fallback.
    func testTheLensFallsBackToThePlainExifField() throws {
        var meta = metadata(lensModel: nil)
        var exif = meta[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exif[kCGImagePropertyExifLensModel as String] = " 35mm f/1.4 "
        meta[kCGImagePropertyExifDictionary as String] = exif

        let summary = try XCTUnwrap(makeExifSummary(from: meta))

        XCTAssertEqual(summary.lens, "35mm f/1.4")
    }

    // MARK: - Exposure

    /// A fast shutter reads as a fraction; anything at or over a second reads
    /// as seconds.
    func testShutterSpeedIsFormattedForBothEnds() throws {
        let fast = try XCTUnwrap(makeExifSummary(from: metadata(exposureTime: 0.002)))
        XCTAssertEqual(fast.shutterSpeed, "1/500s")

        let slow = try XCTUnwrap(makeExifSummary(from: metadata(exposureTime: 2.0)))
        XCTAssertEqual(slow.shutterSpeed, "2.0s")
    }

    func testApertureAndISOAreFormatted() throws {
        let summary = try XCTUnwrap(makeExifSummary(from: metadata(fNumber: 2.8, iso: 1600)))

        XCTAssertEqual(summary.aperture, "f/2.8")
        XCTAssertEqual(summary.iso, "ISO 1600")
    }

    /// Focal length arrives as an int from some cameras and a double from
    /// others.
    func testFocalLengthIsReadAsEitherAnIntOrADouble() throws {
        let asInt = try XCTUnwrap(makeExifSummary(from: metadata(focal: 35)))
        XCTAssertEqual(asInt.focalLength, "35mm")

        let asDouble = try XCTUnwrap(makeExifSummary(from: metadata(focal: 50.0 as Double)))
        XCTAssertEqual(asDouble.focalLength, "50mm")
    }

    /// A zero or missing focal length is left out rather than printed as "0mm".
    func testAZeroFocalLengthIsOmitted() throws {
        let summary = try XCTUnwrap(makeExifSummary(from: metadata(focal: 0)))

        XCTAssertNil(summary.focalLength)
    }

    /// The one-line summary is the four settings joined, in a fixed order.
    func testTheExposureLineJoinsEverySettingItHas() throws {
        let summary = try XCTUnwrap(makeExifSummary(from: metadata()))

        XCTAssertEqual(summary.exposure, "1/500s  ISO 400  35mm  f/2")
    }

    /// A photo with only some settings still gets a line, just a shorter one.
    func testTheExposureLineSkipsWhatIsMissing() throws {
        let summary = try XCTUnwrap(
            makeExifSummary(from: metadata(exposureTime: nil, fNumber: nil, focal: nil))
        )

        XCTAssertEqual(summary.exposure, "ISO 400")
    }

    func testThereIsNoExposureLineWithoutAnySettings() throws {
        let summary = try XCTUnwrap(
            makeExifSummary(from: metadata(exposureTime: nil, fNumber: nil, iso: nil, focal: nil))
        )

        XCTAssertNil(summary.exposure)
        XCTAssertNotNil(summary.camera, "The camera name alone is still worth showing")
    }

    // MARK: - Nothing to show

    /// A screenshot has no camera, no lens and no settings — the row should be
    /// absent rather than empty.
    func testMetadataWithNothingUsefulYieldsNoSummary() {
        XCTAssertNil(makeExifSummary(from: [:]))
        XCTAssertNil(makeExifSummary(from: ["Unrelated": "value"]))
        XCTAssertNil(buildExifSummary(exifDict: nil, tiffDict: nil, exifAux: nil))
    }

    // MARK: - From file data

    func testASummaryIsReadBackOutOfAJPEG() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            context.cgContext.setFillColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata() as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let summary = try XCTUnwrap(makeExifSummary(from: output as Data))

        XCTAssertEqual(summary.camera, "FUJIFILM X100V")
        XCTAssertEqual(summary.iso, "ISO 400")
    }

    func testDataThatIsNotAnImageYieldsNoSummary() {
        XCTAssertNil(makeExifSummary(from: Data("not an image".utf8)))
        XCTAssertNil(makeExifSummary(from: Data()))
    }

    // MARK: - Display bridge

    /// `ExifSummary` and the feed's `GrainExif` both feed one display model, so
    /// the mapping has to line up.
    func testTheSummaryMapsOntoTheDisplayModel() {
        let summary = ExifSummary(
            camera: "FUJIFILM X100V",
            lens: "23mm f/2",
            exposure: "1/500s  ISO 400",
            shutterSpeed: "1/500s",
            iso: "ISO 400",
            focalLength: "35mm",
            aperture: "f/2"
        )

        let display = summary.displayData

        XCTAssertEqual(display.camera, "FUJIFILM X100V")
        XCTAssertEqual(display.lens, "23mm f/2")
        XCTAssertEqual(display.focalLength, "35mm")
        XCTAssertEqual(display.fNumber, "f/2", "The display model calls it fNumber where the summary calls it aperture")
        XCTAssertEqual(display.exposureTime, "1/500s", "…and exposureTime where the summary calls it shutterSpeed")
        XCTAssertEqual(display.iso, "ISO 400")
    }
}

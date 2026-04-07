@testable import Grain
import XCTest

final class PhotoModelsTests: XCTestCase {
    // MARK: - Helpers

    private func makeExif(
        make: String? = nil,
        model: String? = nil,
        lensMake: String? = nil,
        lensModel: String? = nil,
        focalLength: String? = nil,
        fNumber: String? = nil,
        exposureTime: String? = nil,
        iso: Int? = nil
    ) -> GrainExif {
        GrainExif(
            uri: "at://test/photo.exif/1",
            cid: "cid",
            photo: "at://test/photo/1",
            createdAt: "2024-01-01T00:00:00Z",
            exposureTime: exposureTime,
            fNumber: fNumber,
            focalLengthIn35mmFormat: focalLength,
            iSO: iso,
            lensMake: lensMake,
            lensModel: lensModel,
            make: make,
            model: model
        )
    }

    // MARK: - cameraName

    func testCameraNameWithMakeAndModel() {
        let exif = makeExif(make: "Sony", model: "A7III")
        XCTAssertEqual(exif.cameraName, "Sony A7III")
    }

    func testCameraNameWithOnlyMake() {
        let exif = makeExif(make: "Canon")
        XCTAssertEqual(exif.cameraName, "Canon")
    }

    func testCameraNameWithOnlyModel() {
        let exif = makeExif(model: "X100V")
        XCTAssertEqual(exif.cameraName, "X100V")
    }

    func testCameraNameNilWhenBothMissing() {
        let exif = makeExif()
        XCTAssertNil(exif.cameraName)
    }

    func testCameraNameFiltersEmptyStrings() {
        let exif = makeExif(make: "", model: "A7III")
        XCTAssertEqual(exif.cameraName, "A7III")
    }

    // MARK: - lensName

    func testLensNamePrefersLensModel() {
        let exif = makeExif(lensMake: "Sigma", lensModel: "35mm f/1.4")
        XCTAssertEqual(exif.lensName, "35mm f/1.4")
    }

    func testLensNameNilWhenMissing() {
        let exif = makeExif()
        XCTAssertNil(exif.lensName)
    }

    func testLensNameWithEmptyLensModel() {
        let exif = makeExif(lensMake: "Sigma", lensModel: "")
        // Empty lensModel → falls to joined path, but lensModel is empty so only lensMake
        XCTAssertEqual(exif.lensName, "Sigma")
    }

    // MARK: - settingsLine

    func testSettingsLineAllPresent() {
        // settingsLine now routes focalLength + fNumber + exposureTime through their
        // formatter helpers, which always emit "Nmm", "f/N", and "1/Ns" forms.
        let exif = makeExif(focalLength: "35mm", fNumber: "f/1.4", exposureTime: "1/250", iso: 400)
        XCTAssertEqual(exif.settingsLine, "35mm  ·  f/1.4  ·  1/250s  ·  ISO 400")
    }

    func testSettingsLinePartial() {
        let exif = makeExif(fNumber: "f/2.8", iso: 100)
        XCTAssertEqual(exif.settingsLine, "f/2.8  ·  ISO 100")
    }

    func testSettingsLineNilWhenEmpty() {
        let exif = makeExif()
        XCTAssertNil(exif.settingsLine)
    }

    // MARK: - hasDisplayableData

    func testHasDisplayableDataTrue() {
        let exif = makeExif(make: "Sony")
        XCTAssertTrue(exif.hasDisplayableData)
    }

    func testHasDisplayableDataFalse() {
        let exif = makeExif()
        XCTAssertFalse(exif.hasDisplayableData)
    }

    // MARK: - formatAperture

    func testFormatApertureWholeNumberDropsZero() {
        XCTAssertEqual(formatAperture(2.0), "f/2")
    }

    func testFormatApertureOneDecimal() {
        XCTAssertEqual(formatAperture(2.5), "f/2.5")
    }

    func testFormatApertureTwoDecimals() {
        XCTAssertEqual(formatAperture(2.83), "f/2.83")
    }

    func testFormatApertureRoundsToTwoDecimals() {
        XCTAssertEqual(formatAperture(2.834), "f/2.83")
        XCTAssertEqual(formatAperture(2.836), "f/2.84")
    }

    func testFormatApertureSmallValue() {
        XCTAssertEqual(formatAperture(1.4), "f/1.4")
    }

    // MARK: - formatShutterSpeed

    func testFormatShutterSpeedFastFraction() {
        XCTAssertEqual(formatShutterSpeed(seconds: 0.002), "1/500s")
        XCTAssertEqual(formatShutterSpeed(seconds: 0.001), "1/1000s")
    }

    func testFormatShutterSpeedHalfSecond() {
        XCTAssertEqual(formatShutterSpeed(seconds: 0.5), "1/2s")
    }

    func testFormatShutterSpeedRoundsDenominator() {
        // 1/249.something should round to 1/250
        XCTAssertEqual(formatShutterSpeed(seconds: 1.0 / 249.7), "1/250s")
    }

    func testFormatShutterSpeedSlowWholeSecond() {
        XCTAssertEqual(formatShutterSpeed(seconds: 1.0), "1s")
        XCTAssertEqual(formatShutterSpeed(seconds: 2.0), "2s")
        XCTAssertEqual(formatShutterSpeed(seconds: 30.0), "30s")
    }

    func testFormatShutterSpeedSlowPreservesHalfSecond() {
        // Slow shutters keep one decimal of precision so 1.5s, 2.5s, etc. survive.
        XCTAssertEqual(formatShutterSpeed(seconds: 1.5), "1.5s")
        XCTAssertEqual(formatShutterSpeed(seconds: 2.5), "2.5s")
    }

    func testFormatShutterSpeedZeroOrNegative() {
        XCTAssertEqual(formatShutterSpeed(seconds: 0), "0s")
        XCTAssertEqual(formatShutterSpeed(seconds: -1), "0s")
    }

    // MARK: - formatFocalLength

    func testFormatFocalLengthWholeNumber() {
        XCTAssertEqual(formatFocalLength(mm: 35.0), "35mm")
    }

    func testFormatFocalLengthRoundsUp() {
        XCTAssertEqual(formatFocalLength(mm: 50.5), "51mm")
    }

    func testFormatFocalLengthRoundsDown() {
        XCTAssertEqual(formatFocalLength(mm: 24.4), "24mm")
    }

    // MARK: - formattedFNumber

    func testFormattedFNumberStripsPrefix() {
        let exif = makeExif(fNumber: "f/2.0")
        XCTAssertEqual(exif.formattedFNumber, "f/2")
    }

    func testFormattedFNumberWithoutPrefix() {
        let exif = makeExif(fNumber: "2.5")
        XCTAssertEqual(exif.formattedFNumber, "f/2.5")
    }

    func testFormattedFNumberWithDecimals() {
        let exif = makeExif(fNumber: "f/2.83")
        XCTAssertEqual(exif.formattedFNumber, "f/2.83")
    }

    func testFormattedFNumberNilWhenMissing() {
        let exif = makeExif()
        XCTAssertNil(exif.formattedFNumber)
    }

    func testFormattedFNumberFallsBackOnGarbage() {
        let exif = makeExif(fNumber: "bulb")
        XCTAssertEqual(exif.formattedFNumber, "bulb")
    }

    // MARK: - formattedExposureTime

    func testFormattedExposureTimeWithDecimalDenominator() {
        let exif = makeExif(exposureTime: "1/500.0")
        XCTAssertEqual(exif.formattedExposureTime, "1/500s")
    }

    func testFormattedExposureTimeWithSuffix() {
        let exif = makeExif(exposureTime: "1/250s")
        XCTAssertEqual(exif.formattedExposureTime, "1/250s")
    }

    func testFormattedExposureTimeAsDecimalSeconds() {
        let exif = makeExif(exposureTime: "0.002")
        XCTAssertEqual(exif.formattedExposureTime, "1/500s")
    }

    func testFormattedExposureTimeWholeSecond() {
        let exif = makeExif(exposureTime: "2.0s")
        XCTAssertEqual(exif.formattedExposureTime, "2s")
    }

    func testFormattedExposureTimeNilWhenMissing() {
        let exif = makeExif()
        XCTAssertNil(exif.formattedExposureTime)
    }

    func testFormattedExposureTimeRejectsZeroDenominator() {
        let exif = makeExif(exposureTime: "1/0")
        // 1/0 is invalid; we should pass through the original string rather than
        // produce a divide-by-zero result.
        XCTAssertEqual(exif.formattedExposureTime, "1/0")
    }

    func testFormattedExposureTimeFallsBackOnGarbage() {
        let exif = makeExif(exposureTime: "bulb")
        XCTAssertEqual(exif.formattedExposureTime, "bulb")
    }

    func testFormattedExposureTimePreservesSecAfterTrim() {
        // The string "1/500 sec" should NOT get mangled into "1/500 ec" — only the
        // single trailing "s" is stripped.
        let exif = makeExif(exposureTime: "1/500 sec")
        // With the safe trimming, "sec" doesn't end in just "s" cleanly — it does
        // end in "c", so suffix-trim of "s" doesn't apply. The string falls through
        // to the parser which can't parse "1/500 sec", so we return the original.
        XCTAssertEqual(exif.formattedExposureTime, "1/500 sec")
    }

    // MARK: - formattedFocalLength

    func testFormattedFocalLengthStripsSuffix() {
        let exif = makeExif(focalLength: "35.0mm")
        XCTAssertEqual(exif.formattedFocalLength, "35mm")
    }

    func testFormattedFocalLengthWithoutSuffix() {
        let exif = makeExif(focalLength: "50.0")
        XCTAssertEqual(exif.formattedFocalLength, "50mm")
    }

    func testFormattedFocalLengthRounds() {
        let exif = makeExif(focalLength: "23.6mm")
        XCTAssertEqual(exif.formattedFocalLength, "24mm")
    }

    func testFormattedFocalLengthNilWhenMissing() {
        let exif = makeExif()
        XCTAssertNil(exif.formattedFocalLength)
    }

    // MARK: - settingsLine uses formatted versions

    func testSettingsLineUsesFormattedFocalLength() {
        let exif = makeExif(focalLength: "35.0mm", iso: 100)
        XCTAssertEqual(exif.settingsLine, "35mm  ·  ISO 100")
    }

    func testSettingsLineUsesFormattedExposureTime() {
        let exif = makeExif(exposureTime: "1/500.0", iso: 100)
        XCTAssertEqual(exif.settingsLine, "1/500s  ·  ISO 100")
    }

    func testSettingsLineFullyFormatted() {
        let exif = makeExif(
            focalLength: "35.0mm",
            fNumber: "f/2.0",
            exposureTime: "1/500.0",
            iso: 400
        )
        XCTAssertEqual(exif.settingsLine, "35mm  ·  f/2  ·  1/500s  ·  ISO 400")
    }
}

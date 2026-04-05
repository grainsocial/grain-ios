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
        let exif = makeExif(focalLength: "35mm", fNumber: "f/1.4", exposureTime: "1/250", iso: 400)
        XCTAssertEqual(exif.settingsLine, "35mm  ·  f/1.4  ·  1/250  ·  ISO 400")
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
}

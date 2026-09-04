@testable import Grain
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest

/// Turning what's on screen into a draft on disk. This is the expensive,
/// entirely offline half of posting: every photo is resized and written out,
/// and every record key is assigned, so that publishing can then be resumed
/// from the draft alone.
@MainActor
final class GalleryDraftBuilderTests: XCTestCase {
    private var root: URL!
    private var store: GalleryDraftStore!

    override func setUp() async throws {
        try await super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("draftbuilder-\(UUID().uuidString)", isDirectory: true)
        store = GalleryDraftStore(root: root)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func image(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            context.cgContext.setFillColor(red: 0.3, green: 0.6, blue: 0.4, alpha: 1)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func item(width: Int = 900, height: Int = 600, alt: String = "", metadata: [String: Any]? = nil) -> PhotoItem {
        let photo = image(width: width, height: height)
        return PhotoItem(
            thumbnail: photo,
            carouselPreview: photo,
            source: .camera(photo, metadata: metadata),
            alt: alt
        )
    }

    private func build(
        items: [PhotoItem],
        title: String = "A gallery",
        description: String = "",
        labels: [String] = [],
        location: GalleryDraft.Location? = nil,
        includeExif: Bool = false,
        postToBluesky: Bool = false,
        onProgress: @MainActor @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> GalleryDraft {
        try await GalleryDraft.build(
            items: items,
            repo: "did:plc:test",
            title: title,
            description: description,
            labels: labels,
            location: location,
            includeExif: includeExif,
            postToBluesky: postToBluesky,
            store: store,
            onProgress: onProgress
        )
    }

    // MARK: - Building

    func testBuildingWritesADraftThatCanBeReadBackFromDisk() async throws {
        let draft = try await build(items: [item(), item()])

        let reloaded = try XCTUnwrap(store.load(draft.id))
        XCTAssertEqual(reloaded.id, draft.id)
        XCTAssertEqual(reloaded.photos.count, 2)
        XCTAssertEqual(reloaded.title, "A gallery")
        XCTAssertEqual(reloaded.repo, "did:plc:test")
    }

    /// The whole point of the draft is that the picker items and this process
    /// are no longer needed once it exists — so the pixels have to be on disk.
    func testEveryPhotoIsWrittenBesideTheDraft() async throws {
        let draft = try await build(items: [item(), item(), item()])

        for photo in draft.photos {
            let data = try store.readImage(draftID: draft.id, fileName: photo.fileName)
            XCTAssertFalse(data.isEmpty, "\(photo.fileName) was recorded but never written")
            XCTAssertNotNil(UIImage(data: data), "\(photo.fileName) isn't a decodable image")
        }
    }

    /// Photos are resized to upload size up front, not at publish time.
    func testPhotosAreResizedToUploadSize() async throws {
        let draft = try await build(items: [item(width: 4000, height: 3000)])

        let photo = try XCTUnwrap(draft.photos.first)
        XCTAssertEqual(max(photo.width, photo.height), 2000)
        XCTAssertEqual(Double(photo.width) / Double(photo.height), 4.0 / 3.0, accuracy: 0.01)
    }

    func testASmallPhotoKeepsItsOwnDimensions() async throws {
        let draft = try await build(items: [item(width: 900, height: 600)])

        let photo = try XCTUnwrap(draft.photos.first)
        XCTAssertEqual(photo.width, 900)
        XCTAssertEqual(photo.height, 600)
    }

    /// Every record key is assigned up front so a retry overwrites its own
    /// records rather than creating a second gallery.
    func testEveryRecordKeyIsAssignedAndUnique() async throws {
        let draft = try await build(items: [item(), item()])

        var keys = [draft.galleryRkey, draft.blueskyRkey]
        for photo in draft.photos {
            keys.append(contentsOf: [photo.photoRkey, photo.exifRkey, photo.itemRkey])
        }

        XCTAssertTrue(keys.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(keys).count, keys.count, "Two records share a key: \(keys)")
    }

    /// One `createdAt` is frozen for the whole gallery, so a retry two minutes
    /// later writes byte-identical records.
    func testTheTimestampIsFrozenWhenTheDraftIsBuilt() async throws {
        let before = Date()
        let draft = try await build(items: [item(), item()])
        let after = Date()

        let created = try XCTUnwrap(DateFormatting.parse(draft.createdAt))
        XCTAssertGreaterThanOrEqual(created.timeIntervalSince1970, before.timeIntervalSince1970 - 1)
        XCTAssertLessThanOrEqual(created.timeIntervalSince1970, after.timeIntervalSince1970 + 1)
        XCTAssertEqual(store.load(draft.id)?.createdAt, draft.createdAt, "The frozen timestamp must survive to disk")
    }

    /// Every URI the gallery will publish under is derivable from the draft
    /// alone, which is what makes a resume safe.
    func testTheDraftKnowsEveryURIItWillPublishUnder() async throws {
        let draft = try await build(items: [item()])
        let photo = try XCTUnwrap(draft.photos.first)

        XCTAssertEqual(draft.galleryUri, "at://did:plc:test/social.grain.gallery/\(draft.galleryRkey)")
        XCTAssertEqual(draft.photoUri(photo), "at://did:plc:test/social.grain.photo/\(photo.photoRkey)")
        XCTAssertEqual(draft.displayTitle, "A gallery")
    }

    func testAnUntitledGalleryStillHasSomethingToShowInTheResumeBanner() async throws {
        let draft = try await build(items: [item()], title: "   ")
        XCTAssertEqual(draft.displayTitle, "Untitled gallery")
    }

    func testTheDraftCarriesTheComposedFields() async throws {
        let location = GalleryDraft.Location(h3: "8a2a1072b59ffff", name: "Lisboa", address: nil)
        let draft = try await build(
            items: [item()],
            title: "Golden hour",
            description: "Shot on Portra.",
            labels: ["nudity"],
            location: location,
            includeExif: true,
            postToBluesky: true
        )

        XCTAssertEqual(draft.title, "Golden hour")
        XCTAssertEqual(draft.description, "Shot on Portra.")
        XCTAssertEqual(draft.labels, ["nudity"])
        XCTAssertEqual(draft.location?.h3, "8a2a1072b59ffff")
        XCTAssertTrue(draft.includeExif)
        XCTAssertTrue(draft.postToBluesky)
        XCTAssertFalse(draft.committed)
        XCTAssertFalse(draft.crossPosted)
    }

    func testAltTextIsCarriedOntoThePhoto() async throws {
        let draft = try await build(items: [item(alt: "A quiet street"), item()])

        XCTAssertEqual(draft.photos.first?.alt, "A quiet street")
        XCTAssertEqual(draft.photos.last?.alt, "")
    }

    /// The progress callback drives the "Preparing photo 3 of 8" label, so it
    /// has to fire once per photo, counting from one.
    func testProgressIsReportedOncePerPhoto() async throws {
        let reported = Reported()

        _ = try await build(items: [item(), item(), item()], onProgress: { done, total in
            reported.append(done: done, total: total)
        })

        XCTAssertEqual(reported.pairs.map(\.done), [1, 2, 3])
        XCTAssertTrue(reported.pairs.allSatisfy { $0.total == 3 })
    }

    func testBuildingAGalleryWithNoPhotosStillProducesADraft() async throws {
        let draft = try await build(items: [])

        XCTAssertTrue(draft.photos.isEmpty)
        XCTAssertEqual(draft.uploadedPhotoCount, 0)
        XCTAssertNotNil(store.load(draft.id))
    }

    /// Two drafts must never share a directory, or one would overwrite the
    /// other's photos.
    func testTwoDraftsGetTheirOwnDirectories() async throws {
        let first = try await build(items: [item()])
        let second = try await build(items: [item()])

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(store.directory(for: first.id), store.directory(for: second.id))
        XCTAssertEqual(store.loadAll().count, 2)
    }

    // MARK: - EXIF extraction

    private func cameraMetadata(
        flash: Int = 16,
        captureDate: String = "2025:01:02 15:04:05",
        includeAux: Bool = true
    ) -> [String: Any] {
        var metadata: [String: Any] = [
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: "  FUJIFILM ",
                kCGImagePropertyTIFFModel as String: "X100V ",
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifExposureTime as String: 0.002,
                kCGImagePropertyExifFNumber as String: 2.0,
                kCGImagePropertyExifISOSpeedRatings as String: [NSNumber(value: 400)],
                kCGImagePropertyExifFocalLenIn35mmFilm as String: 35,
                kCGImagePropertyExifFlash as String: flash,
                kCGImagePropertyExifDateTimeOriginal as String: captureDate,
                kCGImagePropertyExifLensModel as String: " 23mm f/2 ",
            ],
        ]
        if includeAux {
            metadata[kCGImagePropertyExifAuxDictionary as String] = ["LensMake": " FUJIFILM "]
        }
        return metadata
    }

    /// The exif dictionary is only ever seen by the PDS as JSON, so read it
    /// back the way the server would rather than reaching into `AnyCodable`.
    private func asRecord(_ exif: [String: AnyCodable]?) throws -> [String: Any] {
        let exif = try XCTUnwrap(exif)
        let data = try JSONEncoder().encode(exif)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testExifFromCameraMetadataIsScaledAndTrimmed() throws {
        let record = try asRecord(extractExifFromMetadata(cameraMetadata()))

        XCTAssertEqual(record["make"] as? String, "FUJIFILM", "Camera makes arrive padded with spaces")
        XCTAssertEqual(record["model"] as? String, "X100V")
        XCTAssertEqual(record["lensMake"] as? String, "FUJIFILM")
        XCTAssertEqual(record["lensModel"] as? String, "23mm f/2")
        // Rationals are stored as integers scaled by a million.
        XCTAssertEqual(record["exposureTime"] as? Int, 2000)
        XCTAssertEqual(record["fNumber"] as? Int, 2_000_000)
        XCTAssertEqual(record["iSO"] as? Int, 400_000_000)
        XCTAssertEqual(record["focalLengthIn35mmFormat"] as? Int, 35_000_000)
    }

    /// Flash is a bitfield on the wire and a sentence on screen.
    func testFlashIsTurnedIntoSomethingReadable() throws {
        let cases = [
            (0, "Off, Did not fire"), (1, "On, Fired"), (5, "On, Return not detected"),
            (7, "On, Return detected"), (16, "Off, Did not fire"), (24, "Off, Auto"), (25, "On, Auto"),
        ]
        for (raw, expected) in cases {
            let record = try asRecord(extractExifFromMetadata(cameraMetadata(flash: raw)))
            XCTAssertEqual(record["flash"] as? String, expected, "Flash \(raw)")
        }
    }

    /// A flash value the table doesn't know still has to say something rather
    /// than drop the field.
    func testAnUnknownFlashValueIsLabelledAsSuch() throws {
        let record = try asRecord(extractExifFromMetadata(cameraMetadata(flash: 93)))
        XCTAssertEqual(record["flash"] as? String, "Unknown (93)")
    }

    /// Cameras write `yyyy:MM:dd HH:mm:ss`; the record wants ISO 8601.
    func testTheCaptureDateIsConvertedToISO8601() throws {
        let record = try asRecord(extractExifFromMetadata(cameraMetadata()))
        let raw = try XCTUnwrap(record["dateTimeOriginal"] as? String)

        XCTAssertNotNil(ISO8601DateFormatter().date(from: raw), "\(raw) isn't ISO 8601")
    }

    func testAnUnparseableCaptureDateIsDroppedRatherThanGuessed() throws {
        let record = try asRecord(extractExifFromMetadata(cameraMetadata(captureDate: "not a date")))
        XCTAssertNil(record["dateTimeOriginal"])
    }

    /// A screenshot or a scan has no camera metadata at all.
    func testMetadataWithNothingUsefulYieldsNoExifRecord() {
        XCTAssertNil(extractExifFromMetadata(nil))
        XCTAssertNil(extractExifFromMetadata([:]))
        XCTAssertNil(extractExifFromMetadata(["Unrelated": "value"]))
    }

    /// The lens make falls back through three sources before giving up.
    func testTheLensMakeFallsBackToTheCameraMake() throws {
        let record = try asRecord(extractExifFromMetadata(cameraMetadata(includeAux: false)))
        XCTAssertEqual(record["lensMake"] as? String, "FUJIFILM")
    }

    // MARK: - Exif from file data

    private func jpegWithExif() -> Data {
        let source = image(width: 60, height: 40)
        let jpeg = source.jpegData(compressionQuality: 0.8)!
        let imageSource = CGImageSourceCreateWithData(jpeg as CFData, nil)!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImageFromSource(destination, imageSource, 0, cameraMetadata() as CFDictionary)
        _ = CGImageDestinationFinalize(destination)
        return output as Data
    }

    func testExifIsReadBackOutOfAJPEG() throws {
        let record = try asRecord(extractGalleryExif(from: jpegWithExif()))

        XCTAssertEqual(record["make"] as? String, "FUJIFILM")
        XCTAssertEqual(record["model"] as? String, "X100V")
        XCTAssertEqual(record["iSO"] as? Int, 400_000_000)
    }

    func testAJPEGWithNoExifYieldsNothing() throws {
        let plain = try XCTUnwrap(image(width: 40, height: 40).jpegData(compressionQuality: 0.8))
        XCTAssertNil(extractGalleryExif(from: plain))
    }

    func testDataThatIsNotAnImageYieldsNothing() {
        XCTAssertNil(extractGalleryExif(from: Data("not an image".utf8)))
    }

    // MARK: - Errors

    /// Reaches the user in an alert, so it has to name the photo they need to
    /// remove — counting from one, as the picker does.
    func testTheUnreadablePhotoErrorCountsFromOne() {
        XCTAssertEqual(
            GalleryDraftError.photoUnavailable(index: 0).errorDescription,
            "Photo 1 couldn't be read from your library. Remove it and try again."
        )
        XCTAssertEqual(
            GalleryDraftError.photoUnavailable(index: 4).errorDescription?.hasPrefix("Photo 5"),
            true
        )
    }
}

/// The progress callback is `@Sendable`, so what it records can't be a captured
/// local.
private final class Reported: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(done: Int, total: Int)] = []

    func append(done: Int, total: Int) {
        lock.withLock { values.append((done, total)) }
    }

    var pairs: [(done: Int, total: Int)] {
        lock.withLock { values }
    }
}

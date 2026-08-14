import ImageIO
import os
import PhotosUI
import UIKit

private let logger = Logger(subsystem: "social.grain.grain", category: "GalleryDraft")

enum GalleryDraftError: LocalizedError {
    case photoUnavailable(index: Int)

    var errorDescription: String? {
        switch self {
        case let .photoUnavailable(index):
            "Photo \(index + 1) couldn't be read from your library. Remove it and try again."
        }
    }
}

extension GalleryDraft {
    /// Turn what's on screen into a draft on disk.
    ///
    /// This is where the expensive, entirely offline half of posting happens:
    /// each photo is decoded, resized to upload size, and written into the
    /// draft's directory, and every record key is assigned. Once this returns
    /// the gallery can be published from the draft alone — the picker items,
    /// the in-memory previews, and even this app process are no longer needed.
    static func build(
        items: [PhotoItem],
        repo: String,
        title: String,
        description: String,
        labels: [String],
        location: Location?,
        includeExif: Bool,
        postToBluesky: Bool,
        store: GalleryDraftStore = .shared,
        onProgress: @MainActor @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> GalleryDraft {
        let draftID = UUID()
        do {
            return try await assemble(
                draftID: draftID,
                items: items,
                repo: repo,
                title: title,
                description: description,
                labels: labels,
                location: location,
                includeExif: includeExif,
                postToBluesky: postToBluesky,
                store: store,
                onProgress: onProgress
            )
        } catch {
            // Don't leave the JPEGs we'd already written behind: without a
            // draft.json beside them nothing would ever pick them up again.
            store.delete(draftID)
            throw error
        }
    }

    private static func assemble(
        draftID: UUID,
        items: [PhotoItem],
        repo: String,
        title: String,
        description: String,
        labels: [String],
        location: Location?,
        includeExif: Bool,
        postToBluesky: Bool,
        store: GalleryDraftStore,
        onProgress: @MainActor @Sendable (Int, Int) -> Void
    ) async throws -> GalleryDraft {
        let total = items.count
        var photos: [Photo] = []

        for (index, item) in items.enumerated() {
            let resized: Data
            let size: CGSize
            var exif: [String: AnyCodable]?

            switch item.source {
            case let .picker(pickerItem):
                guard let data = try await pickerItem.loadTransferable(type: Data.self),
                      let original = UIImage(data: data)
                else {
                    // Previously this photo was silently dropped and the
                    // gallery posted one short. Better to say so.
                    throw GalleryDraftError.photoUnavailable(index: index)
                }
                if includeExif {
                    exif = extractGalleryExif(from: data)
                }
                (resized, size) = ImageProcessing.resizeImage(original, maxDimension: 2000, maxBytes: 900_000)

            case let .camera(image, metadata):
                if includeExif {
                    exif = extractExifFromMetadata(metadata)
                }
                (resized, size) = ImageProcessing.resizeImage(image, maxDimension: 2000, maxBytes: 900_000)
            }

            let fileName = "\(item.id.uuidString).jpg"
            try store.writeImage(resized, draftID: draftID, fileName: fileName)
            logger.info("Prepared photo \(index + 1)/\(total): \(resized.count) bytes, \(Int(size.width))x\(Int(size.height))")

            photos.append(Photo(
                id: item.id,
                fileName: fileName,
                width: Int(size.width),
                height: Int(size.height),
                alt: item.alt,
                exif: exif,
                photoRkey: TID.next(),
                exifRkey: TID.next(),
                itemRkey: TID.next()
            ))
            await onProgress(index + 1, total)
        }

        let draft = GalleryDraft(
            id: draftID,
            repo: repo,
            title: title,
            description: description,
            labels: labels,
            location: location,
            includeExif: includeExif,
            postToBluesky: postToBluesky,
            createdAt: DateFormatting.nowISO(),
            galleryRkey: TID.next(),
            blueskyRkey: TID.next(),
            photos: photos
        )
        store.save(draft)
        return draft
    }
}

// MARK: - EXIF record extraction

// These build the `social.grain.photo.exif` record. The display-oriented
// `ExifSummary` used by the editor is a separate path in `CreateGalleryView`.

private func flashDescription(for flash: Int) -> String {
    switch flash {
    case 0: "Off, Did not fire"
    case 1: "On, Fired"
    case 5: "On, Return not detected"
    case 7: "On, Return detected"
    case 16: "Off, Did not fire"
    case 24: "Off, Auto"
    case 25: "On, Auto"
    default: "Unknown (\(flash))"
    }
}

private func extractCameraInfo(
    exifDict: [String: Any]?,
    tiffDict: [String: Any]?,
    exifAux: [String: Any]?,
    into result: inout [String: AnyCodable]
) {
    if let make = tiffDict?[kCGImagePropertyTIFFMake as String] as? String {
        result["make"] = AnyCodable(make.trimmingCharacters(in: .whitespaces))
    }
    if let model = tiffDict?[kCGImagePropertyTIFFModel as String] as? String {
        result["model"] = AnyCodable(model.trimmingCharacters(in: .whitespaces))
    }
    let lensMake = exifAux?["LensMake"] as? String
        ?? exifDict?["LensMake"] as? String
        ?? tiffDict?[kCGImagePropertyTIFFMake as String] as? String
    if let lensMake {
        result["lensMake"] = AnyCodable(lensMake.trimmingCharacters(in: .whitespaces))
    }
    let lensModel = exifAux?["LensModel"] as? String
        ?? exifDict?[kCGImagePropertyExifLensModel as String] as? String
    if let lensModel {
        result["lensModel"] = AnyCodable(lensModel.trimmingCharacters(in: .whitespaces))
    }
}

private func extractExposureInfo(
    exifDict: [String: Any]?,
    scale: Int,
    into result: inout [String: AnyCodable]
) {
    if let exposureTime = exifDict?[kCGImagePropertyExifExposureTime as String] as? Double {
        result["exposureTime"] = AnyCodable(Int(exposureTime * Double(scale)))
    }
    if let fNumber = exifDict?[kCGImagePropertyExifFNumber as String] as? Double {
        result["fNumber"] = AnyCodable(Int(fNumber * Double(scale)))
    }
    if let isoRaw = exifDict?[kCGImagePropertyExifISOSpeedRatings as String] as? [Any],
       let iso = (isoRaw.first as? NSNumber)?.intValue
    {
        result["iSO"] = AnyCodable(iso * scale)
    }
    if let focal35 = exifDict?[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Int {
        result["focalLengthIn35mmFormat"] = AnyCodable(focal35 * scale)
    } else if let focal35 = exifDict?[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Double {
        result["focalLengthIn35mmFormat"] = AnyCodable(Int(focal35) * scale)
    }
    if let flash = exifDict?[kCGImagePropertyExifFlash as String] as? Int {
        result["flash"] = AnyCodable(flashDescription(for: flash))
    }
    if let dateStr = exifDict?[kCGImagePropertyExifDateTimeOriginal as String] as? String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let date = formatter.date(from: dateStr) {
            result["dateTimeOriginal"] = AnyCodable(ISO8601DateFormatter().string(from: date))
        }
    }
}

func extractExifFromMetadata(_ metadata: [String: Any]?) -> [String: AnyCodable]? {
    guard let metadata else { return nil }
    let exifDict = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let tiffDict = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
    let exifAux = metadata[kCGImagePropertyExifAuxDictionary as String] as? [String: Any]
    var result: [String: AnyCodable] = [:]
    extractCameraInfo(exifDict: exifDict, tiffDict: tiffDict, exifAux: exifAux, into: &result)
    extractExposureInfo(exifDict: exifDict, scale: 1_000_000, into: &result)
    return result.isEmpty ? nil : result
}

func extractGalleryExif(from data: Data) -> [String: AnyCodable]? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    else {
        logger.warning("No image properties found")
        return nil
    }

    let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
    let exifAux = properties[kCGImagePropertyExifAuxDictionary as String] as? [String: Any]
    var result: [String: AnyCodable] = [:]

    extractCameraInfo(exifDict: exifDict, tiffDict: tiffDict, exifAux: exifAux, into: &result)
    extractExposureInfo(exifDict: exifDict, scale: 1_000_000, into: &result)

    return result.isEmpty ? nil : result
}

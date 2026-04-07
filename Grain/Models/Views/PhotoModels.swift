import Foundation

/// Format a Double aperture value as "f/N" with up to 2 fraction digits, dropping
/// trailing zeros. e.g., 2.0 → "f/2", 2.5 → "f/2.5", 2.83 → "f/2.83".
func formatAperture(_ value: Double) -> String {
    var str = String(format: "%.2f", value)
    while str.hasSuffix("0") {
        str.removeLast()
    }
    if str.hasSuffix(".") { str.removeLast() }
    return "f/" + str
}

/// social.grain.photo.defs#photoView
struct GrainPhoto: Codable, Sendable, Identifiable {
    let uri: String
    let cid: String
    let thumb: String
    let fullsize: String
    var alt: String?
    let aspectRatio: AspectRatio
    var exif: GrainExif?
    var gallery: PhotoGalleryState?

    var id: String {
        uri
    }
}

/// social.grain.photo.defs#exifView
struct GrainExif: Codable, Sendable {
    let uri: String
    let cid: String
    let photo: String
    var record: AnyCodable?
    let createdAt: String
    var dateTimeOriginal: String?
    var exposureTime: String?
    var fNumber: String?
    var flash: String?
    var focalLengthIn35mmFormat: String?
    var iSO: Int?
    var lensMake: String?
    var lensModel: String?
    var make: String?
    var model: String?

    var cameraName: String? {
        let parts = [make, model].compactMap(\.self).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var lensName: String? {
        if let lensModel, !lensModel.isEmpty { return lensModel }
        let parts = [lensMake, lensModel].compactMap(\.self).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Re-formats the server-supplied fNumber string to drop trailing zeros.
    /// "f/2.0" → "f/2", "2.0" → "f/2", "f/2.83" → "f/2.83".
    var formattedFNumber: String? {
        guard let fNumber else { return nil }
        let cleaned = fNumber
            .replacingOccurrences(of: "f/", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned) else { return fNumber }
        return formatAperture(value)
    }

    var settingsLine: String? {
        let parts = [
            focalLengthIn35mmFormat,
            formattedFNumber,
            exposureTime,
            iSO.map { "ISO \($0)" },
        ].compactMap(\.self).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    var hasDisplayableData: Bool {
        cameraName != nil || lensName != nil || settingsLine != nil
    }
}

/// social.grain.photo.defs#galleryState
struct PhotoGalleryState: Codable, Sendable {
    let item: String
    let itemCreatedAt: String
    let itemPosition: Int
}

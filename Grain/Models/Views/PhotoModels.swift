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

/// Format shutter speed. Fast shutters (< 1s) use "1/Ns" with a whole-number
/// denominator. Slow shutters preserve up to one decimal place, dropping trailing
/// zeros. e.g., 0.002 → "1/500s", 0.5 → "1/2s", 1.0 → "1s", 1.5 → "1.5s", 2.0 → "2s".
func formatShutterSpeed(seconds value: Double) -> String {
    guard value > 0 else { return "0s" }
    if value < 1 {
        let denom = max(1, Int((1 / value).rounded()))
        return "1/\(denom)s"
    }
    // Slow shutter: one decimal, trim trailing zero
    var str = String(format: "%.1f", value)
    if str.hasSuffix("0") { str.removeLast() }
    if str.hasSuffix(".") { str.removeLast() }
    return str + "s"
}

/// Format focal length as "Nmm" with whole-number millimeters. e.g., 35.0 → "35mm",
/// 50.5 → "51mm".
func formatFocalLength(mm value: Double) -> String {
    "\(Int(value.rounded()))mm"
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

    /// Re-formats the server-supplied exposure time string so the 1/N denominator
    /// is always a whole number. Handles "1/500", "1/500s", "1/500.0", and seconds
    /// strings like "0.002s" or "30s". Falls back to the original string for any
    /// input we can't parse (so "bulb", "1/0", etc. pass through unchanged).
    var formattedExposureTime: String? {
        guard let exposureTime else { return nil }
        var cleaned = exposureTime.trimmingCharacters(in: .whitespaces)
        if cleaned.hasSuffix("s") { cleaned.removeLast() }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        if cleaned.hasPrefix("1/") {
            let denomStr = String(cleaned.dropFirst(2))
            if let denom = Double(denomStr), denom > 0 {
                return formatShutterSpeed(seconds: 1.0 / denom)
            }
        }
        if let seconds = Double(cleaned) {
            return formatShutterSpeed(seconds: seconds)
        }
        return exposureTime
    }

    /// Re-formats the server-supplied focal length so the millimeters value is always
    /// a whole number. Handles "35", "35.0", "35mm", "35.0mm".
    var formattedFocalLength: String? {
        guard let focalLengthIn35mmFormat else { return nil }
        var cleaned = focalLengthIn35mmFormat.trimmingCharacters(in: .whitespaces)
        if cleaned.hasSuffix("mm") { cleaned.removeLast(2) }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if let value = Double(cleaned) {
            return formatFocalLength(mm: value)
        }
        return focalLengthIn35mmFormat
    }

    var settingsLine: String? {
        let parts = [
            formattedFocalLength,
            formattedFNumber,
            formattedExposureTime,
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

import Foundation

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

    var settingsLine: String? {
        let parts = [
            focalLengthIn35mmFormat,
            fNumber,
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

import Foundation

/// social.grain.photo record
struct PhotoRecord: Codable, Sendable {
    let photo: BlobRef
    var alt: String?
    let aspectRatio: AspectRatio
    let createdAt: String
}

/// social.grain.photo.exif record
/// Integer values are scaled by 1,000,000 to accommodate decimals.
struct PhotoExifRecord: Codable, Sendable {
    let photo: String
    let createdAt: String
    var dateTimeOriginal: String?
    var exposureTime: Int?
    var fNumber: Int?
    var flash: String?
    var focalLengthIn35mmFormat: Int?
    var iSO: Int?
    var lensMake: String?
    var lensModel: String?
    var make: String?
    var model: String?
}

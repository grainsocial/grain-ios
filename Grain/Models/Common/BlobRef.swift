import Foundation

/// AT Protocol blob reference returned from uploadBlob
struct BlobRef: Codable, Sendable {
    let type: String?
    let ref: BlobLink?
    let mimeType: String?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case ref
        case mimeType
        case size
    }

    struct BlobLink: Codable, Sendable {
        let link: String

        enum CodingKeys: String, CodingKey {
            case link = "$link"
        }
    }
}

/// Label definition (com.atproto.label.defs#label)
struct ATLabel: Codable, Sendable {
    let src: String?
    let uri: String?
    let val: String?
    let cts: String?
}

/// Self-label values (com.atproto.label.defs#selfLabels)
struct SelfLabels: Codable, Sendable {
    let type: String?
    let values: [SelfLabel]?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case values
    }
}

struct SelfLabel: Codable, Sendable {
    let val: String
}

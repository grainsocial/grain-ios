import Foundation

/// Rich text annotation (app.bsky.richtext.facet)
struct Facet: Codable, Sendable {
    let index: ByteSlice
    let features: [FacetFeature]

    struct ByteSlice: Codable, Sendable {
        let byteStart: Int
        let byteEnd: Int
    }
}

extension Facet {
    /// Encodes the facet as the dict shape used in `createRecord` calls
    /// (matches `app.bsky.richtext.facet`).
    func toAnyCodableDict() -> [String: AnyCodable] {
        let featureDicts: [[String: AnyCodable]] = features.map { feature in
            switch feature {
            case let .link(uri):
                ["$type": AnyCodable("app.bsky.richtext.facet#link"), "uri": AnyCodable(uri)]
            case let .mention(did):
                ["$type": AnyCodable("app.bsky.richtext.facet#mention"), "did": AnyCodable(did)]
            case let .tag(tag):
                ["$type": AnyCodable("app.bsky.richtext.facet#tag"), "tag": AnyCodable(tag)]
            }
        }
        return [
            "index": AnyCodable([
                "byteStart": AnyCodable(index.byteStart),
                "byteEnd": AnyCodable(index.byteEnd),
            ] as [String: AnyCodable]),
            "features": AnyCodable(featureDicts as [[String: AnyCodable]]),
        ]
    }
}

enum FacetFeature: Codable, Sendable {
    case mention(did: String)
    case link(uri: String)
    case tag(tag: String)

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case did
        case uri
        case tag
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "app.bsky.richtext.facet#mention":
            let did = try container.decode(String.self, forKey: .did)
            self = .mention(did: did)
        case "app.bsky.richtext.facet#link":
            let uri = try container.decode(String.self, forKey: .uri)
            self = .link(uri: uri)
        case "app.bsky.richtext.facet#tag":
            let tag = try container.decode(String.self, forKey: .tag)
            self = .tag(tag: tag)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown facet type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .mention(did):
            try container.encode("app.bsky.richtext.facet#mention", forKey: .type)
            try container.encode(did, forKey: .did)
        case let .link(uri):
            try container.encode("app.bsky.richtext.facet#link", forKey: .type)
            try container.encode(uri, forKey: .uri)
        case let .tag(tag):
            try container.encode("app.bsky.richtext.facet#tag", forKey: .type)
            try container.encode(tag, forKey: .tag)
        }
    }
}

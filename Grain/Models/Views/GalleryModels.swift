import Foundation

/// social.grain.gallery.defs#galleryView
struct GrainGallery: Codable, Sendable, Identifiable {
    let uri: String
    let cid: String
    var title: String?
    var description: String?
    var cameras: [String]?
    var location: H3Location?
    var address: Address?
    var facets: [Facet]?
    let creator: GrainProfile
    var record: AnyCodable?
    var items: [GrainPhoto]?
    var favCount: Int?
    var commentCount: Int?
    var labels: [ATLabel]?
    var createdAt: String?
    let indexedAt: String
    var viewer: GalleryViewerState?
    var crossPost: CrossPostInfo?
    var labelRevealed: Bool = false

    var id: String {
        uri
    }

    private enum CodingKeys: String, CodingKey {
        case uri, cid, title, description, cameras, location, address, facets, creator, record, items, favCount, commentCount, labels, createdAt, indexedAt, viewer, crossPost
    }
}

/// social.grain.gallery.defs#viewerState
struct GalleryViewerState: Codable, Sendable {
    var fav: String?
}

/// social.grain.gallery.defs#crossPostInfo
struct CrossPostInfo: Codable, Sendable {
    let url: String
}

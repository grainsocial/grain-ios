import Foundation

/// social.grain.gallery record
struct GalleryRecord: Codable, Sendable {
    let title: String
    var description: String?
    var facets: [Facet]?
    var labels: SelfLabels?
    var location: H3Location?
    var address: Address?
    var updatedAt: String?
    let createdAt: String
}

/// social.grain.gallery.item record
struct GalleryItemRecord: Codable, Sendable {
    let createdAt: String
    let gallery: String
    let item: String
    var position: Int?
}

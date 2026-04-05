import Foundation

/// social.grain.comment.defs#commentView
struct GrainComment: Codable, Sendable, Identifiable {
    let uri: String
    let cid: String
    let author: GrainProfile
    var record: AnyCodable?
    let text: String
    var facets: [Facet]?
    var subject: AnyCodable?
    var focus: AnyCodable?
    var replyTo: String?
    let createdAt: String

    var id: String {
        uri
    }
}

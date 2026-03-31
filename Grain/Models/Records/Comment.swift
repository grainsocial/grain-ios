import Foundation

/// social.grain.comment record
struct CommentRecord: Codable, Sendable {
    let text: String
    var facets: [Facet]?
    let subject: String
    var focus: String?
    var replyTo: String?
    let createdAt: String
}

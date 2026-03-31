import Foundation

/// social.grain.favorite record
struct FavoriteRecord: Codable, Sendable {
    let createdAt: String
    let subject: String
}

/// social.grain.graph.follow record
struct FollowRecord: Codable, Sendable {
    let subject: String
    let createdAt: String
}

/// social.grain.actor.profile record
struct ActorProfileRecord: Codable, Sendable {
    var displayName: String?
    var description: String?
    var avatar: BlobRef?
    var createdAt: String?
}

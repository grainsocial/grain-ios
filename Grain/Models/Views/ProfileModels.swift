import Foundation

/// social.grain.actor.defs#profileView
struct GrainProfile: Codable, Sendable, Identifiable {
    let cid: String
    let did: String
    let handle: String
    var displayName: String?
    var description: String?
    var labels: [ATLabel]?
    var avatar: String?
    var createdAt: String?

    var id: String { did }
}

/// social.grain.actor.defs#profileViewDetailed
struct GrainProfileDetailed: Codable, Sendable, Identifiable {
    let cid: String
    let did: String
    let handle: String
    var displayName: String?
    var description: String?
    var avatar: String?
    var cameras: [String]?
    var followersCount: Int?
    var followsCount: Int?
    var galleryCount: Int?
    var indexedAt: String?
    var createdAt: String?
    var viewer: ActorViewerState?
    var labels: [ATLabel]?

    var id: String { did }
}

/// social.grain.actor.defs#viewerState
struct ActorViewerState: Codable, Sendable {
    var following: String?
    var followedBy: String?
}

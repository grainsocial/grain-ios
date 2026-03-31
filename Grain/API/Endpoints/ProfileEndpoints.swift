import Foundation

/// Response types for profile-related XRPC queries.

struct GetFollowersResponse: Codable, Sendable {
    var items: [FollowerItem]?
    var cursor: String?
}

struct GetFollowingResponse: Codable, Sendable {
    var items: [FollowingItem]?
    var cursor: String?
}

struct GetKnownFollowersResponse: Codable, Sendable {
    var items: [FollowerItem]?
}

struct GetSuggestedFollowsResponse: Codable, Sendable {
    var items: [SuggestedItem]?
}

struct SearchProfilesResponse: Codable, Sendable {
    var items: [ProfileSearchResult]?
    var cursor: String?
}

struct FollowerItem: Codable, Sendable, Identifiable {
    let did: String
    var handle: String?
    var displayName: String?
    var description: String?
    var avatar: String?
    var id: String { did }
}

struct FollowingItem: Codable, Sendable, Identifiable {
    let did: String
    var handle: String?
    var displayName: String?
    var description: String?
    var avatar: String?
    var id: String { did }
}

struct SuggestedItem: Codable, Sendable, Identifiable {
    let did: String
    var handle: String?
    var displayName: String?
    var description: String?
    var avatar: String?
    var followersCount: Int?
    var id: String { did }
}

struct ProfileSearchResult: Codable, Sendable, Identifiable {
    let did: String
    var handle: String?
    var displayName: String?
    var description: String?
    var avatar: String?
    var id: String { did }
}

// MARK: - Convenience Extensions

extension XRPCClient {
    func getActorProfile(actor: String, viewer: String? = nil, auth: AuthContext? = nil) async throws -> GrainProfileDetailed {
        var params = ["actor": actor]
        if let viewer { params["viewer"] = viewer }
        return try await query("social.grain.unspecced.getActorProfile", params: params, auth: auth, as: GrainProfileDetailed.self)
    }

    func getFollowers(actor: String, limit: Int = 50, cursor: String? = nil, auth: AuthContext? = nil) async throws -> GetFollowersResponse {
        var params = ["actor": actor, "limit": String(limit)]
        if let cursor { params["cursor"] = cursor }
        return try await query("social.grain.unspecced.getFollowers", params: params, auth: auth, as: GetFollowersResponse.self)
    }

    func getFollowing(actor: String, limit: Int = 50, cursor: String? = nil, auth: AuthContext? = nil) async throws -> GetFollowingResponse {
        var params = ["actor": actor, "limit": String(limit)]
        if let cursor { params["cursor"] = cursor }
        return try await query("social.grain.unspecced.getFollowing", params: params, auth: auth, as: GetFollowingResponse.self)
    }

    func getKnownFollowers(actor: String, viewer: String, auth: AuthContext? = nil) async throws -> GetKnownFollowersResponse {
        try await query("social.grain.unspecced.getKnownFollowers", params: ["actor": actor, "viewer": viewer], auth: auth, as: GetKnownFollowersResponse.self)
    }

    func getSuggestedFollows(actor: String, limit: Int = 10, auth: AuthContext? = nil) async throws -> GetSuggestedFollowsResponse {
        try await query("social.grain.unspecced.getSuggestedFollows", params: ["actor": actor, "limit": String(limit)], auth: auth, as: GetSuggestedFollowsResponse.self)
    }

    func searchProfiles(query q: String, limit: Int = 30, cursor: String? = nil, auth: AuthContext? = nil) async throws -> SearchProfilesResponse {
        var params = ["q": q, "limit": String(limit)]
        if let cursor { params["cursor"] = cursor }
        return try await self.query("social.grain.unspecced.searchProfiles", params: params, auth: auth, as: SearchProfilesResponse.self)
    }
}

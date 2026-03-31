import Foundation

/// Response types for feed-related XRPC queries.

struct GetFeedResponse: Codable, Sendable {
    var items: [GrainGallery]?
    var cursor: String?
}

struct GetGalleryResponse: Codable, Sendable {
    let gallery: GrainGallery
}

struct GetGalleryThreadResponse: Codable, Sendable {
    let comments: [GrainComment]
    var cursor: String?
    var totalCount: Int?
}

struct GetPreferencesResponse: Codable, Sendable {
    let preferences: UserPreferences
}

struct UserPreferences: Codable, Sendable {
    var pinnedFeeds: [PinnedFeed]?
    var includeExif: Bool?
}

struct PinnedFeed: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let label: String
    let type: String
    let path: String

    static let defaults: [PinnedFeed] = [
        PinnedFeed(id: "recent", label: "Recent", type: "feed", path: "/"),
        PinnedFeed(id: "following", label: "Following", type: "feed", path: "/feeds/following"),
    ]

    /// The feed name parameter for the API (e.g. "recent", "following", "camera", "location", "hashtag")
    var feedName: String {
        switch type {
        case "camera": "camera"
        case "location": "location"
        case "hashtag": "hashtag"
        default: id
        }
    }

    /// Extract the value part from the id (e.g. "Sony A7III" from "camera:Sony A7III")
    var feedValue: String? {
        guard id.contains(":") else { return nil }
        return String(id.split(separator: ":", maxSplits: 1).last ?? "")
    }
}

struct SearchGalleriesResponse: Codable, Sendable {
    var items: [GrainGallery]?
    var cursor: String?
}

// MARK: - Convenience Extensions

extension XRPCClient {
    func getFeed(
        feed: String,
        limit: Int = 30,
        cursor: String? = nil,
        actor: String? = nil,
        camera: String? = nil,
        location: String? = nil,
        tag: String? = nil,
        auth: AuthContext? = nil
    ) async throws -> GetFeedResponse {
        var params = ["feed": feed, "limit": String(limit)]
        if let cursor { params["cursor"] = cursor }
        if let actor { params["actor"] = actor }
        if let camera { params["camera"] = camera }
        if let location { params["location"] = location }
        if let tag { params["tag"] = tag }
        return try await query("dev.hatk.getFeed", params: params, auth: auth, as: GetFeedResponse.self)
    }

    func getPreferences(auth: AuthContext? = nil) async throws -> GetPreferencesResponse {
        try await query("dev.hatk.getPreferences", auth: auth, as: GetPreferencesResponse.self)
    }

    func getGallery(uri: String, auth: AuthContext? = nil) async throws -> GetGalleryResponse {
        try await query("social.grain.unspecced.getGallery", params: ["gallery": uri], auth: auth, as: GetGalleryResponse.self)
    }

    func getGalleryThread(
        gallery: String,
        limit: Int = 20,
        cursor: String? = nil,
        auth: AuthContext? = nil
    ) async throws -> GetGalleryThreadResponse {
        var params = ["gallery": gallery, "limit": String(limit)]
        if let cursor { params["cursor"] = cursor }
        return try await query("social.grain.unspecced.getGalleryThread", params: params, auth: auth, as: GetGalleryThreadResponse.self)
    }

    func searchGalleries(
        query q: String,
        limit: Int = 30,
        cursor: String? = nil,
        fuzzy: Bool = true,
        auth: AuthContext? = nil
    ) async throws -> SearchGalleriesResponse {
        var params = ["q": q, "limit": String(limit), "fuzzy": String(fuzzy)]
        if let cursor { params["cursor"] = cursor }
        return try await self.query("social.grain.unspecced.searchGalleries", params: params, auth: auth, as: SearchGalleriesResponse.self)
    }
}

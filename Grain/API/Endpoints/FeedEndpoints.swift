import Foundation

// Response types for feed-related XRPC queries.

struct GetFeedResponse: Codable, Sendable {
    var items: [GrainGallery]?
    var cursor: String?
}

struct GetGalleryResponse: Codable, Sendable {
    let gallery: GrainGallery
}

struct GetCommentThreadResponse: Codable, Sendable {
    let comments: [GrainComment]
    var cursor: String?
    var totalCount: Int?
}

struct GetPreferencesResponse: Codable, Sendable {
    let preferences: UserPreferences
}

struct NotifPref: Codable, Sendable {
    var push: Bool
    var inApp: Bool
    var from: String // "all" or "follows"

    static let `default` = NotifPref(push: true, inApp: true, from: "all")
}

struct NotificationPrefs: Codable, Sendable {
    var favorites: NotifPref?
    var follows: NotifPref?
    var comments: NotifPref?
    var mentions: NotifPref?

    static let `default` = NotificationPrefs(
        favorites: .default,
        follows: .default,
        comments: .default,
        mentions: .default
    )
}

struct UserPreferences: Codable, Sendable {
    var pinnedFeeds: [PinnedFeed]?
    var includeExif: Bool?
    var includeLocation: Bool?
    var notificationPrefs: NotificationPrefs?
}

struct PinnedFeed: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let label: String
    let type: String
    let path: String

    static let defaults: [PinnedFeed] = [
        PinnedFeed(id: "recent", label: "Recent", type: "feed", path: "/"),
        PinnedFeed(id: "following", label: "Following", type: "feed", path: "/feeds/following"),
        PinnedFeed(id: "foryou", label: "For You", type: "feed", path: "/feeds/for-you"),
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

    func getCommentThread(
        subject: String,
        limit: Int = 20,
        cursor: String? = nil,
        auth: AuthContext? = nil
    ) async throws -> GetCommentThreadResponse {
        var params = ["subject": subject, "limit": String(limit)]
        if let cursor { params["cursor"] = cursor }
        return try await query("social.grain.unspecced.getCommentThread", params: params, auth: auth, as: GetCommentThreadResponse.self)
    }

    func putPinnedFeeds(_ feeds: [PinnedFeed], auth: AuthContext? = nil) async throws {
        struct Input: Encodable {
            let key: String
            let value: [PinnedFeed]
        }
        try await procedure("dev.hatk.putPreference", input: Input(key: "pinnedFeeds", value: feeds), auth: auth)
    }

    func putIncludeExif(_ value: Bool, auth: AuthContext? = nil) async throws {
        struct Input: Encodable {
            let key: String
            let value: Bool
        }
        try await procedure("dev.hatk.putPreference", input: Input(key: "includeExif", value: value), auth: auth)
    }

    func putIncludeLocation(_ value: Bool, auth: AuthContext? = nil) async throws {
        struct Input: Encodable {
            let key: String
            let value: Bool
        }
        try await procedure("dev.hatk.putPreference", input: Input(key: "includeLocation", value: value), auth: auth)
    }

    func putNotificationPrefs(_ prefs: NotificationPrefs, auth: AuthContext? = nil) async throws {
        struct Input: Encodable {
            let key: String
            let value: NotificationPrefs
        }
        try await procedure("dev.hatk.putPreference", input: Input(key: "notificationPrefs", value: prefs), auth: auth)
    }

    func getActorFavorites(
        actor: String,
        limit: Int = 30,
        cursor: String? = nil,
        auth: AuthContext? = nil
    ) async throws -> GetFeedResponse {
        var params = ["actor": actor, "limit": String(limit)]
        if let cursor { params["cursor"] = cursor }
        return try await query("social.grain.unspecced.getActorFavorites", params: params, auth: auth, as: GetFeedResponse.self)
    }

    func searchGalleries(
        query queryString: String,
        limit: Int = 30,
        cursor: String? = nil,
        fuzzy: Bool = true,
        auth: AuthContext? = nil
    ) async throws -> SearchGalleriesResponse {
        var params = ["q": queryString, "limit": String(limit), "fuzzy": String(fuzzy)]
        if let cursor { params["cursor"] = cursor }
        return try await query("social.grain.unspecced.searchGalleries", params: params, auth: auth, as: SearchGalleriesResponse.self)
    }
}

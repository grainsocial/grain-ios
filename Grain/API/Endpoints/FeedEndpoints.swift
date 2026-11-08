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

struct PutPreferencesInput: Encodable, Sendable {
    let preferences: UserPreferences
}

struct NotifPref: Codable, Sendable, Equatable {
    var push: Bool
    var inApp: Bool
    var from: String // "all" or "follows"

    static let `default` = NotifPref(push: true, inApp: true, from: "all")
}

struct NotificationPrefs: Codable, Sendable, Equatable {
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

/// The viewer's grain preferences, `social.grain.actor.defs#preferences`:
/// on the wire an array holding each kind at most once, by its `$type`.
/// `theme` is the web's; the app keeps it so writing the set back leaves it
/// as it was.
struct UserPreferences: Codable, Sendable, Equatable {
    var pinnedFeeds: [PinnedFeed]?
    var includeExif: Bool?
    var includeLocation: Bool?
    var notificationPrefs: NotificationPrefs?
    var theme: String?

    static let pinnedFeedsType = "social.grain.actor.defs#pinnedFeedsPref"
    static let photoMetadataType = "social.grain.actor.defs#photoMetadataPref"
    static let notificationsType = "social.grain.actor.defs#notificationsPref"
    static let themeType = "social.grain.actor.defs#themePref"

    init(
        pinnedFeeds: [PinnedFeed]? = nil,
        includeExif: Bool? = nil,
        includeLocation: Bool? = nil,
        notificationPrefs: NotificationPrefs? = nil,
        theme: String? = nil
    ) {
        self.pinnedFeeds = pinnedFeeds
        self.includeExif = includeExif
        self.includeLocation = includeLocation
        self.notificationPrefs = notificationPrefs
        self.theme = theme
    }

    private enum Keys: String, CodingKey {
        case type = "$type"
        case items, includeExif, includeLocation, theme
    }

    /// One item of the array, whatever its kind, with the fields each kind
    /// has. A kind the app does not know decodes to nothing.
    private struct Item: Decodable {
        let type: String?
        let items: [PinnedFeed]?
        let includeExif: Bool?
        let includeLocation: Bool?
        let theme: String?
        let favorites: NotifPref?
        let follows: NotifPref?
        let comments: NotifPref?
        let mentions: NotifPref?

        private enum CodingKeys: String, CodingKey {
            case type = "$type"
            case items, includeExif, includeLocation, theme, favorites, follows, comments, mentions
        }
    }

    init(from decoder: Decoder) throws {
        self.init()
        for item in try [Item](from: decoder) {
            switch item.type {
            case Self.pinnedFeedsType:
                pinnedFeeds = item.items
            case Self.photoMetadataType:
                includeExif = item.includeExif
                includeLocation = item.includeLocation
            case Self.notificationsType:
                notificationPrefs = NotificationPrefs(
                    favorites: item.favorites,
                    follows: item.follows,
                    comments: item.comments,
                    mentions: item.mentions
                )
            case Self.themeType:
                theme = item.theme
            default:
                break
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var list = encoder.unkeyedContainer()
        if let pinnedFeeds {
            var item = list.nestedContainer(keyedBy: Keys.self)
            try item.encode(Self.pinnedFeedsType, forKey: .type)
            try item.encode(pinnedFeeds, forKey: .items)
        }
        if includeExif != nil || includeLocation != nil {
            var item = list.nestedContainer(keyedBy: Keys.self)
            try item.encode(Self.photoMetadataType, forKey: .type)
            try item.encodeIfPresent(includeExif, forKey: .includeExif)
            try item.encodeIfPresent(includeLocation, forKey: .includeLocation)
        }
        if let theme {
            var item = list.nestedContainer(keyedBy: Keys.self)
            try item.encode(Self.themeType, forKey: .type)
            try item.encode(theme, forKey: .theme)
        }
        if let notificationPrefs {
            try list.encode(TypedNotificationPrefs(prefs: notificationPrefs))
        }
    }
}

/// A `notificationsPref`: its kinds beside its `$type`.
private struct TypedNotificationPrefs: Encodable {
    let prefs: NotificationPrefs

    private enum Keys: String, CodingKey {
        case type = "$type"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(UserPreferences.notificationsType, forKey: .type)
        try prefs.encode(to: encoder)
    }
}

struct PinnedFeed: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let label: String
    let type: String
    let path: String

    static let defaults: [PinnedFeed] = [
        PinnedFeed(id: "recent", label: "Recent", type: "feed", path: "/"),
        PinnedFeed(id: "following", label: "Following", type: "feed", path: "/feeds/following"),
        PinnedFeed(id: "foryou", label: "For you", type: "feed", path: "/feeds/for-you"),
    ]

    /// The name of the feed it opens (e.g. "recent", "following", "camera", "location", "hashtag")
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
        // A place's display name, alongside `location`. The index folds
        // several cells into one place and counts across all of them; the
        // feed asked for one cell shows only that cell's galleries, so the
        // name is what makes the feed match the count. The appview unions
        // every cell sharing it.
        name: String? = nil,
        tag: String? = nil,
        auth: AuthContext? = nil
    ) async throws -> GetFeedResponse {
        var params = ["limit": String(limit)]
        if let cursor {
            params["cursor"] = cursor
        }
        if let actor {
            params["actor"] = actor
        }
        if let camera {
            params["camera"] = camera
        }
        if let location {
            params["location"] = location
        }
        if let name {
            params["name"] = name
        }
        if let tag {
            params["tag"] = tag
        }
        params["feed"] = Self.feedURI(feed)
        return try await query("social.grain.feed.getFeed", params: params, auth: auth, as: GetFeedResponse.self)
    }

    /// The URI grain-serve names its feed `name` by, as
    /// `social.grain.feed.describeFeeds` lists it.
    static func feedURI(_ name: String) -> String {
        "at://\(AuthManager.appviewDID)/social.grain.feed.generator/\(name)"
    }

    func getPreferences(auth: AuthContext? = nil) async throws -> GetPreferencesResponse {
        try await query("social.grain.actor.getPreferences", auth: auth, as: GetPreferencesResponse.self)
    }

    /// Replace the viewer's whole set of preferences.
    func putPreferences(_ preferences: UserPreferences, auth: AuthContext? = nil) async throws {
        try await procedure("social.grain.actor.putPreferences", input: PutPreferencesInput(preferences: preferences), auth: auth)
    }

    /// Change one kind of preference: the set is read, changed and written
    /// back whole, so the kinds left alone stay as they were.
    func updatePreferences(auth: AuthContext? = nil, _ change: (inout UserPreferences) -> Void) async throws {
        var preferences = try await getPreferences(auth: auth).preferences
        change(&preferences)
        try await putPreferences(preferences, auth: auth)
    }

    func getGallery(uri: String, auth: AuthContext? = nil) async throws -> GetGalleryResponse {
        try await query("social.grain.gallery.getGallery", params: ["gallery": uri], auth: auth, as: GetGalleryResponse.self)
    }

    func getCommentThread(
        subject: String,
        limit: Int = 20,
        cursor: String? = nil,
        auth: AuthContext? = nil
    ) async throws -> GetCommentThreadResponse {
        var params = ["subject": subject, "limit": String(limit)]
        if let cursor {
            params["cursor"] = cursor
        }
        return try await query("social.grain.comment.getThread", params: params, auth: auth, as: GetCommentThreadResponse.self)
    }

    func putPinnedFeeds(_ feeds: [PinnedFeed], auth: AuthContext? = nil) async throws {
        try await updatePreferences(auth: auth) { $0.pinnedFeeds = feeds }
    }

    func putIncludeExif(_ value: Bool, auth: AuthContext? = nil) async throws {
        try await updatePreferences(auth: auth) { $0.includeExif = value }
    }

    func putIncludeLocation(_ value: Bool, auth: AuthContext? = nil) async throws {
        try await updatePreferences(auth: auth) { $0.includeLocation = value }
    }

    func putNotificationPrefs(_ prefs: NotificationPrefs, auth: AuthContext? = nil) async throws {
        try await updatePreferences(auth: auth) { $0.notificationPrefs = prefs }
    }

    func getActorFavorites(
        actor: String,
        limit: Int = 30,
        cursor: String? = nil,
        auth: AuthContext? = nil
    ) async throws -> GetFeedResponse {
        var params = ["actor": actor, "limit": String(limit)]
        if let cursor {
            params["cursor"] = cursor
        }
        return try await query("social.grain.actor.getFavorites", params: params, auth: auth, as: GetFeedResponse.self)
    }

    func searchGalleries(
        query queryString: String,
        limit: Int = 30,
        cursor: String? = nil,
        fuzzy: Bool = true,
        auth: AuthContext? = nil
    ) async throws -> SearchGalleriesResponse {
        var params = ["q": queryString, "limit": String(limit), "fuzzy": String(fuzzy)]
        if let cursor {
            params["cursor"] = cursor
        }
        return try await query("social.grain.gallery.searchGalleries", params: params, auth: auth, as: SearchGalleriesResponse.self)
    }
}

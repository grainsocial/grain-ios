import Foundation

struct GetStoriesResponse: Codable, Sendable {
    let stories: [GrainStory]
}

struct GetStoryResponse: Codable, Sendable {
    var story: GrainStory?
}

struct GetStoryArchiveResponse: Codable, Sendable {
    let stories: [GrainStory]
    var cursor: String?
}

struct GetStoryAuthorsResponse: Codable, Sendable {
    let authors: [GrainStoryAuthor]
}

struct MarkStoriesViewedInput: Codable, Sendable {
    let stories: [String]
}

extension XRPCClient {
    func getStories(actor: String, auth: AuthContext? = nil) async throws -> GetStoriesResponse {
        try await query("social.grain.unspecced.getStories", params: ["actor": actor], auth: auth, as: GetStoriesResponse.self)
    }

    func getStory(uri: String, auth: AuthContext? = nil) async throws -> GetStoryResponse {
        try await query("social.grain.unspecced.getStory", params: ["story": uri], auth: auth, as: GetStoryResponse.self)
    }

    func getStoryArchive(actor: String, limit: Int = 50, cursor: String? = nil, auth: AuthContext? = nil) async throws -> GetStoryArchiveResponse {
        var params = ["actor": actor, "limit": String(limit)]
        if let cursor {
            params["cursor"] = cursor
        }
        return try await query("social.grain.unspecced.getStoryArchive", params: params, auth: auth, as: GetStoryArchiveResponse.self)
    }

    func getStoryAuthors(auth: AuthContext? = nil) async throws -> GetStoryAuthorsResponse {
        try await query("social.grain.unspecced.getStoryAuthors", auth: auth, as: GetStoryAuthorsResponse.self)
    }

    /// Tell the appview these stories were watched, so the web and Android
    /// see them as watched too. At most 100 per call.
    func markStoriesViewed(uris: [String], auth: AuthContext) async throws {
        try await procedure("social.grain.unspecced.markStoriesViewed", input: MarkStoriesViewedInput(stories: uris), auth: auth)
    }
}

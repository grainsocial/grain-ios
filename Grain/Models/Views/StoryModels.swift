import Foundation

/// social.grain.story.defs#storyView
struct GrainStory: Codable, Sendable, Identifiable {
    let uri: String
    let cid: String
    let creator: GrainProfile
    let thumb: String
    let fullsize: String
    let aspectRatio: AspectRatio
    var location: H3Location?
    var address: Address?
    var locationDisplay: String?
    let createdAt: String
    var labels: [ATLabel]?
    var expired: Bool?
    var crossPost: CrossPostInfo?
    var viewer: StoryViewerState?

    var id: String {
        uri
    }

    var storyUri: String {
        uri
    }
}

extension GrainStory: StoryIdentifiable {}

/// social.grain.story.defs#viewerState
struct StoryViewerState: Codable, Sendable {
    var fav: String?
    /// The appview's record of this account having watched the story. Only
    /// ever sent as true; absent means unwatched as far as the server knows.
    var viewed: Bool?
}

/// social.grain.unspecced.getStoryAuthors#storyAuthor
struct GrainStoryAuthor: Codable, Sendable, Identifiable {
    let profile: GrainProfile
    let storyCount: Int
    let latestAt: String
    /// createdAt of the newest live story this account has watched, as the
    /// appview has it. Absent when signed out or nothing has been watched.
    var lastViewedAt: String?
    /// Live stories this account has not watched, as the appview has it.
    var unviewedCount: Int?

    var id: String {
        profile.did
    }
}

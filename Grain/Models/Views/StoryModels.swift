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
    let createdAt: String
    var labels: [ATLabel]?
    var crossPost: CrossPostInfo?

    var id: String { uri }
    var storyUri: String { uri }
}

extension GrainStory: StoryIdentifiable {}

/// social.grain.unspecced.getStoryAuthors#storyAuthor
struct GrainStoryAuthor: Codable, Sendable, Identifiable {
    let profile: GrainProfile
    let storyCount: Int
    let latestAt: String

    var id: String { profile.did }
}

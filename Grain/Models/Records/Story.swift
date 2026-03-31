import Foundation

/// social.grain.story record
struct StoryRecord: Codable, Sendable {
    let media: BlobRef
    let aspectRatio: AspectRatio
    var location: H3Location?
    var address: Address?
    let createdAt: String
}

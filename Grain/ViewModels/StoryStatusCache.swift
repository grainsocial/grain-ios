import Foundation

@Observable
@MainActor
final class StoryStatusCache {
    private(set) var authorsByDid: [String: GrainStoryAuthor] = [:]

    var didsWithStories: Set<String> {
        Set(authorsByDid.keys)
    }

    func hasStory(for did: String) -> Bool {
        authorsByDid[did] != nil
    }

    func author(for did: String) -> GrainStoryAuthor? {
        authorsByDid[did]
    }

    func update(from authors: [GrainStoryAuthor]) {
        authorsByDid = Dictionary(uniqueKeysWithValues: authors.map { ($0.profile.did, $0) })
    }
}

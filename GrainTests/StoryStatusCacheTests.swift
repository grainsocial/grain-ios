import XCTest
@testable import Grain

@MainActor
final class StoryStatusCacheTests: XCTestCase {

    private func makeAuthor(did: String, storyCount: Int = 1) -> GrainStoryAuthor {
        GrainStoryAuthor(
            profile: GrainProfile(cid: "cid", did: did, handle: "\(did).test"),
            storyCount: storyCount,
            latestAt: "2024-06-15T12:00:00Z"
        )
    }

    // MARK: - update(from:)

    func testUpdatePopulatesCache() {
        let cache = StoryStatusCache()
        cache.update(from: [makeAuthor(did: "did:plc:alice"), makeAuthor(did: "did:plc:bob")])
        XCTAssertEqual(cache.authorsByDid.count, 2)
    }

    func testUpdateReplacesOldData() {
        let cache = StoryStatusCache()
        cache.update(from: [makeAuthor(did: "did:plc:alice", storyCount: 3)])
        cache.update(from: [makeAuthor(did: "did:plc:bob", storyCount: 1)])
        // After second update, alice should be gone
        XCTAssertNil(cache.author(for: "did:plc:alice"))
        XCTAssertNotNil(cache.author(for: "did:plc:bob"))
    }

    // MARK: - hasStory(for:)

    func testHasStoryReturnsTrue() {
        let cache = StoryStatusCache()
        cache.update(from: [makeAuthor(did: "did:plc:alice")])
        XCTAssertTrue(cache.hasStory(for: "did:plc:alice"))
    }

    func testHasStoryReturnsFalse() {
        let cache = StoryStatusCache()
        XCTAssertFalse(cache.hasStory(for: "did:plc:nobody"))
    }

    // MARK: - author(for:)

    func testAuthorReturnsCorrectAuthor() {
        let cache = StoryStatusCache()
        cache.update(from: [makeAuthor(did: "did:plc:alice", storyCount: 5)])
        let author = cache.author(for: "did:plc:alice")
        XCTAssertEqual(author?.storyCount, 5)
        XCTAssertEqual(author?.profile.handle, "did:plc:alice.test")
    }

    func testAuthorReturnsNilForUnknown() {
        let cache = StoryStatusCache()
        XCTAssertNil(cache.author(for: "did:plc:unknown"))
    }

    // MARK: - didsWithStories

    func testDidsWithStoriesReturnsCorrectSet() {
        let cache = StoryStatusCache()
        cache.update(from: [makeAuthor(did: "did:plc:a"), makeAuthor(did: "did:plc:b")])
        XCTAssertEqual(cache.didsWithStories, Set(["did:plc:a", "did:plc:b"]))
    }

    func testDidsWithStoriesEmptyByDefault() {
        let cache = StoryStatusCache()
        XCTAssertTrue(cache.didsWithStories.isEmpty)
    }
}

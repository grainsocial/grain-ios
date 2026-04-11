@testable import Grain
import XCTest

@MainActor
final class StoryStatusCacheTests: XCTestCase {
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Creates an author whose latest story was created `offset` seconds from now.
    /// Positive offset = future (not yet expired).
    /// Negative offset = past (expired if |offset| > 86400).
    private func makeAuthor(did: String, storyCount: Int = 1, latestAtOffset: TimeInterval = -3600) -> GrainStoryAuthor {
        let latestAt = Self.iso8601.string(from: Date().addingTimeInterval(latestAtOffset))
        return GrainStoryAuthor(
            profile: GrainProfile(cid: "cid", did: did, handle: "\(did).test"),
            storyCount: storyCount,
            latestAt: latestAt
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

    // MARK: - Expiry

    func testExpiredEntryNotVisibleViaHasStory() {
        let cache = StoryStatusCache()
        // latestAt was 25 hours ago — story expired 1 hour ago
        cache.update(from: [makeAuthor(did: "did:plc:alice", latestAtOffset: -90000)])
        XCTAssertFalse(cache.hasStory(for: "did:plc:alice"))
    }

    func testExpiredEntryNotVisibleViaAuthor() {
        let cache = StoryStatusCache()
        cache.update(from: [makeAuthor(did: "did:plc:alice", latestAtOffset: -90000)])
        XCTAssertNil(cache.author(for: "did:plc:alice"))
    }

    func testExpiredEntryExcludedFromAuthorsByDid() {
        let cache = StoryStatusCache()
        cache.update(from: [
            makeAuthor(did: "did:plc:fresh", latestAtOffset: -3600), // expires in 23h
            makeAuthor(did: "did:plc:stale", latestAtOffset: -90000), // expired 1h ago
        ])
        XCTAssertEqual(cache.authorsByDid.count, 1)
        XCTAssertNotNil(cache.authorsByDid["did:plc:fresh"])
    }

    func testExpiredEntryExcludedFromDidsWithStories() {
        let cache = StoryStatusCache()
        cache.update(from: [
            makeAuthor(did: "did:plc:fresh", latestAtOffset: -3600),
            makeAuthor(did: "did:plc:stale", latestAtOffset: -90000),
        ])
        XCTAssertEqual(cache.didsWithStories, Set(["did:plc:fresh"]))
    }

    func testPurgeExpiredRemovesStalePurgesEntries() {
        let cache = StoryStatusCache()
        cache.update(from: [
            makeAuthor(did: "did:plc:fresh", latestAtOffset: -3600),
            makeAuthor(did: "did:plc:stale", latestAtOffset: -90000),
        ])
        cache.purgeExpired()
        XCTAssertTrue(cache.hasStory(for: "did:plc:fresh"))
        XCTAssertFalse(cache.hasStory(for: "did:plc:stale"))
    }

    func testPurgeExpiredKeepsFreshEntries() {
        let cache = StoryStatusCache()
        cache.update(from: [makeAuthor(did: "did:plc:alice", latestAtOffset: -3600)])
        cache.purgeExpired()
        XCTAssertTrue(cache.hasStory(for: "did:plc:alice"))
        XCTAssertNotNil(cache.author(for: "did:plc:alice"))
    }
}

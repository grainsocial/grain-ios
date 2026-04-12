@testable import Grain
import XCTest

@MainActor
final class ViewedStoryStorageTests: XCTestCase {
    private var storage: ViewedStoryStorage!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "viewedStoryUris")
        UserDefaults.standard.removeObject(forKey: "viewedStoryAuthors")
        storage = ViewedStoryStorage()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "viewedStoryUris")
        UserDefaults.standard.removeObject(forKey: "viewedStoryAuthors")
        storage = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private struct StubStory: StoryIdentifiable {
        let storyUri: String
    }

    private func makeStories(_ uris: [String]) -> [StubStory] {
        uris.map { StubStory(storyUri: $0) }
    }

    // MARK: - markViewed / isViewed

    func testMarkViewedTracksUri() {
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z")
        XCTAssertTrue(storage.isViewed(uri: "at://story/1"))
        XCTAssertFalse(storage.isViewed(uri: "at://story/2"))
    }

    func testMarkViewedMultipleStories() {
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z")
        storage.markViewed(uri: "at://story/2", authorDid: "did:plc:alice", createdAt: "2024-06-15T13:00:00.000Z")
        XCTAssertTrue(storage.isViewed(uri: "at://story/1"))
        XCTAssertTrue(storage.isViewed(uri: "at://story/2"))
    }

    // MARK: - hasViewedAll

    func testHasViewedAllReturnsTrueWhenLatestViewed() {
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T14:00:00.000Z")
        XCTAssertTrue(storage.hasViewedAll(authorDid: "did:plc:alice", latestAt: "2024-06-15T14:00:00.000Z"))
    }

    func testHasViewedAllReturnsTrueWhenViewedNewer() {
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T15:00:00.000Z")
        XCTAssertTrue(storage.hasViewedAll(authorDid: "did:plc:alice", latestAt: "2024-06-15T14:00:00.000Z"))
    }

    func testHasViewedAllReturnsFalseWhenNotViewed() {
        XCTAssertFalse(storage.hasViewedAll(authorDid: "did:plc:alice", latestAt: "2024-06-15T14:00:00.000Z"))
    }

    func testHasViewedAllReturnsFalseWhenOlderViewed() {
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z")
        XCTAssertFalse(storage.hasViewedAll(authorDid: "did:plc:alice", latestAt: "2024-06-15T14:00:00.000Z"))
    }

    func testHasViewedAllTracksMostRecentTimestamp() {
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z")
        storage.markViewed(uri: "at://story/2", authorDid: "did:plc:alice", createdAt: "2024-06-15T14:00:00.000Z")
        // Viewing an older story doesn't regress the timestamp
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z")
        XCTAssertTrue(storage.hasViewedAll(authorDid: "did:plc:alice", latestAt: "2024-06-15T14:00:00.000Z"))
    }

    func testHasViewedAllIndependentPerAuthor() {
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T14:00:00.000Z")
        XCTAssertTrue(storage.hasViewedAll(authorDid: "did:plc:alice", latestAt: "2024-06-15T14:00:00.000Z"))
        XCTAssertFalse(storage.hasViewedAll(authorDid: "did:plc:bob", latestAt: "2024-06-15T14:00:00.000Z"))
    }

    // MARK: - firstUnviewedIndex

    func testFirstUnviewedIndexReturnsFirstUnviewed() {
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z")
        storage.markViewed(uri: "at://story/2", authorDid: "did:plc:alice", createdAt: "2024-06-15T13:00:00.000Z")
        let stories = makeStories(["at://story/1", "at://story/2", "at://story/3", "at://story/4"])
        XCTAssertEqual(storage.firstUnviewedIndex(in: stories), 2)
    }

    func testFirstUnviewedIndexReturnsZeroWhenNoneViewed() {
        let stories = makeStories(["at://story/1", "at://story/2", "at://story/3"])
        XCTAssertEqual(storage.firstUnviewedIndex(in: stories), 0)
    }

    func testFirstUnviewedIndexReturnsZeroWhenAllViewed() {
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z")
        storage.markViewed(uri: "at://story/2", authorDid: "did:plc:alice", createdAt: "2024-06-15T13:00:00.000Z")
        let stories = makeStories(["at://story/1", "at://story/2"])
        XCTAssertEqual(storage.firstUnviewedIndex(in: stories), 0)
    }

    func testFirstUnviewedIndexSkipsViewedInMiddle() {
        // Only the middle story is viewed — should return index 0
        storage.markViewed(uri: "at://story/2", authorDid: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z")
        let stories = makeStories(["at://story/1", "at://story/2", "at://story/3"])
        XCTAssertEqual(storage.firstUnviewedIndex(in: stories), 0)
    }

    func testFirstUnviewedIndexWithSingleStory() {
        let stories = makeStories(["at://story/1"])
        XCTAssertEqual(storage.firstUnviewedIndex(in: stories), 0)

        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z")
        XCTAssertEqual(storage.firstUnviewedIndex(in: stories), 0)
    }

    func testFirstUnviewedIndexEmptyArray() {
        let stories: [StubStory] = []
        XCTAssertEqual(storage.firstUnviewedIndex(in: stories), 0)
    }

    // MARK: - cleanup

    func testCleanupRemovesOldAuthorEntries() {
        storage.markViewed(uri: "at://story/old", authorDid: "did:plc:old", createdAt: "2020-01-01T12:00:00.000Z")
        storage.markViewed(uri: "at://story/new", authorDid: "did:plc:new", createdAt: "2099-01-01T12:00:00.000Z")
        storage.cleanup()
        XCTAssertFalse(storage.hasViewedAll(authorDid: "did:plc:old", latestAt: "2020-01-01T12:00:00.000Z"))
        XCTAssertTrue(storage.hasViewedAll(authorDid: "did:plc:new", latestAt: "2099-01-01T12:00:00.000Z"))
    }

    func testCleanupPreservesRecentAuthorEntries() {
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2099-06-15T12:00:00.000Z")
        storage.cleanup()
        XCTAssertTrue(storage.hasViewedAll(authorDid: "did:plc:alice", latestAt: "2099-06-15T12:00:00.000Z"))
    }

    func testCleanupCapsViewedUrisWhenOver500() {
        for i in 0 ..< 600 {
            storage.markViewed(uri: "at://story/\(i)", authorDid: "did:plc:alice", createdAt: "2099-01-01T12:00:00.000Z")
        }
        storage.cleanup()
        // After cleanup, total viewed URIs should be capped — at least some should no longer be tracked
        let stillViewedCount = (0 ..< 600).count(where: { storage.isViewed(uri: "at://story/\($0)") })
        XCTAssertLessThanOrEqual(stillViewedCount, 200)
    }
}

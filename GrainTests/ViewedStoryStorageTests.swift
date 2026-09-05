@testable import Grain
import XCTest

@MainActor
final class ViewedStoryStorageTests: GrainTestCase {
    private var storage: ViewedStoryStorage!
    /// Watch history is stored per account, and the test host shares
    /// UserDefaults with the app on the simulator — so pin these to a DID
    /// nobody is signed in as.
    private let testDID = "did:plc:viewedstoragetests"

    override func setUp() {
        super.setUp()
        AccountScopedStorage.purge(did: testDID)
        storage = ViewedStoryStorage(did: testDID)
    }

    override func tearDown() {
        AccountScopedStorage.purge(did: testDID)
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

    // MARK: - Server state

    private func author(_ did: String, latestAt: String, lastViewedAt: String? = nil) -> GrainStoryAuthor {
        GrainStoryAuthor(
            profile: GrainProfile(cid: "", did: did, handle: "\(did).test"),
            storyCount: 1,
            latestAt: latestAt,
            lastViewedAt: lastViewedAt
        )
    }

    private func story(_ uri: String, by did: String, createdAt: String, viewed: Bool?) -> GrainStory {
        GrainStory(
            uri: uri,
            cid: "cid",
            creator: GrainProfile(cid: "", did: did, handle: "\(did).test"),
            thumb: "",
            fullsize: "",
            aspectRatio: AspectRatio(width: 9, height: 16),
            createdAt: createdAt,
            viewer: viewed.map { StoryViewerState(fav: nil, viewed: $0) }
        )
    }

    func testAbsorbingAuthorsMovesTheMarkForward() {
        storage.absorb(authors: [author("did:plc:alice", latestAt: "2024-06-15T14:00:00.000Z", lastViewedAt: "2024-06-15T14:00:00.000Z")])
        XCTAssertTrue(storage.hasViewedAll(authorDid: "did:plc:alice", latestAt: "2024-06-15T14:00:00.000Z"))
    }

    func testAbsorbingAuthorsNeverMovesTheMarkBack() {
        storage.markViewed(uri: "at://story/2", authorDid: "did:plc:alice", createdAt: "2024-06-15T14:00:00.000Z")
        storage.absorb(authors: [author("did:plc:alice", latestAt: "2024-06-15T14:00:00.000Z", lastViewedAt: "2024-06-15T12:00:00.000Z")])
        XCTAssertTrue(storage.hasViewedAll(authorDid: "did:plc:alice", latestAt: "2024-06-15T14:00:00.000Z"))
    }

    func testAbsorbingAuthorsWithoutAMarkChangesNothing() {
        storage.absorb(authors: [author("did:plc:alice", latestAt: "2024-06-15T14:00:00.000Z")])
        XCTAssertFalse(storage.hasViewedAll(authorDid: "did:plc:alice", latestAt: "2024-06-15T14:00:00.000Z"))
        XCTAssertEqual(storage.pendingUploadCount, 0)
    }

    func testAbsorbingStoriesMarksTheFlaggedOnes() {
        storage.absorb(stories: [
            story("at://story/1", by: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z", viewed: true),
            story("at://story/2", by: "did:plc:alice", createdAt: "2024-06-15T13:00:00.000Z", viewed: nil),
        ])
        XCTAssertTrue(storage.isViewed(uri: "at://story/1"))
        XCTAssertFalse(storage.isViewed(uri: "at://story/2"))
        XCTAssertEqual(storage.firstUnviewedIndex(in: makeStories(["at://story/1", "at://story/2"])), 1)
        XCTAssertFalse(storage.hasViewedAll(authorDid: "did:plc:alice", latestAt: "2024-06-15T13:00:00.000Z"))
        // Nothing the server told us about goes back up to it.
        XCTAssertEqual(storage.pendingUploadCount, 0)
    }

    // MARK: - Reporting to the appview

    func testWatchedStoriesAreReportedInOneBatch() async {
        var sent: [[String]] = []
        storage.uploader = { uris in sent.append(uris.sorted()) }
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z")
        storage.markViewed(uri: "at://story/2", authorDid: "did:plc:alice", createdAt: "2024-06-15T13:00:00.000Z")
        XCTAssertEqual(storage.pendingUploadCount, 2)

        await storage.flushPending()

        XCTAssertEqual(sent, [["at://story/1", "at://story/2"]])
        XCTAssertEqual(storage.pendingUploadCount, 0)
    }

    func testAFailedReportStaysQueued() async {
        struct Offline: Error {}
        storage.uploader = { _ in throw Offline() }
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z")

        await storage.flushPending()

        XCTAssertEqual(storage.pendingUploadCount, 1)
        XCTAssertTrue(storage.isViewed(uri: "at://story/1"), "Locally it is still watched")

        var sent: [String] = []
        storage.uploader = { uris in sent = uris }
        await storage.flushPending()
        XCTAssertEqual(sent, ["at://story/1"])
        XCTAssertEqual(storage.pendingUploadCount, 0)
    }

    func testTheQueueSurvivesARelaunch() {
        storage.markViewed(uri: "at://story/1", authorDid: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z")
        storage.cleanup() // saves synchronously
        let relaunched = ViewedStoryStorage(did: testDID)
        XCTAssertEqual(relaunched.pendingUploadCount, 1)
    }

    func testReportsGoUpInServerSizedBatches() async {
        var batches: [Int] = []
        storage.uploader = { uris in batches.append(uris.count) }
        for i in 0 ..< 150 {
            storage.markViewed(uri: "at://story/\(i)", authorDid: "did:plc:alice", createdAt: "2024-06-15T12:00:00.000Z")
        }
        await storage.flushPending()
        XCTAssertEqual(batches, [100, 50])
        XCTAssertEqual(storage.pendingUploadCount, 0)
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

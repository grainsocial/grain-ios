@testable import Grain
import XCTest

/// Relative, not a literal: `StoryStatusCache` expires a story 24 hours after
/// `latestAt`, so a hardcoded date turns these into time bombs. File scope
/// because a default argument can't reference the enclosing type.
private let recently = DateFormatting.nowISO(date: Date().addingTimeInterval(-3600))

/// The strip only exists when someone has posted, so its job is mostly
/// filtering: authors whose stories have all expired must not leave an empty
/// ring behind, and a failed load must leave the strip absent rather than
/// broken.
@MainActor
final class StoryStripViewModelTests: GrainTestCase {
    private var client: XRPCClient!
    private var vm: StoryStripViewModel!

    override func setUp() async throws {
        try await super.setUp()
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        vm = StoryStripViewModel(client: client)
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try await super.tearDown()
    }

    private func authorJSON(did: String, storyCount: Int, latestAt: String = recently) -> String {
        """
        {
          "profile": {"cid": "c-\(did)", "did": "\(did)", "handle": "\(did).test"},
          "storyCount": \(storyCount),
          "latestAt": "\(latestAt)"
        }
        """
    }

    func testLoadPopulatesTheStrip() async {
        MockURLProtocol.respondWithJSON("""
        {"authors": [\(authorJSON(did: "did:plc:a", storyCount: 2))]}
        """)

        await vm.load()

        XCTAssertEqual(vm.authors.map(\.id), ["did:plc:a"])
        XCTAssertEqual(vm.authors.first?.storyCount, 2)
        XCTAssertFalse(vm.isLoading)
    }

    /// The appview keeps returning an author for a while after their last story
    /// goes, with a count of zero. Showing them would put an empty ring in the
    /// strip that opens onto nothing.
    func testAuthorsWithNoStoriesLeftAreDropped() async {
        MockURLProtocol.respondWithJSON("""
        {"authors": [
          \(authorJSON(did: "did:plc:a", storyCount: 0)),
          \(authorJSON(did: "did:plc:b", storyCount: 1))
        ]}
        """)

        await vm.load()

        XCTAssertEqual(vm.authors.map(\.id), ["did:plc:b"])
    }

    func testAFailedLoadLeavesTheStripEmptyAndNotLoading() async {
        MockURLProtocol.respondWithError(statusCode: 500)

        await vm.load()

        XCTAssertTrue(vm.authors.isEmpty)
        XCTAssertFalse(vm.isLoading, "A failure must clear the loading flag or the skeleton never goes away")
    }

    /// Loading also primes the shared cache the profile and feed rings read, so
    /// a story ring appears without those screens making their own request.
    func testLoadingAlsoFillsTheSharedStoryStatusCache() async {
        MockURLProtocol.respondWithJSON("""
        {"authors": [
          \(authorJSON(did: "did:plc:a", storyCount: 2)),
          \(authorJSON(did: "did:plc:b", storyCount: 0))
        ]}
        """)
        let cache = StoryStatusCache()

        await vm.load(storyStatusCache: cache)

        XCTAssertTrue(cache.hasStory(for: "did:plc:a"))
        XCTAssertFalse(cache.hasStory(for: "did:plc:b"), "A zero-story author shouldn't get a ring anywhere")
    }

    /// The cache holds authors the strip itself filtered out of view, so a
    /// failure must not wipe what an earlier successful load put there.
    func testAFailedLoadLeavesThePreviouslyCachedStatusAlone() async {
        MockURLProtocol.respondWithJSON("""
        {"authors": [\(authorJSON(did: "did:plc:a", storyCount: 2))]}
        """)
        let cache = StoryStatusCache()
        await vm.load(storyStatusCache: cache)

        MockURLProtocol.respondWithError(statusCode: 503)
        await vm.load(storyStatusCache: cache)

        XCTAssertTrue(cache.hasStory(for: "did:plc:a"))
    }

    /// Sorting depends on viewed state, which changes without the author list
    /// changing — so there has to be something else for the view to observe.
    func testInvalidateBumpsTheVersionWithoutTouchingTheAuthors() async {
        MockURLProtocol.respondWithJSON("""
        {"authors": [\(authorJSON(did: "did:plc:a", storyCount: 1))]}
        """)
        await vm.load()
        let before = vm.version

        vm.invalidate()
        vm.invalidate()

        XCTAssertEqual(vm.version, before + 2)
        XCTAssertEqual(vm.authors.map(\.id), ["did:plc:a"])
    }

    func testASecondLoadReplacesRatherThanAppends() async {
        MockURLProtocol.respondWithJSON("""
        {"authors": [\(authorJSON(did: "did:plc:a", storyCount: 1))]}
        """)
        await vm.load()

        MockURLProtocol.respondWithJSON("""
        {"authors": [\(authorJSON(did: "did:plc:b", storyCount: 1))]}
        """)
        await vm.load()

        XCTAssertEqual(vm.authors.map(\.id), ["did:plc:b"])
    }
}

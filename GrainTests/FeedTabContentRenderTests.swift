@testable import Grain
import SwiftUI
import XCTest

/// One tab's worth of feed. `FeedView` is little more than a switcher over
/// these, so the cards, the story strip, the suggested-follows block and the
/// paging footer all live here rather than in the parent.
@MainActor
final class FeedTabContentRenderTests: GrainTestCase {
    private var account: TestAccount!

    /// Async overrides: the synchronous `setUp`/`tearDown` are nonisolated, so
    /// touching main-actor state from them warns.
    override func setUp() async throws {
        try await super.setUp()
        account = TestAccount()
        MockURLProtocol.respondByPath(Fixtures.routes)
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        account.restore()
        try await super.tearDown()
    }

    private let settle: TimeInterval = 0.35

    private func renderTab(
        _ feed: PinnedFeed,
        env: TestEnvironment,
        withStories: Bool = false
    ) {
        let authors = withStories
            ? [GrainStoryAuthor(
                profile: GrainProfile(cid: "c1", did: "did:plc:test", handle: "tester.grain.social"),
                storyCount: 2,
                latestAt: Fixtures.freshTimestamp
            )]
            : []

        ViewRender.render(
            FeedTabContent(
                client: env.client,
                pinnedFeed: feed,
                userDID: env.auth.userDID,
                storyAuthors: authors,
                userAvatar: "https://test.local/avatar.jpg",
                onStoryAuthorTap: { _, _ in },
                onStoryCreateTap: {},
                onRefresh: {},
                prefsViewModel: FeedPreferencesViewModel(client: env.client)
            )
            .withTestEnvironment(env),
            settle: settle
        )
    }

    // MARK: - Feed tab content

    /// One tab's worth of feed, which is where the cards, the story strip and
    /// the suggested-follows block all live.
    func testRendersATabOfFeedForEachPinnedFeed() {
        let env = TestEnvironment()

        for feed in PinnedFeed.defaults {
            renderTab(feed, env: env)
        }
        // With a story strip above it, which is its own row of chrome.
        renderTab(PinnedFeed.defaults[0], env: env, withStories: true)
    }

    /// A camera or hashtag feed carries a value in its id, which the tab has to
    /// pull apart to build its request.
    func testRendersATabOfFeedForACameraAndAHashtag() {
        let env = TestEnvironment()
        let feeds = [
            PinnedFeed(id: "camera:Leica M6", label: "Leica M6", type: "camera", path: "/c/leica"),
            PinnedFeed(id: "hashtag:film", label: "#film", type: "hashtag", path: "/t/film"),
            PinnedFeed(id: "location:8a2a1072b59ffff", label: "Lisboa", type: "location", path: "/l/lisboa"),
        ]

        for feed in feeds {
            renderTab(feed, env: env)
        }
    }

    func testRendersATabOfFeedWhenItFailsToLoad() {
        MockURLProtocol.respondWithError(statusCode: 500)
        let env = TestEnvironment()

        renderTab(PinnedFeed.defaults[0], env: env)
    }

    func testRendersATabOfFeedWhenEmpty() {
        MockURLProtocol.respondByPath(["getFeed": #"{"items": [], "cursor": null}"#], fallback: "{}")
        let env = TestEnvironment()

        renderTab(PinnedFeed.defaults[0], env: env)
    }

    /// Suggested follows only appear on an empty following feed, and only when
    /// the privacy toggle allows them.
    func testRendersATabOfFeedWithSuggestedFollowsTurnedOff() {
        let key = "privacy.showSuggestedUsers"
        let saved = StorageEnvironment.defaults.object(forKey: key) as? Bool
        defer {
            if let saved {
                StorageEnvironment.defaults.set(saved, forKey: key)
            } else {
                StorageEnvironment.defaults.removeObject(forKey: key)
            }
        }
        StorageEnvironment.defaults.set(false, forKey: key)

        let env = TestEnvironment()
        renderTab(PinnedFeed.defaults[1], env: env)
    }

    /// Signed out the feed still renders, without any of the actions that need
    /// an account.
    func testRendersATabOfFeedWhileSignedOut() {
        let env = TestEnvironment(authenticated: false)

        renderTab(PinnedFeed.defaults[0], env: env)
    }

    // MARK: - Loading footers

    /// The footer is what tells you another page is on the way; with nothing in
    /// flight it must add no height at all.
    func testTheFeedFooterOnlyShowsWhileLoading() {
        let env = TestEnvironment()
        let viewModel = FeedViewModel(client: env.client, feedName: "recent")

        let idle = UIHostingController(rootView: FeedLoadingFooter(viewModel: viewModel))
            .sizeThatFits(in: CGSize(width: 402, height: 200))

        viewModel.isLoading = true
        let busy = UIHostingController(rootView: FeedLoadingFooter(viewModel: viewModel))
            .sizeThatFits(in: CGSize(width: 402, height: 200))

        XCTAssertLessThan(idle.height, busy.height)
    }

    /// The profile feed's footer also gates on whether that particular source
    /// has more to fetch, so a loading galleries tab shouldn't spin the
    /// favorites tab's footer.
    func testTheProfileFeedFooterShowsOnlyForTheSourceStillLoading() {
        let env = TestEnvironment()
        let viewModel = ProfileDetailViewModel(client: env.client)

        func height(_ source: ProfileGalleryFeedSource) -> CGFloat {
            UIHostingController(rootView: ProfileFeedLoadingFooter(viewModel: viewModel, source: source))
                .sizeThatFits(in: CGSize(width: 402, height: 200))
                .height
        }

        let idle = height(.galleries)
        viewModel.isLoading = true
        let busy = height(.galleries)

        XCTAssertLessThan(idle, busy)
        ViewRender.render(ProfileFeedLoadingFooter(viewModel: viewModel, source: .favorites), settle: 0)
    }
}

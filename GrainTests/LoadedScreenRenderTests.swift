@testable import Grain
import SwiftUI
import XCTest

/// Every screen rendered against a full set of endpoint fixtures, so it settles
/// on its *loaded* state.
///
/// The earlier render suites served one canned body to every request, which
/// meant all but one endpoint failed to decode and each screen ended up on its
/// error branch — the populated layouts, the rows, and the per-item chrome were
/// never reached. `Fixtures.routes` answers each endpoint with a payload of the
/// right shape instead.
@MainActor
final class LoadedScreenRenderTests: GrainTestCase {
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

    /// Loaded screens need a beat for the fetch to land and the body to
    /// re-evaluate with content.
    private let settle: TimeInterval = 0.35

    // MARK: - Feed

    func testRendersALoadedFeed() {
        let env = TestEnvironment()
        ViewRender.render(FeedView(client: env.client).withTestEnvironment(env), settle: settle)
    }

    func testRendersALoadedFeedWithStoriesAboveIt() {
        let env = TestEnvironment()
        env.storyStatus.update(from: [
            GrainStoryAuthor(
                profile: GrainProfile(cid: "c1", did: "did:plc:test", handle: "tester.grain.social"),
                storyCount: 2,
                latestAt: Fixtures.freshTimestamp
            ),
        ])
        ViewRender.render(FeedView(client: env.client).withTestEnvironment(env), settle: settle)
    }

    func testRendersTheLoadedHashtagAndLocationAndCameraFeeds() {
        let env = TestEnvironment()
        ViewRender.render(
            HashtagFeedView(client: env.client, tag: "film").withTestEnvironment(env), settle: settle
        )
        ViewRender.render(
            LocationFeedView(client: env.client, h3Index: "8a2a1072b59ffff", locationName: "Lisboa")
                .withTestEnvironment(env),
            settle: settle
        )
        ViewRender.render(
            CameraFeedView(client: env.client, camera: "Leica M6").withTestEnvironment(env), settle: settle
        )
    }

    // MARK: - Profile

    func testRendersALoadedOwnProfile() {
        let env = TestEnvironment()
        ViewRender.render(
            ProfileView(client: env.client, did: "did:plc:test", isRoot: true).withTestEnvironment(env),
            settle: settle
        )
    }

    func testRendersALoadedProfileForSomeoneElse() {
        let env = TestEnvironment()
        ViewRender.render(
            ProfileView(client: env.client, did: "did:plc:other", isRoot: false).withTestEnvironment(env),
            settle: settle
        )
    }

    /// Someone with a story gets a ring around their avatar and a tappable one
    /// at that, which is a branch a story-less profile never reaches.
    func testRendersALoadedProfileForSomeoneWithAStory() {
        let env = TestEnvironment()
        env.storyStatus.update(from: [
            GrainStoryAuthor(
                profile: GrainProfile(cid: "c1", did: "did:plc:other", handle: "other.test"),
                storyCount: 3,
                latestAt: Fixtures.freshTimestamp
            ),
        ])
        ViewRender.render(
            ProfileView(client: env.client, did: "did:plc:other", isRoot: false).withTestEnvironment(env),
            settle: settle
        )
    }

    func testRendersALoadedProfileGalleryFeedForEachSource() {
        let env = TestEnvironment()
        for source in [ProfileGalleryFeedSource.galleries, .favorites] {
            ViewRender.render(
                ProfileGalleryFeedView(
                    viewModel: ProfileDetailViewModel(client: env.client),
                    client: env.client,
                    did: "did:plc:test",
                    initialUri: "at://did:plc:test/social.grain.gallery/1",
                    source: source
                )
                .withTestEnvironment(env),
                settle: settle
            )
        }
    }

    // MARK: - Follow lists

    /// Each mode hits a different endpoint and draws a different title; with
    /// people in the list the rows and their follow buttons render too.
    func testRendersEachFollowListWithPeopleInIt() {
        let env = TestEnvironment()
        let modes: [FollowListMode] = [
            .followers,
            .following,
            .knownFollowers,
            .galleryFavorites("at://did:plc:test/social.grain.gallery/1"),
        ]

        for mode in modes {
            ViewRender.render(
                FollowListView(client: env.client, did: "did:plc:test", mode: mode).withTestEnvironment(env),
                settle: settle
            )
        }
    }

    /// Viewing your own follower list adds the actions you only get on your own
    /// account.
    func testRendersYourOwnFollowerList() {
        let env = TestEnvironment(did: "did:plc:a")
        ViewRender.render(
            FollowListView(client: env.client, did: "did:plc:a", mode: .followers).withTestEnvironment(env),
            settle: settle
        )
    }

    // MARK: - Moderation lists

    func testRendersTheBlockAndMuteListsWithPeopleInThem() {
        let env = TestEnvironment()
        ViewRender.render(BlockedUsersView(client: env.client).withTestEnvironment(env), settle: settle)
        ViewRender.render(MutedUsersView(client: env.client).withTestEnvironment(env), settle: settle)
    }

    // MARK: - Notifications

    func testRendersLoadedNotifications() {
        let env = TestEnvironment()
        ViewRender.render(
            NotificationsView(client: env.client, viewModel: NotificationsViewModel(client: env.client))
                .withTestEnvironment(env),
            settle: settle
        )
    }

    // MARK: - Settings

    func testRendersLoadedSettings() {
        let env = TestEnvironment()
        env.auth.accounts = [
            StoredAccount(did: "did:plc:test", handle: "tester.grain.social", avatar: "https://test.local/a.jpg"),
            StoredAccount(did: "did:plc:other", handle: "other.test", avatar: nil),
        ]
        env.auth.userHandle = "tester.grain.social"
        env.auth.userAvatar = "https://test.local/a.jpg"

        ViewRender.render(SettingsView(client: env.client).withTestEnvironment(env), settle: settle)
    }

    func testRendersLoadedNotificationSettings() {
        let env = TestEnvironment()
        ViewRender.render(
            NotificationSettingsView(client: env.client).withTestEnvironment(env), settle: settle
        )
    }

    func testRendersLoadedModerationSettings() {
        let env = TestEnvironment()
        ViewRender.render(ModerationView(client: env.client).withTestEnvironment(env), settle: settle)
    }

    func testRendersLoadedEditProfile() {
        let env = TestEnvironment()
        ViewRender.render(EditProfileView(client: env.client).withTestEnvironment(env), settle: settle)
    }

    // MARK: - Feeds management

    func testRendersLoadedFeedsManagement() {
        let env = TestEnvironment()
        let prefs = FeedPreferencesViewModel(client: env.client)
        ViewRender.render(
            FeedsManagementView(prefsViewModel: prefs, client: env.client).withTestEnvironment(env),
            settle: settle
        )
    }

    // MARK: - Search

    /// The discovery lists — locations and cameras — are what the search tab
    /// shows before anything is typed.
    func testRendersSearchWithItsDiscoveryLists() {
        let env = TestEnvironment()
        ViewRender.render(SearchView(client: env.client).withTestEnvironment(env), settle: settle)
    }

    /// With history on the account the tab shows the recents list instead of
    /// the empty placeholder.
    func testRendersSearchWithRecentHistory() {
        let did = AccountScopedStorage.activeAccountID
        let recents = RecentSearchStorage(did: did)
        let hadHistory = !recents.profiles.isEmpty || !recents.textSearches.isEmpty
        recents.addTextSearch("portra")
        recents.addProfile(did: "did:plc:a", displayName: "Alpha", handle: "alpha.test", avatar: nil)
        defer {
            if !hadHistory {
                recents.clearAll()
            }
        }

        let env = TestEnvironment()
        ViewRender.render(SearchView(client: env.client).withTestEnvironment(env), settle: settle)
    }

    // MARK: - Gallery detail

    func testRendersALoadedGalleryDetail() {
        let env = TestEnvironment()
        ViewRender.render(
            GalleryDetailView(client: env.client, galleryUri: "at://did:plc:test/social.grain.gallery/1")
                .withTestEnvironment(env),
            settle: settle
        )
    }

    func testRendersALoadedGalleryCommentSheet() {
        let env = TestEnvironment()
        ViewRender.render(
            CommentSheetView(client: env.client, galleryUri: "at://did:plc:test/social.grain.gallery/1")
                .withTestEnvironment(env),
            settle: settle
        )
    }

    // MARK: - Stories

    func testRendersALoadedStoryViewer() {
        let env = TestEnvironment()
        let author = GrainStoryAuthor(
            profile: GrainProfile(cid: "c1", did: "did:plc:test", handle: "tester.grain.social", displayName: "Tester"),
            storyCount: 2,
            latestAt: Fixtures.freshTimestamp
        )

        ViewRender.render(
            StoryViewer(authors: [author], client: env.client).withTestEnvironment(env),
            settle: 0.5
        )
    }

    /// A story the viewer owns gets the author's own controls; someone else's
    /// gets the reporting ones.
    func testRendersAStoryViewerForSomeoneElsesStory() {
        let env = TestEnvironment()
        let author = GrainStoryAuthor(
            profile: GrainProfile(cid: "c2", did: "did:plc:other", handle: "other.test", displayName: "Other"),
            storyCount: 1,
            latestAt: Fixtures.freshTimestamp
        )

        ViewRender.render(
            StoryViewer(authors: [author], startAuthorDid: "did:plc:other", client: env.client)
                .withTestEnvironment(env),
            settle: 0.5
        )
    }

    func testRendersTheStoryStripWithLiveAuthors() {
        let env = TestEnvironment()
        let authors = [
            GrainStoryAuthor(
                profile: GrainProfile(cid: "c1", did: "did:plc:test", handle: "tester.grain.social"),
                storyCount: 2, latestAt: Fixtures.freshTimestamp
            ),
            GrainStoryAuthor(
                profile: GrainProfile(cid: "c2", did: "did:plc:other", handle: "other.test"),
                storyCount: 1, latestAt: Fixtures.freshTimestamp
            ),
        ]
        // One author already watched, so both ring states render.
        env.viewedStories.markViewed(
            uri: "at://did:plc:other/social.grain.story/1",
            authorDid: "did:plc:other",
            createdAt: Fixtures.freshTimestamp
        )

        ViewRender.render(
            StoryStripView(
                authors: authors,
                userDid: "did:plc:test",
                userAvatar: "https://test.local/avatar.jpg",
                onAuthorTap: { _, _ in },
                onAuthorLongPress: { _ in },
                onCreateTap: {}
            )
            .withTestEnvironment(env),
            settle: settle
        )
    }

    // MARK: - Whole tab tree

    /// The signed-in tree with every tab's content resolving, which is as close
    /// to a cold launch as a render test gets.
    func testRendersTheWholeTabTreeLoaded() {
        let env = TestEnvironment()
        ViewRender.render(
            MainTabView(pendingDeepLink: .constant(nil)).withTestEnvironment(env), settle: 0.6
        )
    }

    /// Opening the app on a link puts the tab tree straight into a pushed
    /// destination.
    func testRendersTheTabTreeOpenedOnADeepLink() {
        let env = TestEnvironment()
        for link in [
            DeepLink.profile(did: "did:plc:other"),
            .gallery(did: "did:plc:test", rkey: "1"),
            .story(did: "did:plc:test", rkey: "1"),
        ] {
            ViewRender.render(
                MainTabView(pendingDeepLink: .constant(link)).withTestEnvironment(env), settle: 0.4
            )
        }
    }
}

@testable import Grain
import SwiftUI
import XCTest

/// What a screen shows when the server has nothing to give it, or nothing at
/// all to say.
///
/// The rest of the render suites drive screens against a healthy server, so the
/// "no galleries yet" and "that didn't work" branches — which is what someone
/// on a bad connection or a brand new account actually sees — went unexercised.
@MainActor
final class EmptyAndFailedStateRenderTests: GrainTestCase {
    private var account: TestAccount!

    /// Async overrides: the synchronous `setUp`/`tearDown` are nonisolated, so
    /// touching main-actor state from them warns.
    override func setUp() async throws {
        try await super.setUp()
        account = TestAccount()
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        account.restore()
        try await super.tearDown()
    }

    private let settle: TimeInterval = 0.4

    /// Everything answers, but with nothing in it.
    private func respondEmpty() {
        MockURLProtocol.respondByPath([
            "getFeed": #"{"items": [], "cursor": null}"#,
            "searchGalleries": #"{"items": [], "cursor": null}"#,
            "getCommentThread": #"{"comments": [], "cursor": null}"#,
            "getStoryAuthors": #"{"authors": []}"#,
            "getStoryArchive": #"{"stories": [], "cursor": null}"#,
            "getStories": #"{"stories": []}"#,
            "getNotifications": #"{"notifications": [], "cursor": null}"#,
            "getBlocks": #"{"items": [], "cursor": null}"#,
            "getMutes": #"{"items": [], "cursor": null}"#,
            "getFollowers": #"{"items": [], "cursor": null}"#,
            "getFollowing": #"{"items": [], "cursor": null}"#,
            "getKnownFollowers": #"{"items": []}"#,
            "getGalleryFavorites": #"{"items": [], "cursor": null}"#,
            "getSuggestedFollows": #"{"items": []}"#,
            "getLocations": #"{"locations": []}"#,
            "getCameras": #"{"cameras": []}"#,
            "getActorProfile": Fixtures.profileDetailed,
            "getGallery": Fixtures.galleryResponse,
        ], fallback: "{}")
    }

    // MARK: - Failures

    /// Every screen with a fetch, against a server that is refusing.
    func testEveryScreenRendersWhenEverythingFails() {
        MockURLProtocol.respondWithError(statusCode: 503)
        let env = TestEnvironment()

        ViewRender.render(FeedView(client: env.client).withTestEnvironment(env), settle: settle)
        ViewRender.render(SearchView(client: env.client).withTestEnvironment(env), settle: settle)
        ViewRender.render(SettingsView(client: env.client).withTestEnvironment(env), settle: settle)
        ViewRender.render(EditProfileView(client: env.client).withTestEnvironment(env), settle: settle)
        ViewRender.render(ModerationView(client: env.client).withTestEnvironment(env), settle: settle)
        ViewRender.render(BlockedUsersView(client: env.client).withTestEnvironment(env), settle: settle)
        ViewRender.render(MutedUsersView(client: env.client).withTestEnvironment(env), settle: settle)
        ViewRender.render(NotificationSettingsView(client: env.client).withTestEnvironment(env), settle: settle)
        ViewRender.render(StoryCreateView(client: env.client).withTestEnvironment(env), settle: settle)
    }

    func testEveryFeedRendersWhenItsFetchFails() {
        MockURLProtocol.respondWithError(statusCode: 500)
        let env = TestEnvironment()

        ViewRender.render(
            HashtagFeedView(client: env.client, tag: "film").withTestEnvironment(env), settle: settle
        )
        ViewRender.render(
            CameraFeedView(client: env.client, camera: "Leica M6").withTestEnvironment(env), settle: settle
        )
        ViewRender.render(
            LocationFeedView(client: env.client, h3Index: "8a2a1072b59ffff", locationName: "Lisboa")
                .withTestEnvironment(env),
            settle: settle
        )
        ViewRender.render(
            ProfileGalleryFeedView(
                viewModel: ProfileDetailViewModel(client: env.client),
                client: env.client,
                did: "did:plc:test",
                initialUri: "at://did:plc:test/social.grain.gallery/1",
                source: .galleries
            )
            .withTestEnvironment(env),
            settle: settle
        )
        ViewRender.render(
            GalleryDetailView(client: env.client, galleryUri: "at://did:plc:test/social.grain.gallery/1")
                .withTestEnvironment(env),
            settle: settle
        )
        for mode in [FollowListMode.followers, .following, .knownFollowers] {
            ViewRender.render(
                FollowListView(client: env.client, did: "did:plc:test", mode: mode).withTestEnvironment(env),
                settle: settle
            )
        }
    }

    // MARK: - Empty

    /// The same screens against a server that answers with nothing — which is
    /// a different branch again from a failure.
    func testEveryScreenRendersWithNothingToShow() {
        respondEmpty()
        let env = TestEnvironment()

        ViewRender.render(FeedView(client: env.client).withTestEnvironment(env), settle: settle)
        ViewRender.render(SearchView(client: env.client).withTestEnvironment(env), settle: settle)
        ViewRender.render(BlockedUsersView(client: env.client).withTestEnvironment(env), settle: settle)
        ViewRender.render(MutedUsersView(client: env.client).withTestEnvironment(env), settle: settle)
        ViewRender.render(
            HashtagFeedView(client: env.client, tag: "film").withTestEnvironment(env), settle: settle
        )
        ViewRender.render(
            CameraFeedView(client: env.client, camera: "Leica M6").withTestEnvironment(env), settle: settle
        )
        ViewRender.render(
            LocationFeedView(client: env.client, h3Index: "8a2a1072b59ffff", locationName: "Lisboa")
                .withTestEnvironment(env),
            settle: settle
        )
    }

    /// A profile with nothing posted, on each of its tabs.
    func testAnEmptyProfileRendersOnEveryTab() {
        respondEmpty()
        let env = TestEnvironment()

        for mode in ProfileViewMode.allCases {
            ViewRender.render(
                ProfileView(client: env.client, did: "did:plc:test", isRoot: true, viewMode: mode)
                    .withTestEnvironment(env),
                settle: settle
            )
        }
    }

    /// Someone else's profile, where the "followed by" row and the follow
    /// button live.
    func testSomeoneElsesProfileRendersOnEveryTab() {
        MockURLProtocol.respondByPath(Fixtures.routes)
        let env = TestEnvironment()

        for mode in ProfileViewMode.allCases {
            ViewRender.render(
                ProfileView(client: env.client, did: "did:plc:other", isRoot: false, viewMode: mode)
                    .withTestEnvironment(env),
                settle: 0.6
            )
        }
    }
}

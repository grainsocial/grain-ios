@testable import Grain
import SwiftUI
import XCTest

/// The list, management and moderation screens. Each was entirely unexercised;
/// most are a loading state, a loaded list and an empty state, so they are
/// rendered across those branches rather than just once.
@MainActor
final class ListViewRenderTests: XCTestCase {
    private var account: TestAccount!

    /// Async overrides: the synchronous `setUp`/`tearDown` are nonisolated, so
    /// touching main-actor state from them warns.
    override func setUp() async throws {
        try await super.setUp()
        account = TestAccount()
        MockURLProtocol.interceptSharedSession()
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        MockURLProtocol.stopInterceptingSharedSession()
        account.restore()
        try await super.tearDown()
    }

    private static let followers = """
    {"items": [{"subject": \(Fixtures.profile), "followedBy": null}], "cursor": null}
    """

    // MARK: - Follow lists

    func testRendersEachFollowListMode() {
        MockURLProtocol.respondWithJSON(Self.followers)
        let env = TestEnvironment()
        let modes: [FollowListMode] = [
            .followers,
            .following,
            .knownFollowers,
            .galleryFavorites("at://did:plc:test/social.grain.gallery/1"),
        ]

        for mode in modes {
            ViewRender.render(
                FollowListView(client: env.client, did: "did:plc:test", mode: mode)
                    .withTestEnvironment(env)
            )
        }
    }

    func testRendersFollowListWhenEmpty() {
        MockURLProtocol.respondWithJSON(#"{"items": [], "cursor": null}"#)
        let env = TestEnvironment()

        ViewRender.render(
            FollowListView(client: env.client, did: "did:plc:test", mode: .followers)
                .withTestEnvironment(env)
        )
    }

    // MARK: - Feed management

    func testRendersFeedsManagement() {
        MockURLProtocol.respondWithJSON(#"{"feeds": [], "cursor": null}"#)
        let env = TestEnvironment()
        ViewRender.render(
            FeedsManagementView(
                prefsViewModel: FeedPreferencesViewModel(client: env.client),
                client: env.client
            )
            .withTestEnvironment(env)
        )
    }

    // MARK: - Hashtag and profile gallery feeds

    func testRendersHashtagFeed() {
        MockURLProtocol.respondWithJSON(Fixtures.feed)
        let env = TestEnvironment()
        ViewRender.render(
            HashtagFeedView(client: env.client, tag: "film").withTestEnvironment(env)
        )
    }

    func testRendersProfileGalleryFeedForEachSource() {
        MockURLProtocol.respondWithJSON(Fixtures.feed)
        let env = TestEnvironment()

        for source in [ProfileGalleryFeedSource.galleries, .favorites] {
            let vm = ProfileDetailViewModel(client: env.client)
            ViewRender.render(
                ProfileGalleryFeedView(
                    viewModel: vm,
                    client: env.client,
                    did: "did:plc:test",
                    initialUri: "at://did:plc:test/social.grain.gallery/1",
                    source: source
                )
                .withTestEnvironment(env)
            )
        }
    }

    // MARK: - Moderation

    func testRendersReportView() {
        MockURLProtocol.respondWithJSON("{}")
        let env = TestEnvironment()

        ViewRender.render(
            ReportView(
                client: env.client,
                subjectUri: "at://did:plc:test/social.grain.gallery/1",
                subjectCid: "bafygallery"
            )
            .withTestEnvironment(env)
        )
    }

    func testRendersBlockedUsers() {
        MockURLProtocol.respondWithJSON(#"{"items": [], "cursor": null}"#)
        let env = TestEnvironment()
        ViewRender.render(BlockedUsersView(client: env.client).withTestEnvironment(env))
    }

    func testRendersMutedUsers() {
        MockURLProtocol.respondWithJSON(#"{"items": [], "cursor": null}"#)
        let env = TestEnvironment()
        ViewRender.render(MutedUsersView(client: env.client).withTestEnvironment(env))
    }

    func testRendersModerationView() {
        MockURLProtocol.respondWithJSON("{}")
        let env = TestEnvironment()
        ViewRender.render(ModerationView(client: env.client).withTestEnvironment(env))
    }

    // MARK: - Settings leaves

    func testRendersNotificationSettings() {
        MockURLProtocol.respondWithJSON("{}")
        let env = TestEnvironment()
        ViewRender.render(NotificationSettingsView(client: env.client).withTestEnvironment(env))
    }

    // MARK: - Suggestions

    func testRendersSuggestedFollows() {
        MockURLProtocol.respondWithJSON("{}")
        let env = TestEnvironment()
        var suggestions = [
            SuggestedItem(did: "did:plc:a", handle: "a.test", displayName: "A", followersCount: 3),
            SuggestedItem(did: "did:plc:b", handle: "b.test", displayName: "B", followersCount: 9),
        ]

        ViewRender.render(
            SuggestedFollowsView(
                client: env.client,
                suggestions: Binding(get: { suggestions }, set: { suggestions = $0 })
            )
            .withTestEnvironment(env)
        )
    }

    // MARK: - Chrome and placeholders

    func testRendersProfileSkeleton() {
        ViewRender.render(ProfileSkeletonView(showsTabBar: true), settle: 0)
        ViewRender.render(ProfileSkeletonView(showsTabBar: false), settle: 0)
    }

    func testRendersContentWarningOverlayForEachAction() {
        for action in [LabelAction.warnMedia, .warnContent, .badge, .hide] {
            ViewRender.render(
                ContentWarningOverlay(name: "nudity", action: action, onReveal: {}),
                settle: 0
            )
        }
    }

    /// Reads the label definitions out of the environment, so it needs the same
    /// ancestors the app gives it.
    func testRendersContentLabelPicker() {
        let env = TestEnvironment()
        var selected: Set = ["nudity"]
        ViewRender.render(
            ContentLabelPicker(
                selectedLabels: Binding(get: { selected }, set: { selected = $0 })
            )
            .withTestEnvironment(env),
            settle: 0
        )
    }

    func testRendersCaptionsListPrototype() {
        ViewRender.render(CaptionsListPrototype(), settle: 0)
    }
}

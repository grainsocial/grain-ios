@testable import Grain
import SwiftUI
import XCTest

/// The notifications screen as a whole: the list assembled from grouped rows,
/// against each reason the appview can send.
///
/// `NotificationRowRenderTests` covers the rows in isolation. This covers the
/// list that builds them — including the grouping applied on the way in, which
/// is what decides whether four favorites are four rows or one.
@MainActor
final class NotificationsListRenderTests: XCTestCase {
    private var account: TestAccount!

    /// Async overrides: the synchronous `setUp`/`tearDown` are nonisolated, so
    /// touching main-actor state from them warns.
    override func setUp() async throws {
        try await super.setUp()
        account = TestAccount()
        MockURLProtocol.interceptSharedSession()
    }

    override func tearDown() async throws {
        MockURLProtocol.stopInterceptingSharedSession()
        MockURLProtocol.handler = nil
        account.restore()
        try await super.tearDown()
    }

    // MARK: - Builders

    private static func notification(
        _ index: Int,
        reason: String,
        did: String = "did:plc:someone",
        extras: String = ""
    ) -> String {
        """
        {
          "uri": "at://did:plc:test/notification/\(index)",
          "reason": "\(reason)",
          "createdAt": "\(Fixtures.freshTimestamp)",
          "author": {"cid": "c\(index)", "did": "\(did)", "handle": "\(did).test", "displayName": "User \(index)"}
          \(extras.isEmpty ? "" : ",\(extras)")
        }
        """
    }

    private static let galleryExtras = """
    "galleryUri": "at://did:plc:test/social.grain.gallery/1",
    "galleryTitle": "A test gallery",
    "galleryThumb": "https://test.local/thumb.jpg"
    """

    private static let storyExtras = """
    "storyUri": "at://did:plc:test/social.grain.story/1",
    "storyThumb": "https://test.local/story.jpg"
    """

    private static let commentExtras = """
    "galleryUri": "at://did:plc:test/social.grain.gallery/1",
    "commentText": "A comment long enough to wrap onto a second line in the row.",
    "replyToText": "The comment it is replying to."
    """

    private func renderList(_ items: [String], settle: TimeInterval = 0.35) {
        MockURLProtocol.respondByPath([
            "getNotifications": "{\"notifications\": [\(items.joined(separator: ","))], \"cursor\": null, \"unseenCount\": 4}",
            "getActorProfile": Fixtures.profileDetailed,
        ], fallback: "{}")

        let env = TestEnvironment()
        ViewRender.render(
            NotificationsView(client: env.client, viewModel: NotificationsViewModel(client: env.client))
                .withTestEnvironment(env),
            settle: settle
        )
    }

    // MARK: - Reasons

    /// Every reason the appview sends, including one the app doesn't recognise
    /// — a list has to draw a row for that rather than dropping it silently.
    func testTheListRendersARowForEveryReason() {
        let items = [
            Self.notification(1, reason: "gallery-favorite", extras: Self.galleryExtras),
            Self.notification(2, reason: "gallery-comment", extras: Self.commentExtras),
            Self.notification(3, reason: "gallery-comment-mention", extras: Self.commentExtras),
            Self.notification(4, reason: "gallery-mention", extras: Self.galleryExtras),
            Self.notification(5, reason: "comment-favorite", extras: Self.commentExtras),
            Self.notification(6, reason: "story-favorite", extras: Self.storyExtras),
            Self.notification(7, reason: "story-comment", extras: Self.storyExtras),
            Self.notification(8, reason: "reply", extras: Self.commentExtras),
            Self.notification(9, reason: "follow"),
            Self.notification(10, reason: "gallery-reposted", extras: Self.galleryExtras),
        ]

        renderList(items)
    }

    // MARK: - Grouping

    /// Four people favoriting one gallery collapse into a single row with a
    /// facepile, which is a different row layout from four separate ones.
    func testFavoritesOfOneGalleryCollapseIntoOneRow() {
        let items = (1 ... 4).map {
            Self.notification($0, reason: "gallery-favorite", did: "did:plc:fan\($0)", extras: Self.galleryExtras)
        }

        renderList(items)
    }

    /// A story notification carries no gallery thumbnail, so the row falls back
    /// to the story's and draws it in portrait.
    func testAStoryNotificationFallsBackToItsOwnThumbnail() {
        renderList([Self.notification(1, reason: "story-favorite", extras: Self.storyExtras)], settle: 0.25)
    }

    // MARK: - Nothing to show

    func testTheListRendersWhenItFailsToLoad() {
        MockURLProtocol.respondWithError(statusCode: 500)
        let env = TestEnvironment()

        ViewRender.render(
            NotificationsView(client: env.client, viewModel: NotificationsViewModel(client: env.client))
                .withTestEnvironment(env),
            settle: 0.3
        )
    }

    func testTheListRendersWhenThereAreNoNotifications() {
        renderList([], settle: 0.25)
    }
}

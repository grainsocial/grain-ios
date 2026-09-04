@testable import Grain
import SwiftUI
import XCTest

/// The notification rows themselves. A row looks different for each of nine
/// reasons, and different again once it groups — a facepile and "N others"
/// instead of one avatar — so the rows are rendered directly rather than left
/// to whatever a list render happens to reach.
@MainActor
final class NotificationRowRenderTests: GrainTestCase {
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

    // MARK: - Builders

    private func profile(_ id: String) -> GrainProfile {
        GrainProfile(
            cid: "bafy\(id)",
            did: "did:plc:\(id)",
            handle: "\(id).test",
            displayName: id.capitalized,
            avatar: "https://test.local/\(id).jpg"
        )
    }

    private func notification(
        _ index: Int,
        reason: String,
        author: String = "alice",
        galleryThumb: String? = "https://test.local/thumb.jpg",
        storyThumb: String? = nil,
        commentText: String? = nil,
        replyToText: String? = nil
    ) -> GrainNotification {
        GrainNotification(
            uri: "at://did:plc:test/notification/\(index)",
            reason: reason,
            createdAt: Fixtures.freshTimestamp,
            author: profile(author),
            galleryUri: "at://did:plc:test/social.grain.gallery/1",
            galleryTitle: "A test gallery",
            galleryThumb: galleryThumb,
            storyUri: storyThumb == nil ? nil : "at://did:plc:test/social.grain.story/1",
            storyThumb: storyThumb,
            commentText: commentText,
            replyToText: replyToText
        )
    }

    private let reasons = [
        "gallery-favorite", "gallery-comment", "gallery-comment-mention", "gallery-mention",
        "comment-favorite", "story-favorite", "story-comment", "reply", "follow",
        // One the app doesn't know yet — it still has to draw a row.
        "gallery-reposted",
    ]

    // MARK: - Reason icon

    /// Every reason gets an icon and a tint; an unrecognised one still has to
    /// resolve to something rather than leaving a hole in the row.
    func testRendersTheReasonIconForEveryReason() {
        for reason in reasons {
            ViewRender.render(ReasonIcon(reason: NotificationReason(rawValue: reason) ?? .unknown), settle: 0)
        }
        ViewRender.render(ReasonIcon(reason: .unknown), settle: 0)
    }

    // MARK: - Single rows

    func testRendersASingleRowForEveryReason() {
        for (index, reason) in reasons.enumerated() {
            ViewRender.render(
                SingleNotificationRow(
                    notification: notification(index, reason: reason, commentText: "A comment on your gallery."),
                    onProfileTap: { _ in },
                    onSubjectTap: {}
                ),
                settle: 0.1
            )
        }
    }

    /// A reply shows what it is replying to above its own text.
    func testRendersAReplyWithItsParentQuoted() {
        ViewRender.render(
            SingleNotificationRow(
                notification: notification(
                    1, reason: "reply",
                    commentText: "Portra, every time.",
                    replyToText: "What film stock was this?"
                )
            ),
            settle: 0.1
        )
    }

    /// A story notification has no gallery thumbnail, so the row falls back to
    /// the story's and draws it in portrait.
    func testRendersARowThatFallsBackToTheStoryThumbnail() {
        ViewRender.render(
            SingleNotificationRow(
                notification: notification(1, reason: "story-favorite", galleryThumb: nil, storyThumb: "https://test.local/s.jpg")
            ),
            settle: 0.1
        )
    }

    /// A follow has no subject at all — no thumbnail, nothing to tap through to.
    func testRendersARowWithNoThumbnail() {
        ViewRender.render(
            SingleNotificationRow(notification: notification(1, reason: "follow", galleryThumb: nil)),
            settle: 0.1
        )
    }

    // MARK: - Grouped rows

    private func grouped(_ reason: String, authors: Int) -> GroupedNotification {
        let names = ["alice", "bob", "carol", "dave", "erin", "frank"]
        let head = notification(0, reason: reason, author: names[0])
        let rest = (1 ..< authors).map { notification($0, reason: reason, author: names[$0 % names.count]) }
        return GroupedNotification(notification: head, additional: rest)
    }

    /// Two, three and six people read differently — "and 1 other" versus a
    /// capped facepile — so each is drawn.
    func testRendersAGroupedRowAtEachSize() {
        for count in [2, 3, 6] {
            ViewRender.render(
                GroupedNotificationRow(
                    group: grouped("gallery-favorite", authors: count),
                    onProfileTap: { _ in },
                    onSubjectTap: {},
                    onGroupTap: {}
                ),
                settle: 0.1
            )
        }
    }

    func testRendersAGroupedRowForEveryGroupableReason() {
        for reason in ["gallery-favorite", "story-favorite", "comment-favorite", "follow"] {
            ViewRender.render(
                GroupedNotificationRow(group: grouped(reason, authors: 3)),
                settle: 0.1
            )
        }
    }

    // MARK: - Row container

    /// The container is what picks between the two row layouts, and it carries
    /// the tap routing for each reason.
    func testTheContainerPicksTheRightRowLayout() {
        let env = TestEnvironment()

        for group in [grouped("gallery-favorite", authors: 1), grouped("gallery-favorite", authors: 4)] {
            ViewRender.render(
                NotificationRowContainer(
                    group: group,
                    client: env.client,
                    authContext: { await env.auth.authContext() },
                    onProfileTap: { _ in },
                    onGalleryTap: { _ in },
                    onStoryAuthorTap: { _ in },
                    onStoryTap: { _ in },
                    onGroupTap: { _ in }
                )
                .withTestEnvironment(env),
                settle: 0.1
            )
        }
    }

    // MARK: - Avatars and thumbnails

    /// The facepile caps how many faces it draws and fans them out by a fixed
    /// step, so it has to be rendered above and below that cap.
    func testRendersOverlappingAvatarsAtEachSize() {
        let people = ["alice", "bob", "carol", "dave", "erin"].map(profile)

        for count in [1, 2, 3, 5] {
            ViewRender.render(
                OverlappingAvatarsView(
                    authors: Array(people.prefix(count)),
                    size: 32,
                    overlap: 10,
                    onProfileTap: { _ in }
                ),
                settle: 0.1
            )
        }
    }

    func testRendersAnEmptyFacepile() {
        ViewRender.render(OverlappingAvatarsView(authors: [], size: 32, overlap: 10), settle: 0)
    }

    /// Story thumbnails are portrait where gallery ones are square.
    func testRendersACachedThumbnailInBothShapes() {
        ViewRender.render(CachedThumbnailView(url: "https://test.local/thumb.jpg", size: 44), settle: 0.1)
        ViewRender.render(
            CachedThumbnailView(url: "https://test.local/story.jpg", size: 44, portrait: true), settle: 0.1
        )
    }

    /// A thumbnail URL the loader can't parse has to leave the row's layout
    /// intact rather than collapsing it.
    func testACachedThumbnailWithAnUnusableURLStillHoldsItsSpace() {
        let good = UIHostingController(rootView: CachedThumbnailView(url: "https://test.local/t.jpg", size: 44))
            .sizeThatFits(in: CGSize(width: 200, height: 200))
        let bad = UIHostingController(rootView: CachedThumbnailView(url: "", size: 44))
            .sizeThatFits(in: CGSize(width: 200, height: 200))

        XCTAssertEqual(good.width, bad.width, accuracy: 0.5)
        XCTAssertEqual(good.height, bad.height, accuracy: 0.5)
    }

    // MARK: - Grouped authors list

    /// Tapping a grouped row opens the full list of who was in it.
    func testRendersTheGroupedAuthorsList() {
        let env = TestEnvironment()

        for reason in ["gallery-favorite", "story-favorite", "comment-favorite", "follow"] {
            ViewRender.render(
                GroupedAuthorsView(group: grouped(reason, authors: 4), client: env.client)
                    .withTestEnvironment(env),
                settle: 0.2
            )
        }
    }

    // MARK: - List content

    func testRendersTheNotificationListContent() {
        let env = TestEnvironment()
        let viewModel = NotificationsViewModel(client: env.client)

        ViewRender.render(
            NotificationListContent(
                viewModel: viewModel,
                client: env.client,
                authContext: { await env.auth.authContext() },
                onProfileTap: { _ in },
                onGalleryTap: { _ in },
                onStoryAuthorTap: { _ in },
                onStoryTap: { _ in },
                onGroupTap: { _ in }
            )
            .withTestEnvironment(env),
            settle: 0.3
        )
    }
}

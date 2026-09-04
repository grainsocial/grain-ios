@testable import Grain
import XCTest

/// Grouping is what keeps the notifications tab from being twenty identical
/// "someone favorited your gallery" rows. It collapses on three axes at once —
/// same reason, same subject, within two days — and only for the reasons that
/// read sensibly in the plural.
@MainActor
final class NotificationGroupingTests: XCTestCase {
    // MARK: - Builders

    private func profile(_ id: String) -> GrainProfile {
        GrainProfile(cid: "bafy\(id)", did: "did:plc:\(id)", handle: "\(id).test", displayName: id.capitalized)
    }

    /// `GroupedNotification` parses with fractional seconds, so timestamps have
    /// to carry them or every notification lands on the same instant.
    private func timestamp(hoursAfterEpoch hours: Double) -> String {
        let date = Date(timeIntervalSince1970: hours * 3600)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func notification(
        _ id: String,
        reason: String,
        author: String,
        gallery: String? = "at://did:plc:me/social.grain.gallery/1",
        story: String? = nil,
        hours: Double = 0
    ) -> GrainNotification {
        GrainNotification(
            uri: "at://did:plc:me/notification/\(id)",
            reason: reason,
            createdAt: timestamp(hoursAfterEpoch: hours),
            author: profile(author),
            galleryUri: gallery,
            storyUri: story
        )
    }

    // MARK: - Reason parsing

    func testEveryWireReasonMapsToACase() {
        let pairs: [(String, NotificationReason)] = [
            ("gallery-favorite", .galleryFavorite),
            ("gallery-comment", .galleryComment),
            ("gallery-comment-mention", .galleryCommentMention),
            ("gallery-mention", .galleryMention),
            ("comment-favorite", .commentFavorite),
            ("story-favorite", .storyFavorite),
            ("story-comment", .storyComment),
            ("reply", .reply),
            ("follow", .follow),
        ]
        for (wire, expected) in pairs {
            XCTAssertEqual(notification("1", reason: wire, author: "a").reasonType, expected)
        }
    }

    /// A reason the server adds later must not crash the tab.
    func testAnUnrecognisedReasonFallsBackToUnknown() {
        XCTAssertEqual(notification("1", reason: "gallery-reposted", author: "a").reasonType, .unknown)
        XCTAssertFalse(NotificationReason.unknown.isGroupable)
    }

    func testOnlyTheCountableReasonsGroup() {
        for reason in [NotificationReason.galleryFavorite, .storyFavorite, .commentFavorite, .follow] {
            XCTAssertTrue(reason.isGroupable, "\(reason) reads as a count and should group")
        }
        for reason in [NotificationReason.galleryComment, .reply, .galleryMention, .galleryCommentMention, .storyComment] {
            XCTAssertFalse(reason.isGroupable, "\(reason) carries its own text and must stay on its own row")
        }
    }

    // MARK: - group

    func testFavoritesOfTheSameGalleryCollapseIntoOneRow() {
        let groups = GroupedNotification.group([
            notification("1", reason: "gallery-favorite", author: "alice"),
            notification("2", reason: "gallery-favorite", author: "bob"),
            notification("3", reason: "gallery-favorite", author: "carol"),
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].isGrouped)
        XCTAssertEqual(groups[0].authorCount, 3)
        XCTAssertEqual(groups[0].allAuthors.map(\.did), ["did:plc:alice", "did:plc:bob", "did:plc:carol"])
    }

    /// The row is identified by the notification it was seeded from, so the
    /// first one has to stay the head.
    func testTheGroupKeepsTheFirstNotificationAsItsHead() {
        let head = notification("1", reason: "gallery-favorite", author: "alice")
        let groups = GroupedNotification.group([
            head,
            notification("2", reason: "gallery-favorite", author: "bob"),
        ])

        XCTAssertEqual(groups[0].notification.uri, head.uri)
        XCTAssertEqual(groups[0].id, head.uri)
    }

    func testFavoritesOfDifferentGalleriesStayApart() {
        let groups = GroupedNotification.group([
            notification("1", reason: "gallery-favorite", author: "alice", gallery: "at://g/1"),
            notification("2", reason: "gallery-favorite", author: "bob", gallery: "at://g/2"),
        ])

        XCTAssertEqual(groups.count, 2)
        XCTAssertFalse(groups[0].isGrouped)
    }

    func testAFavoriteAndACommentOnTheSameGalleryStayApart() {
        let groups = GroupedNotification.group([
            notification("1", reason: "gallery-favorite", author: "alice"),
            notification("2", reason: "gallery-comment", author: "bob"),
        ])

        XCTAssertEqual(groups.count, 2)
    }

    /// Two comments read as two separate things to go and read, so they never
    /// collapse even when everything else matches.
    func testCommentsOnTheSameGalleryEachKeepTheirOwnRow() {
        let groups = GroupedNotification.group([
            notification("1", reason: "gallery-comment", author: "alice"),
            notification("2", reason: "gallery-comment", author: "bob"),
        ])

        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { !$0.isGrouped })
    }

    /// Someone appearing twice in one group's facepile would read as two
    /// different people.
    func testAPersonIsNeverCountedTwiceWithinAGroup() {
        let groups = GroupedNotification.group([
            notification("1", reason: "gallery-favorite", author: "alice"),
            notification("2", reason: "gallery-favorite", author: "bob"),
            notification("3", reason: "gallery-favorite", author: "bob"),
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].authorCount, 2)
        XCTAssertEqual(groups[0].allAuthors.map(\.did), ["did:plc:alice", "did:plc:bob"])
    }

    /// An unfavorite followed by a refavorite comes back as two notifications
    /// from the same person. The second is absorbed into the row the first
    /// seeded rather than opening a duplicate one beside it.
    func testARepeatFromTheGroupsOwnAuthorIsAbsorbed() {
        let groups = GroupedNotification.group([
            notification("1", reason: "gallery-favorite", author: "alice"),
            notification("2", reason: "gallery-favorite", author: "alice"),
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].authorCount, 1)
        XCTAssertFalse(groups[0].isGrouped)
    }

    /// The same, arriving on a later page rather than in the first batch.
    func testARepeatFromTheGroupsOwnAuthorOnALaterPageIsAbsorbed() {
        var groups = GroupedNotification.group([
            notification("1", reason: "gallery-favorite", author: "alice"),
        ])

        GroupedNotification.mergeNewPage([
            notification("2", reason: "gallery-favorite", author: "alice"),
        ], into: &groups)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].authorCount, 1)
    }

    /// A repeat must not cost the row the other people already on it.
    func testARepeatDoesNotDisturbTheRestOfTheFacepile() {
        let groups = GroupedNotification.group([
            notification("1", reason: "gallery-favorite", author: "alice"),
            notification("2", reason: "gallery-favorite", author: "bob"),
            notification("3", reason: "gallery-favorite", author: "alice"),
            notification("4", reason: "gallery-favorite", author: "carol"),
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].allAuthors.map(\.did), ["did:plc:alice", "did:plc:bob", "did:plc:carol"])
    }

    /// Follows have no subject, so they collapse across the board — but still
    /// only inside the same two-day window.
    func testFollowsGroupWithoutASubject() {
        let groups = GroupedNotification.group([
            notification("1", reason: "follow", author: "alice", gallery: nil),
            notification("2", reason: "follow", author: "bob", gallery: nil),
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].authorCount, 2)
    }

    func testFavoritesMoreThanTwoDaysApartStayApart() {
        let groups = GroupedNotification.group([
            notification("1", reason: "gallery-favorite", author: "alice", hours: 0),
            notification("2", reason: "gallery-favorite", author: "bob", hours: 49),
        ])

        XCTAssertEqual(groups.count, 2)
    }

    func testFavoritesJustInsideTwoDaysStillGroup() {
        let groups = GroupedNotification.group([
            notification("1", reason: "gallery-favorite", author: "alice", hours: 0),
            notification("2", reason: "gallery-favorite", author: "bob", hours: 47),
        ])

        XCTAssertEqual(groups.count, 1)
    }

    func testStoryFavoritesGroupOnTheStoryTheyBelongTo() {
        let groups = GroupedNotification.group([
            notification("1", reason: "story-favorite", author: "alice", gallery: nil, story: "at://s/1"),
            notification("2", reason: "story-favorite", author: "bob", gallery: nil, story: "at://s/1"),
            notification("3", reason: "story-favorite", author: "carol", gallery: nil, story: "at://s/2"),
        ])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].authorCount, 2)
        XCTAssertEqual(groups[1].authorCount, 1)
    }

    func testGroupingAnEmptyListProducesNothing() {
        XCTAssertTrue(GroupedNotification.group([]).isEmpty)
    }

    func testUngroupableNotificationsKeepTheirOriginalOrder() {
        let groups = GroupedNotification.group([
            notification("1", reason: "gallery-comment", author: "alice"),
            notification("2", reason: "reply", author: "bob"),
            notification("3", reason: "gallery-mention", author: "carol"),
        ])

        XCTAssertEqual(groups.map { String($0.notification.uri.suffix(1)) }, ["1", "2", "3"])
    }

    // MARK: - mergeNewPage

    /// The whole point of merging rather than regrouping is that page two's
    /// favorites join the row page one already built.
    func testASecondPageFoldsIntoTheGroupTheFirstPageBuilt() {
        var groups = GroupedNotification.group([
            notification("1", reason: "gallery-favorite", author: "alice"),
        ])

        GroupedNotification.mergeNewPage([
            notification("2", reason: "gallery-favorite", author: "bob"),
        ], into: &groups)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].authorCount, 2)
        XCTAssertEqual(
            String(groups[0].notification.uri.suffix(1)), "1",
            "The head must stay the notification page one showed"
        )
    }

    func testASecondPageAppendsWhenItMatchesNothing() {
        var groups = GroupedNotification.group([
            notification("1", reason: "gallery-favorite", author: "alice", gallery: "at://g/1"),
        ])

        GroupedNotification.mergeNewPage([
            notification("2", reason: "gallery-favorite", author: "bob", gallery: "at://g/2"),
            notification("3", reason: "gallery-comment", author: "carol"),
        ], into: &groups)

        XCTAssertEqual(groups.count, 3)
    }

    func testMergingSomeoneAlreadyInTheGroupDoesNotCountThemTwice() {
        var groups = GroupedNotification.group([
            notification("1", reason: "gallery-favorite", author: "alice"),
            notification("2", reason: "gallery-favorite", author: "bob"),
        ])

        GroupedNotification.mergeNewPage([
            notification("3", reason: "gallery-favorite", author: "bob"),
        ], into: &groups)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].authorCount, 2)
    }

    func testMergingAnEmptyPageChangesNothing() {
        var groups = GroupedNotification.group([
            notification("1", reason: "gallery-favorite", author: "alice"),
        ])

        GroupedNotification.mergeNewPage([], into: &groups)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].authorCount, 1)
    }

    // MARK: - Identity

    /// Rows are diffed by URI, and the author count is part of equality so a
    /// group that gains a face actually redraws.
    func testTwoGroupsAreEqualOnlyWhenTheHeadAndTheCountMatch() {
        let base = GroupedNotification(
            notification: notification("1", reason: "gallery-favorite", author: "alice"),
            additional: []
        )
        let same = GroupedNotification(
            notification: notification("1", reason: "gallery-favorite", author: "alice"),
            additional: []
        )
        let grown = GroupedNotification(
            notification: notification("1", reason: "gallery-favorite", author: "alice"),
            additional: [notification("2", reason: "gallery-favorite", author: "bob")]
        )
        let other = GroupedNotification(
            notification: notification("9", reason: "gallery-favorite", author: "alice"),
            additional: []
        )

        XCTAssertEqual(base, same)
        XCTAssertNotEqual(base, grown)
        XCTAssertNotEqual(base, other)
        XCTAssertEqual(base.hashValue, same.hashValue)
    }

    func testTheHeadAuthorIsNotRepeatedInTheFacepile() {
        let group = GroupedNotification(
            notification: notification("1", reason: "gallery-favorite", author: "alice"),
            additional: [
                notification("2", reason: "gallery-favorite", author: "alice"),
                notification("3", reason: "gallery-favorite", author: "bob"),
            ]
        )

        XCTAssertEqual(group.allAuthors.map(\.did), ["did:plc:alice", "did:plc:bob"])
    }
}

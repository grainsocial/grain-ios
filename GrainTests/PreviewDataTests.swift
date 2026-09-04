@testable import Grain
import SwiftUI
import UIKit
import XCTest

/// Every `#Preview` in the app is built from these fixtures, and nothing else
/// checks them — a fixture that stops decoding, or a bundle image that gets
/// renamed, breaks every canvas at once and only shows up when someone opens
/// Xcode. These assert the shapes the previews rely on.
@MainActor
final class PreviewDataTests: XCTestCase {
    // MARK: - Profiles

    func testTheProfileFixturesAreDistinctPeople() {
        let profiles = [
            PreviewData.profile1, PreviewData.profile2, PreviewData.profile3, PreviewData.profile4,
            PreviewData.profile5, PreviewData.profile6, PreviewData.profile7, PreviewData.profile8,
        ]

        XCTAssertEqual(Set(profiles.map(\.did)).count, profiles.count, "Two preview profiles share a DID")
        XCTAssertTrue(profiles.allSatisfy { !$0.handle.isEmpty })
    }

    func testTheDetailedProfileHasWhatAProfileHeaderNeeds() {
        let profile = PreviewData.profile

        XCTAssertFalse(profile.did.isEmpty)
        XCTAssertFalse(profile.handle.isEmpty)
        XCTAssertNotNil(profile.displayName)
        XCTAssertNotNil(profile.followersCount)
        XCTAssertNotNil(profile.followsCount)
    }

    // MARK: - Galleries

    func testTheGalleryFixturesAreUsableCards() {
        XCTAssertEqual(PreviewData.galleries.count, 3)

        for gallery in PreviewData.galleries {
            XCTAssertFalse(gallery.uri.isEmpty, "A gallery with no URI can't be identified in a ForEach")
            XCTAssertFalse(gallery.creator.did.isEmpty)
            XCTAssertFalse(gallery.indexedAt.isEmpty)
            XCTAssertFalse(gallery.items?.isEmpty ?? true, "A card preview with no photos shows nothing")
        }
    }

    func testGalleryFixturesHaveDistinctIdentities() {
        XCTAssertEqual(Set(PreviewData.galleries.map(\.id)).count, PreviewData.galleries.count)
    }

    /// The card lays out on aspect ratio, so a zero height would divide by zero.
    func testEveryPreviewPhotoHasAUsableAspectRatio() {
        for photo in PreviewData.photos {
            XCTAssertGreaterThan(photo.aspectRatio.width, 0, "\(photo.uri) has no width")
            XCTAssertGreaterThan(photo.aspectRatio.height, 0, "\(photo.uri) has no height")
            XCTAssertFalse(photo.thumb.isEmpty)
            XCTAssertFalse(photo.fullsize.isEmpty)
        }
    }

    func testPreviewPhotosHaveDistinctIdentities() {
        XCTAssertEqual(Set(PreviewData.photos.map(\.id)).count, PreviewData.photos.count)
    }

    // MARK: - Comments

    func testTheCommentFixturesIncludeAReplyChain() {
        let uris = Set(PreviewData.comments.map(\.uri))

        XCTAssertFalse(PreviewData.comments.isEmpty)
        XCTAssertEqual(uris.count, PreviewData.comments.count, "Two preview comments share a URI")
        XCTAssertTrue(
            PreviewData.comments.contains { $0.replyTo != nil },
            "The comment preview needs a reply in it or the indent branch is never seen"
        )
        for comment in PreviewData.comments {
            if let parent = comment.replyTo {
                XCTAssertTrue(uris.contains(parent), "Reply \(comment.uri) points at a comment that isn't in the fixture")
            }
        }
    }

    func testTheStoryCommentFixturesAreDistinct() {
        XCTAssertFalse(PreviewData.storyComments.isEmpty)
        XCTAssertEqual(
            Set(PreviewData.storyComments.map(\.uri)).count,
            PreviewData.storyComments.count
        )
    }

    // MARK: - Stories

    func testTheStoryFixturesAreUsable() {
        XCTAssertFalse(PreviewData.stories.isEmpty)

        for story in PreviewData.stories {
            XCTAssertFalse(story.uri.isEmpty)
            XCTAssertEqual(story.id, story.uri)
            XCTAssertEqual(story.storyUri, story.uri)
            XCTAssertGreaterThan(story.aspectRatio.height, 0)
            XCTAssertFalse(story.fullsize.isEmpty)
        }
    }

    /// The strip sorts and rings on these, so an author with no stories or a
    /// duplicate DID would show a ring that opens onto nothing.
    func testTheStoryAuthorFixturesAllHaveStories() {
        XCTAssertFalse(PreviewData.storyAuthors.isEmpty)
        XCTAssertEqual(
            Set(PreviewData.storyAuthors.map(\.id)).count,
            PreviewData.storyAuthors.count
        )
        XCTAssertTrue(PreviewData.storyAuthors.allSatisfy { $0.storyCount > 0 })
    }

    // MARK: - Notifications

    /// The notifications preview exists to show grouping, so the fixture has to
    /// actually group into fewer rows than it has notifications.
    func testTheNotificationFixturesGroup() {
        XCTAssertFalse(PreviewData.notifications.isEmpty)

        let grouped = GroupedNotification.group(PreviewData.notifications)

        XCTAssertLessThan(
            grouped.count, PreviewData.notifications.count,
            "Nothing in the notifications fixture collapses, so the grouped row is never previewed"
        )
        XCTAssertTrue(grouped.contains { $0.isGrouped })
    }

    func testEveryNotificationFixtureHasARecognisedReason() {
        for notification in PreviewData.notifications {
            XCTAssertNotEqual(
                notification.reasonType, .unknown,
                "\(notification.reason) isn't a reason the app knows how to draw"
            )
        }
    }

    // MARK: - Editor photo items

    func testThePhotoItemFixturesAreUsableInTheEditor() {
        let items = PreviewData.photoItems

        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        for item in items {
            XCTAssertGreaterThan(item.thumbnail.size.width, 0)
            XCTAssertGreaterThan(item.carouselPreview.size.width, 0)
            XCTAssertGreaterThan(item.naturalAspect, 0, "A zero aspect divides by zero in CellGeometry")
        }
    }

    /// The exif variant exists so a preview shows the chip both on and off.
    func testThePhotoItemsWithExifShowBothChipStates() {
        let items = PreviewData.photoItemsWithExif

        XCTAssertEqual(items.count, PreviewData.photoItems.count)
        XCTAssertTrue(items.contains { $0.exifSummary != nil })
        XCTAssertTrue(items.contains { $0.exifSummary == nil })
    }

    // MARK: - Helpers

    func testTheGradientThumbnailIsDrawnAtTheRequestedSize() {
        let image = PreviewData.gradientThumb(
            colors: [UIColor.systemPink.cgColor, UIColor.systemTeal.cgColor],
            size: CGSize(width: 120, height: 80)
        )

        XCTAssertEqual(image.size.width, 120, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 80, accuracy: 0.5)
    }

    func testBundleImageURLsAreFileURLsOrEmpty() {
        let missing = PreviewData.bundleImageURL("definitely-not-in-the-bundle")

        XCTAssertTrue(
            missing.isEmpty || URL(string: missing) != nil,
            "A missing bundle image should degrade to something a URL initialiser can survive"
        )
    }

    // MARK: - Preview environment

    /// Previews install their own environment set; if it stops matching what
    /// the views read, every canvas traps at once.
    func testThePreviewEnvironmentRenders() {
        ViewRender.render(
            AvatarView(url: nil, size: 48)
                .previewEnvironments()
                .grainPreview(),
            settle: 0
        )
    }

    func testTheAppIsNotRunningAsAPreview() {
        XCTAssertFalse(isPreview, "Tests aren't a preview canvas; preview-only shortcuts must stay off")
    }
}

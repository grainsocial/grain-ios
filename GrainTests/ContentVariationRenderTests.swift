@testable import Grain
import SwiftUI
import XCTest

/// The gallery card and the story viewer are the two largest views in the app,
/// and almost every field on a gallery or a story swaps something in them — a
/// filled heart, a location row, an exif line, an owner-only menu. These render
/// them across those fields rather than against one plain fixture.
@MainActor
final class ContentVariationRenderTests: XCTestCase {
    private var account: TestAccount!

    /// Async overrides: the synchronous `setUp`/`tearDown` are nonisolated, so
    /// touching main-actor state from them warns.
    override func setUp() async throws {
        try await super.setUp()
        account = TestAccount()
        MockURLProtocol.interceptSharedSession()
        MockURLProtocol.respondByPath(Fixtures.routes)
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        MockURLProtocol.stopInterceptingSharedSession()
        account.restore()
        try await super.tearDown()
    }

    // MARK: - Builders

    private func profile(_ did: String = "did:plc:test") -> GrainProfile {
        GrainProfile(
            cid: "bafy\(did)",
            did: did,
            handle: "\(did).test",
            displayName: "Someone",
            avatar: "https://test.local/avatar.jpg"
        )
    }

    private func exif() -> GrainExif {
        GrainExif(
            uri: "at://did:plc:test/social.grain.photo.exif/1",
            cid: "bafyexif",
            photo: "at://did:plc:test/social.grain.photo/1",
            createdAt: "2025-01-02T00:00:00Z",
            exposureTime: "1/500",
            fNumber: "2.0",
            flash: "Off, Did not fire",
            focalLengthIn35mmFormat: "35",
            iSO: 400,
            lensMake: "FUJIFILM",
            lensModel: "23mm f/2",
            make: "FUJIFILM",
            model: "X100V"
        )
    }

    private func photo(_ index: Int, alt: String? = nil, withExif: Bool = false) -> GrainPhoto {
        GrainPhoto(
            uri: "at://did:plc:test/social.grain.photo/\(index)",
            cid: "bafyphoto\(index)",
            thumb: "https://test.local/thumb\(index).jpg",
            fullsize: "https://test.local/full\(index).jpg",
            alt: alt,
            aspectRatio: AspectRatio(width: 3, height: 2),
            exif: withExif ? exif() : nil
        )
    }

    private func gallery(
        creator: String = "did:plc:other",
        photos: [GrainPhoto] = [],
        favourited: Bool = false,
        crossPost: CrossPostInfo? = nil,
        locationDisplay: String? = nil,
        cameras: [String]? = nil,
        favedByFollowing: [GrainProfile]? = nil
    ) -> GrainGallery {
        GrainGallery(
            uri: "at://\(creator)/social.grain.gallery/1",
            cid: "bafygallery",
            title: "A gallery",
            description: "Shot on #Portra400 with @tester.grain.social, see https://grain.social.",
            cameras: cameras,
            locationDisplay: locationDisplay,
            creator: profile(creator),
            items: photos,
            favCount: 42,
            favedByFollowing: favedByFollowing,
            commentCount: 3,
            createdAt: "2025-01-02T00:00:00Z",
            indexedAt: "2025-01-02T00:00:00Z",
            viewer: favourited ? GalleryViewerState(fav: "at://did:plc:test/social.grain.favorite/1") : nil,
            crossPost: crossPost
        )
    }

    private func renderCard(_ gallery: GrainGallery, env: TestEnvironment, settle: TimeInterval = 0.15) {
        var bound = gallery
        ViewRender.render(
            GalleryCardView(
                gallery: Binding(get: { bound }, set: { bound = $0 }),
                client: env.client,
                onNavigate: {},
                onCommentTap: {},
                onFavoritesTap: {},
                onProfileTap: { _ in },
                onHashtagTap: { _ in },
                onLocationTap: { _, _ in },
                onStoryTap: { _ in },
                onReport: {},
                onDelete: {}
            )
            .withTestEnvironment(env),
            settle: settle
        )
    }

    // MARK: - Gallery card

    /// A favorited gallery draws a filled heart and a different accessibility
    /// label from an unfavorited one.
    func testRendersACardInBothFavoriteStates() {
        let env = TestEnvironment()
        renderCard(gallery(photos: [photo(1)], favourited: false), env: env)
        renderCard(gallery(photos: [photo(1)], favourited: true), env: env)
    }

    /// Your own gallery gets a delete action where someone else's gets report.
    func testRendersYourOwnCardAndSomeoneElses() {
        let env = TestEnvironment()
        renderCard(gallery(creator: "did:plc:test", photos: [photo(1)]), env: env)
        renderCard(gallery(creator: "did:plc:other", photos: [photo(1)]), env: env)
    }

    /// A cross-posted gallery carries a link back to the Bluesky post.
    func testRendersACardWithACrossPostLink() {
        let env = TestEnvironment()
        renderCard(
            gallery(photos: [photo(1)], crossPost: CrossPostInfo(url: "https://bsky.app/profile/x/post/1")),
            env: env
        )
    }

    /// Exif and a camera name add a whole row under the photo.
    func testRendersACardWithExifAndACameraName() {
        let env = TestEnvironment()
        renderCard(
            gallery(photos: [photo(1, withExif: true), photo(2)], cameras: ["Fujifilm X100V"]),
            env: env
        )
    }

    /// Alt text is shown behind a badge rather than inline.
    func testRendersACardWithAltText() {
        let env = TestEnvironment()
        renderCard(gallery(photos: [photo(1, alt: "A quiet street just after sunrise")]), env: env)
    }

    func testRendersACardWithALocation() {
        let env = TestEnvironment()
        renderCard(gallery(photos: [photo(1)], locationDisplay: "Lisboa, Portugal"), env: env)
    }

    /// The facepile only appears when people the viewer follows favorited it,
    /// and it says "and others" past two names.
    func testRendersACardWithFacepilesOfEachSize() {
        let env = TestEnvironment()
        let people = (0 ..< 4).map { profile("did:plc:fan\($0)") }
        for count in [1, 2, 4] {
            renderCard(gallery(photos: [photo(1)], favedByFollowing: Array(people.prefix(count))), env: env)
        }
    }

    /// A creator with a live story gets a tappable ring around their avatar.
    func testRendersACardWhoseAuthorHasAStory() {
        let env = TestEnvironment()
        env.storyStatus.update(from: [
            GrainStoryAuthor(profile: profile("did:plc:other"), storyCount: 2, latestAt: Fixtures.freshTimestamp),
        ])

        renderCard(gallery(photos: [photo(1)]), env: env)
    }

    /// Signed out, none of the card's actions are available.
    func testRendersACardWhileSignedOut() {
        let env = TestEnvironment(authenticated: false)
        renderCard(gallery(photos: [photo(1)], favourited: false), env: env)
    }

    /// Mixed aspect ratios make the carousel size to the tallest photo rather
    /// than to each page, which is a separate measurement path.
    func testRendersACardWithMixedAspectRatios() {
        let env = TestEnvironment()
        let mixed = [
            GrainPhoto(
                uri: "at://did:plc:other/social.grain.photo/1", cid: "c1",
                thumb: "https://test.local/1.jpg", fullsize: "https://test.local/1f.jpg",
                aspectRatio: AspectRatio(width: 3, height: 2)
            ),
            GrainPhoto(
                uri: "at://did:plc:other/social.grain.photo/2", cid: "c2",
                thumb: "https://test.local/2.jpg", fullsize: "https://test.local/2f.jpg",
                aspectRatio: AspectRatio(width: 2, height: 3)
            ),
        ]
        renderCard(gallery(photos: mixed), env: env)
    }

    // MARK: - Story viewer

    private func story(
        _ index: Int,
        creator: String = "did:plc:other",
        expired: Bool? = nil,
        favourited: Bool = false,
        labels: [ATLabel]? = nil,
        locationDisplay: String? = nil,
        crossPost: CrossPostInfo? = nil
    ) -> GrainStory {
        GrainStory(
            uri: "at://\(creator)/social.grain.story/\(index)",
            cid: "bafystory\(index)",
            creator: profile(creator),
            thumb: "https://test.local/thumb\(index).jpg",
            fullsize: "https://test.local/full\(index).jpg",
            aspectRatio: AspectRatio(width: 3, height: 4),
            locationDisplay: locationDisplay,
            createdAt: Fixtures.freshTimestamp,
            labels: labels,
            expired: expired,
            crossPost: crossPost,
            viewer: favourited ? StoryViewerState(fav: "at://did:plc:test/social.grain.favorite/1") : nil
        )
    }

    private func author(_ did: String = "did:plc:other", count: Int = 2) -> GrainStoryAuthor {
        GrainStoryAuthor(profile: profile(did), storyCount: count, latestAt: Fixtures.freshTimestamp)
    }

    private func renderViewer(
        authors: [GrainStoryAuthor],
        stories: [GrainStory],
        startAuthorDid: String? = nil,
        startIndex: Int? = nil,
        env: TestEnvironment
    ) {
        ViewRender.render(
            StoryViewer(
                authors: authors,
                startAuthorDid: startAuthorDid,
                initialStories: stories,
                startStoryIndex: startIndex,
                client: env.client,
                onProfileTap: { _ in },
                onDismiss: {}
            )
            .withTestEnvironment(env),
            settle: 0.4
        )
    }

    func testRendersTheStoryViewerWithSeveralStories() {
        let env = TestEnvironment()
        renderViewer(
            authors: [author()],
            stories: [story(1), story(2, locationDisplay: "Lisboa"), story(3)],
            env: env
        )
    }

    /// Starting partway through someone's stories is what tapping a ring does
    /// when you've already seen the first few.
    func testRendersTheStoryViewerStartedPartwayThrough() {
        let env = TestEnvironment()
        renderViewer(
            authors: [author(count: 3)],
            stories: [story(1), story(2), story(3)],
            startIndex: 2,
            env: env
        )
    }

    /// Your own story gets the author's controls — the viewer count and delete
    /// — where someone else's gets favorite and report.
    func testRendersYourOwnStoryAndSomeoneElses() {
        let env = TestEnvironment()
        renderViewer(
            authors: [author("did:plc:test")],
            stories: [story(1, creator: "did:plc:test")],
            startAuthorDid: "did:plc:test",
            env: env
        )
        renderViewer(
            authors: [author("did:plc:other")],
            stories: [story(1, creator: "did:plc:other")],
            startAuthorDid: "did:plc:other",
            env: env
        )
    }

    func testRendersAFavoritedStory() {
        let env = TestEnvironment()
        renderViewer(authors: [author()], stories: [story(1, favourited: true)], env: env)
    }

    /// A labelled story is covered until it's revealed.
    func testRendersALabelledStory() {
        let env = TestEnvironment()
        renderViewer(
            authors: [author()],
            stories: [story(1, labels: [ATLabel(src: nil, uri: nil, val: "nudity", cts: nil)])],
            env: env
        )
    }

    /// An expired story is still in the payload for a while; it must not be
    /// presented as if it were live.
    func testRendersAnExpiredStory() {
        let env = TestEnvironment()
        renderViewer(authors: [author()], stories: [story(1, expired: true)], env: env)
    }

    func testRendersACrossPostedStory() {
        let env = TestEnvironment()
        renderViewer(
            authors: [author()],
            stories: [story(1, crossPost: CrossPostInfo(url: "https://bsky.app/profile/x/post/1"))],
            env: env
        )
    }

    /// Several authors is what paging sideways moves between.
    func testRendersTheStoryViewerWithSeveralAuthors() {
        let env = TestEnvironment()
        renderViewer(
            authors: [author("did:plc:one"), author("did:plc:two"), author("did:plc:three")],
            stories: [story(1, creator: "did:plc:one")],
            startAuthorDid: "did:plc:two",
            env: env
        )
    }

    /// A story already watched sorts and rings differently from an unwatched one.
    func testRendersAStoryThatHasAlreadyBeenWatched() {
        let env = TestEnvironment()
        let watched = story(1)
        env.viewedStories.markViewed(
            uri: watched.uri, authorDid: "did:plc:other", createdAt: watched.createdAt
        )

        renderViewer(authors: [author()], stories: [watched], env: env)
    }
}

@testable import Grain
import SwiftUI
import XCTest

/// The reusable pieces the screens are assembled from. Several of them branch
/// hard — a card with one photo lays out differently from a card with eight,
/// and a labelled gallery doesn't show its photos at all — so each is rendered
/// across the branches rather than once in its happy state.
@MainActor
final class ComponentRenderTests: XCTestCase {
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

    // MARK: - Model builders

    private func makeProfile(did: String = "did:plc:test") -> GrainProfile {
        GrainProfile(
            cid: "bafyprofile",
            did: did,
            handle: "tester.grain.social",
            displayName: "Tester",
            avatar: "https://test.local/avatar.jpg"
        )
    }

    private func label(_ value: String) -> ATLabel {
        ATLabel(src: nil, uri: nil, val: value, cts: nil)
    }

    private func makePhoto(index: Int, width: Int = 3, height: Int = 2) -> GrainPhoto {
        GrainPhoto(
            uri: "at://did:plc:test/social.grain.photo/\(index)",
            cid: "bafyphoto\(index)",
            thumb: "https://test.local/thumb\(index).jpg",
            fullsize: "https://test.local/full\(index).jpg",
            alt: "Photo \(index)",
            aspectRatio: AspectRatio(width: width, height: height)
        )
    }

    private func makeGallery(
        photos: Int = 1,
        portrait: Bool = false,
        labels: [ATLabel]? = nil,
        favCount: Int? = 3,
        favedByFollowing: [GrainProfile]? = nil,
        location: H3Location? = nil
    ) -> GrainGallery {
        GrainGallery(
            uri: "at://did:plc:test/social.grain.gallery/1",
            cid: "bafygallery",
            title: "A test gallery",
            description: "A description with a #hashtag, an @tester.grain.social mention and https://grain.social.",
            location: location,
            locationDisplay: location == nil ? nil : "Test City",
            creator: makeProfile(),
            items: (0 ..< photos).map { makePhoto(index: $0, width: portrait ? 2 : 3, height: portrait ? 3 : 2) },
            favCount: favCount,
            favedByFollowing: favedByFollowing,
            commentCount: 2,
            labels: labels,
            createdAt: "2025-01-02T00:00:00Z",
            indexedAt: "2025-01-02T00:00:00Z"
        )
    }

    private func renderCard(_ gallery: GrainGallery, env: TestEnvironment) {
        var bound = gallery
        ViewRender.render(
            GalleryCardView(
                gallery: Binding(get: { bound }, set: { bound = $0 }),
                client: env.client
            )
            .withTestEnvironment(env)
        )
    }

    // MARK: - Gallery card

    func testRendersGalleryCard() {
        MockURLProtocol.respondWithJSON(Fixtures.gallery)
        let env = TestEnvironment()
        renderCard(makeGallery(), env: env)
    }

    /// More than one photo brings in the pager and the page indicator, which a
    /// single-photo card never builds.
    func testRendersGalleryCardWithACarousel() {
        MockURLProtocol.respondWithJSON(Fixtures.gallery)
        let env = TestEnvironment()
        renderCard(makeGallery(photos: 3), env: env)
    }

    /// The indicator collapses past five dots, so a long gallery takes a
    /// different branch again.
    func testRendersGalleryCardWithMoreDotsThanFit() {
        MockURLProtocol.respondWithJSON(Fixtures.gallery)
        let env = TestEnvironment()
        renderCard(makeGallery(photos: 8), env: env)
    }

    func testRendersGalleryCardWithPortraitPhotos() {
        MockURLProtocol.respondWithJSON(Fixtures.gallery)
        let env = TestEnvironment()
        renderCard(makeGallery(photos: 2, portrait: true), env: env)
    }

    /// A gallery with no photos at all still has to lay out rather than trap on
    /// an empty items array.
    func testRendersGalleryCardWithNoPhotos() {
        MockURLProtocol.respondWithJSON(Fixtures.gallery)
        let env = TestEnvironment()
        renderCard(makeGallery(photos: 0), env: env)
    }

    /// A content-level label replaces the whole card with the warning, so this
    /// is the one branch where none of the photo layout runs.
    func testRendersGalleryCardBehindAContentWarning() {
        MockURLProtocol.respondWithJSON(Fixtures.gallery)
        let env = TestEnvironment()
        renderCard(makeGallery(labels: [label("!hide")]), env: env)
    }

    /// A media label blurs the photos but keeps the card, which is a different
    /// branch again.
    func testRendersGalleryCardBehindAMediaWarning() {
        MockURLProtocol.respondWithJSON(Fixtures.gallery)
        let env = TestEnvironment()
        renderCard(makeGallery(photos: 2, labels: [label("nudity")]), env: env)
    }

    func testRendersGalleryCardWithAFacepileAndALocation() {
        MockURLProtocol.respondWithJSON(Fixtures.gallery)
        let env = TestEnvironment()
        renderCard(
            makeGallery(
                favCount: 1200,
                favedByFollowing: [makeProfile(did: "did:plc:a"), makeProfile(did: "did:plc:b")],
                location: H3Location(value: "8a2a1072b59ffff", name: "Test City")
            ),
            env: env
        )
    }

    // MARK: - Rich text

    /// The regex fallback is the expensive path and runs whenever the server
    /// sends no facets, so each pattern gets a pass.
    func testRendersRichTextThroughTheRegexFallback() {
        for text in [
            "Plain text with nothing in it.",
            "Visit https://grain.social for more.",
            "Shot on grain.social, no scheme.",
            "Thanks @alice.grain.social!",
            "Filed under #35mm and #portra400.",
            "@alice.test posted https://grain.social/x about #film",
        ] {
            ViewRender.render(RichTextView(text: text), settle: 0)
        }
    }

    /// Facets win over the regex when the server supplies them, which is a
    /// separate segmentation routine working in UTF-8 byte offsets.
    func testRendersRichTextFromFacets() throws {
        let text = "Hi @alice.test see https://grain.social #film"
        let utf8 = Array(text.utf8)
        let mentionStart = try XCTUnwrap(utf8.firstIndex(of: UInt8(ascii: "@")))
        let linkStart = try XCTUnwrap(utf8.firstIndex(of: UInt8(ascii: "h")))
        let tagStart = try XCTUnwrap(utf8.firstIndex(of: UInt8(ascii: "#")))

        let facets = [
            Facet(
                index: Facet.ByteSlice(byteStart: mentionStart, byteEnd: mentionStart + 11),
                features: [.mention(did: "did:plc:alice")]
            ),
            Facet(
                index: Facet.ByteSlice(byteStart: linkStart, byteEnd: linkStart + 20),
                features: [.link(uri: "https://grain.social")]
            ),
            Facet(
                index: Facet.ByteSlice(byteStart: tagStart, byteEnd: tagStart + 5),
                features: [.tag(tag: "film")]
            ),
        ]

        ViewRender.render(
            RichTextView(text: text, facets: facets, onMentionTap: { _ in }, onHashtagTap: { _ in }),
            settle: 0
        )
    }

    /// Emoji push the byte offsets away from the character offsets, which is
    /// exactly where a facet renderer goes wrong.
    func testRendersRichTextWithFacetsAfterEmoji() throws {
        let text = "📷🎞️ @alice.test"
        let utf8 = Array(text.utf8)
        let mentionStart = try XCTUnwrap(utf8.firstIndex(of: UInt8(ascii: "@")))

        ViewRender.render(
            RichTextView(
                text: text,
                facets: [Facet(
                    index: Facet.ByteSlice(byteStart: mentionStart, byteEnd: utf8.count),
                    features: [.mention(did: "did:plc:alice")]
                )]
            ),
            settle: 0
        )
    }

    /// A facet whose range runs off the end of the text arrives from the server,
    /// not from us, so it has to be survived rather than trusted.
    func testRendersRichTextWithAnOutOfRangeFacet() {
        ViewRender.render(
            RichTextView(
                text: "Short",
                facets: [Facet(
                    index: Facet.ByteSlice(byteStart: 2, byteEnd: 900),
                    features: [.link(uri: "https://grain.social")]
                )]
            ),
            settle: 0
        )
    }

    func testRendersRichTextWithNoFeaturesOnAFacet() {
        ViewRender.render(
            RichTextView(
                text: "Some text here",
                facets: [Facet(index: Facet.ByteSlice(byteStart: 0, byteEnd: 4), features: [])]
            ),
            settle: 0
        )
    }

    // MARK: - Avatars and facepiles

    func testRendersAvatarWithAndWithoutAURL() {
        ViewRender.render(AvatarView(url: nil), settle: 0)
        ViewRender.render(AvatarView(url: "https://test.local/avatar.jpg", size: 64), settle: 0)
        ViewRender.render(AvatarView(url: "not a url", size: 24, animated: false), settle: 0)
    }

    // MARK: - Exif

    func testRendersExifInfoAcrossItsBranches() {
        let full = ExifDisplayData(
            camera: "Fujifilm X100V",
            lens: "23mm f/2",
            focalLength: "35mm",
            fNumber: "f/2",
            exposureTime: "1/500s",
            iso: "ISO 400"
        )

        ViewRender.render(ExifInfoView(exif: full), settle: 0)
        ViewRender.render(ExifInfoView(exif: ExifDisplayData(camera: "Leica M6")), settle: 0)
        ViewRender.render(ExifInfoView(exif: nil), settle: 0)
        // Reserved rows keep a card from resizing as you page between photos
        // that do and don't carry exif.
        ViewRender.render(
            ExifInfoView(exif: nil, reserveCameraRow: true, reserveLensRow: true),
            settle: 0
        )
    }

    func testRendersExifSettingsRowWithGaps() {
        ViewRender.render(ExifSettingsRow(tokens: ["35mm", nil, "1/500s", nil]), settle: 0)
        ViewRender.render(ExifSettingsRow(tokens: [nil, nil, nil]), settle: 0)
    }

    // MARK: - Skeletons

    func testRendersEverySkeletonShape() {
        ViewRender.render(SkeletonBar(), settle: 0)
        ViewRender.render(SkeletonBar(width: 120, height: 20, cornerRadius: 10), settle: 0)
        ViewRender.render(SkeletonCircle(size: 44), settle: 0)
        ViewRender.render(SkeletonGrid(), settle: 0)
        ViewRender.render(SkeletonGrid(rows: 1, columns: 2, aspectRatio: 1), settle: 0)
    }

    /// The delay is what stops a skeleton flashing on a fast response, so it
    /// has to still be empty immediately and present once the delay elapses.
    func testTheDelayedSkeletonWaitsBeforeAppearing() {
        ViewRender.render(DelayedSkeleton { SkeletonBar() }, settle: 0)
        ViewRender.render(DelayedSkeleton(delay: .milliseconds(1)) { SkeletonBar() }, settle: 0.2)
    }

    // MARK: - Labels

    func testRendersLabelBadgeAndMediaWarning() {
        ViewRender.render(LabelBadge(name: "nudity"), settle: 0)
        ViewRender.render(MediaWarningOverlay(name: "graphic-media", onReveal: {}), settle: 0)
    }

    // MARK: - Story strip

    func testRendersStoryStrip() {
        let env = TestEnvironment()
        let authors = (0 ..< 4).map { index in
            GrainStoryAuthor(
                profile: makeProfile(did: "did:plc:author\(index)"),
                storyCount: index + 1,
                latestAt: "2025-01-03T00:00:00Z"
            )
        }

        ViewRender.render(
            StoryStripView(
                authors: authors,
                userDid: "did:plc:test",
                userAvatar: "https://test.local/avatar.jpg",
                onAuthorTap: { _, _ in },
                onCreateTap: {}
            )
            .withTestEnvironment(env)
        )
    }

    /// Signed out there is no "your story" bubble to lead with.
    func testRendersStoryStripWithNoAuthorsAndNoUser() {
        let env = TestEnvironment(authenticated: false)
        ViewRender.render(
            StoryStripView(
                authors: [],
                userDid: nil,
                userAvatar: nil,
                onAuthorTap: { _, _ in },
                onCreateTap: {}
            )
            .withTestEnvironment(env)
        )
    }

    // MARK: - Comments

    /// A deleted comment, a reply chain and a muted comment are three distinct
    /// row layouts inside the same list.
    func testRendersCommentSheetWithRepliesAndAMutedComment() {
        let env = TestEnvironment()
        let root = GrainComment(
            uri: "at://did:plc:test/social.grain.comment/1",
            cid: "bafycomment1",
            author: makeProfile(),
            text: "A root comment mentioning @tester.grain.social and #film.",
            createdAt: "2025-01-03T00:00:00Z",
            favCount: 4
        )
        let reply = GrainComment(
            uri: "at://did:plc:test/social.grain.comment/2",
            cid: "bafycomment2",
            author: makeProfile(did: "did:plc:other"),
            text: "A reply.",
            replyTo: root.uri,
            createdAt: "2025-01-03T01:00:00Z",
            favCount: 0
        )
        let muted = GrainComment(
            uri: "at://did:plc:test/social.grain.comment/3",
            cid: "bafycomment3",
            author: makeProfile(did: "did:plc:muted"),
            text: "Hidden behind a mute.",
            createdAt: "2025-01-03T02:00:00Z",
            muted: true
        )

        ViewRender.render(
            CommentSheetContent(
                comments: [root, reply, muted],
                isLoading: false,
                isPostingComment: false,
                client: env.client,
                onPost: { _, _ in },
                onDelete: { _ in },
                onProfileTap: { _ in },
                onHashtagTap: { _ in }
            )
            .withTestEnvironment(env)
        )
    }

    /// Empty state and mid-post state are separate branches from the loaded list.
    func testRendersCommentSheetWhenEmptyAndWhilePosting() {
        let env = TestEnvironment()

        for posting in [false, true] {
            ViewRender.render(
                CommentSheetContent(
                    comments: [],
                    isLoading: false,
                    isPostingComment: posting,
                    client: env.client,
                    onPost: { _, _ in },
                    onDelete: { _ in },
                    dismissStyle: .done
                )
                .withTestEnvironment(env)
            )
        }
    }

    // MARK: - Mention suggestions

    func testRendersMentionSuggestionOverlay() {
        let state = MentionAutocompleteState()
        defer { state.clear() }
        state.update(text: "@ali")
        state.suggestions = [
            MentionSuggestion(handle: "alice.grain.social", displayName: "Alice", avatar: nil),
            MentionSuggestion(handle: "alex.grain.social", displayName: nil, avatar: "https://test.local/a.jpg"),
        ]

        ViewRender.render(MentionSuggestionOverlay(state: state) { _ in }, settle: 0)
    }

    /// With nothing to suggest the strip must produce no chrome at all.
    func testTheMentionOverlayIsEmptyWithoutSuggestions() {
        let state = MentionAutocompleteState()
        ViewRender.render(MentionSuggestionOverlay(state: state) { _ in }, settle: 0)
    }

    // MARK: - Location picker

    func testRendersLocationPickerRows() {
        let json: [String: Any] = [
            "place_id": 1,
            "lat": "38.72",
            "lon": "-9.14",
            "name": "Miradouro",
            "display_name": "Miradouro, Lisboa, Portugal",
            "address": ["city": "Lisboa", "country": "Portugal", "country_code": "pt"],
        ]
        let photoLocation = NominatimResult(from: json)
        XCTAssertNotNil(photoLocation, "Fixture no longer parses — the picker rows below prove nothing")

        // Nothing picked yet: the photo suggestion, the search field and the
        // results list.
        var unresolved: (h3: String, name: String, address: [String: AnyCodable]?)?
        ViewRender.render(
            LocationPickerRows(
                resolvedLocation: Binding(get: { unresolved }, set: { unresolved = $0 }),
                photoLocationResult: photoLocation,
                onSelectLocation: { _ in }
            ),
            settle: 0
        )

        // Nothing to suggest either.
        ViewRender.render(
            LocationPickerRows(
                resolvedLocation: Binding(get: { unresolved }, set: { unresolved = $0 }),
                photoLocationResult: nil,
                photoLocationLabel: "Use this photo's location",
                onSelectLocation: { _ in }
            ),
            settle: 0
        )

        // Already picked: the confirmed row with its clear button.
        var resolved: (h3: String, name: String, address: [String: AnyCodable]?)? =
            (h3: "8a2a1072b59ffff", name: "Miradouro", address: nil)
        ViewRender.render(
            LocationPickerRows(
                resolvedLocation: Binding(get: { resolved }, set: { resolved = $0 }),
                photoLocationResult: photoLocation,
                onSelectLocation: { _ in }
            ),
            settle: 0
        )
    }
}

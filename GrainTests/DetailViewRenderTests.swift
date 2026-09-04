@testable import Grain
import SwiftUI
import XCTest

/// The screens you reach from the feed and profile — detail, story, editing and
/// creation flows. Like the other render suites these exist to run the layout
/// code, which is where most of these files' lines are.
@MainActor
final class DetailViewRenderTests: XCTestCase {
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

    private func makeStory(index: Int = 1) -> GrainStory {
        GrainStory(
            uri: "at://did:plc:test/social.grain.story/\(index)",
            cid: "bafystory\(index)",
            creator: makeProfile(),
            thumb: "https://test.local/thumb.jpg",
            fullsize: "https://test.local/full.jpg",
            aspectRatio: AspectRatio(width: 3, height: 4),
            createdAt: "2025-01-03T00:00:00Z"
        )
    }

    private func makeAuthor() -> GrainStoryAuthor {
        GrainStoryAuthor(profile: makeProfile(), storyCount: 2, latestAt: "2025-01-03T00:00:00Z")
    }

    private func makeComment(index: Int = 1, replyTo: String? = nil) -> GrainComment {
        GrainComment(
            uri: "at://did:plc:test/social.grain.comment/\(index)",
            cid: "bafycomment\(index)",
            author: makeProfile(),
            text: "A test comment that is long enough to wrap onto a second line.",
            replyTo: replyTo,
            createdAt: "2025-01-03T00:00:00Z",
            favCount: 1
        )
    }

    // MARK: - Story viewer

    func testRendersStoryViewer() {
        MockURLProtocol.respondWithJSON(#"{"stories": []}"#)
        let env = TestEnvironment()

        ViewRender.render(
            StoryViewer(
                authors: [makeAuthor()],
                startAuthorDid: "did:plc:test",
                initialStories: [makeStory(index: 1), makeStory(index: 2)],
                startStoryIndex: 0,
                client: env.client
            )
            .withTestEnvironment(env),
            settle: 0.2
        )
    }

    func testRendersStoryViewerWithoutPreloadedStories() {
        MockURLProtocol.respondWithJSON(#"{"stories": []}"#)
        let env = TestEnvironment()

        ViewRender.render(
            StoryViewer(authors: [makeAuthor()], client: env.client)
                .withTestEnvironment(env),
            settle: 0.2
        )
    }

    // MARK: - Gallery detail

    func testRendersGalleryDetail() {
        MockURLProtocol.respondWithJSON(Fixtures.gallery)
        let env = TestEnvironment()

        ViewRender.render(
            GalleryDetailView(
                client: env.client,
                galleryUri: "at://did:plc:test/social.grain.gallery/1"
            )
            .withTestEnvironment(env)
        )
    }

    func testRendersGalleryDetailWhenItFailsToLoad() {
        MockURLProtocol.respondWithError(statusCode: 404)
        let env = TestEnvironment()

        ViewRender.render(
            GalleryDetailView(
                client: env.client,
                galleryUri: "at://did:plc:test/social.grain.gallery/missing"
            )
            .withTestEnvironment(env)
        )
    }

    // MARK: - Comments

    func testRendersCommentSheet() {
        let env = TestEnvironment()
        let comments = [
            makeComment(index: 1),
            makeComment(index: 2, replyTo: "at://did:plc:test/social.grain.comment/1"),
        ]

        ViewRender.render(
            CommentSheetContent(
                comments: comments,
                isLoading: false,
                isPostingComment: false,
                client: env.client,
                onPost: { _, _ in },
                onDelete: { _ in }
            )
            .withTestEnvironment(env)
        )
    }

    func testRendersCommentSheetWhileLoading() {
        let env = TestEnvironment()

        ViewRender.render(
            CommentSheetContent(
                comments: [],
                isLoading: true,
                isPostingComment: false,
                client: env.client,
                onPost: { _, _ in },
                onDelete: { _ in }
            )
            .withTestEnvironment(env)
        )
    }

    // MARK: - Profile editing

    func testRendersEditProfile() {
        MockURLProtocol.respondWithJSON(Fixtures.profile)
        let env = TestEnvironment()

        ViewRender.render(EditProfileView(client: env.client).withTestEnvironment(env))
    }

    // MARK: - Location feed

    func testRendersLocationFeed() {
        MockURLProtocol.respondWithJSON(Fixtures.feed)
        let env = TestEnvironment()

        ViewRender.render(
            LocationFeedView(
                client: env.client,
                h3Index: "8a2a1072b59ffff",
                locationName: "Test City"
            )
            .withTestEnvironment(env)
        )
    }

    // MARK: - Creation flow

    func testRendersCreateGallery() {
        MockURLProtocol.respondWithJSON("{}")
        let env = TestEnvironment()

        ViewRender.render(CreateGalleryView(client: env.client).withTestEnvironment(env))
    }

    /// The editor is driven entirely by bindings, so it renders without a
    /// network at all — one pass per mode covers the three layouts.
    func testRendersGalleryEditorInEachMode() throws {
        let env = TestEnvironment()
        let image = try XCTUnwrap(UIImage(systemName: "photo"))
        let items = [
            PhotoItem(thumbnail: image, carouselPreview: image, source: .camera(image, metadata: nil)),
            PhotoItem(thumbnail: image, carouselPreview: image, source: .camera(image, metadata: nil)),
        ]

        for mode in EditorMode.allCases {
            var boundItems = items
            var selected: UUID? = items.first?.id
            var isReordering = mode == .reorder
            var isAnimating = false
            var boundMode = mode

            ViewRender.render(
                GalleryEditor(
                    items: Binding(get: { boundItems }, set: { boundItems = $0 }),
                    selectedPhotoID: Binding(get: { selected }, set: { selected = $0 }),
                    isReordering: Binding(get: { isReordering }, set: { isReordering = $0 }),
                    isAnimatingMode: Binding(get: { isAnimating }, set: { isAnimating = $0 }),
                    mode: Binding(get: { boundMode }, set: { boundMode = $0 }),
                    sendExif: true
                )
                .withTestEnvironment(env)
            )
        }
    }
}

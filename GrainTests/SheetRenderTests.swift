@testable import Grain
import SwiftUI
import XCTest

/// The screens presented as sheets or pushes from the feed and story viewer.
/// None of them was reachable from the suite, and between them they are a large
/// share of the app's view code.
@MainActor
final class SheetRenderTests: XCTestCase {
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

    // MARK: - Sign in

    func testRendersLogin() {
        let env = TestEnvironment(authenticated: false)
        ViewRender.render(LoginView().withTestEnvironment(env))
    }

    // MARK: - Camera feed

    func testRendersCameraFeed() {
        MockURLProtocol.respondWithJSON(Fixtures.feed)
        let env = TestEnvironment()
        ViewRender.render(
            CameraFeedView(client: env.client, camera: "Fujifilm X100V").withTestEnvironment(env)
        )
    }

    func testRendersCameraFeedWhenEmpty() {
        MockURLProtocol.respondWithJSON(#"{"items": [], "cursor": null}"#)
        let env = TestEnvironment()
        ViewRender.render(
            CameraFeedView(client: env.client, camera: "Leica M6").withTestEnvironment(env)
        )
    }

    // MARK: - Story creation

    func testRendersStoryCreate() {
        MockURLProtocol.respondWithJSON("{}")
        let env = TestEnvironment()
        ViewRender.render(
            StoryCreateView(client: env.client, onCreated: {}).withTestEnvironment(env)
        )
    }

    // MARK: - Gallery comment sheet

    /// The sheet owns its own view model and loads the thread on appear, so a
    /// render covers both the loading and the loaded branches.
    func testRendersGalleryCommentSheet() {
        MockURLProtocol.handler = { request in
            let body = request.url!.path.contains("getGallery")
                ? Fixtures.galleryResponse
                : Fixtures.commentThread
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
        let env = TestEnvironment()

        ViewRender.render(
            CommentSheetView(
                client: env.client,
                galleryUri: "at://did:plc:test/social.grain.gallery/1",
                onProfileTap: { _ in },
                onHashtagTap: { _ in },
                onCommentCountChanged: { _ in }
            )
            .withTestEnvironment(env),
            settle: 0.2
        )
    }

    func testRendersGalleryCommentSheetWhenTheThreadFailsToLoad() {
        MockURLProtocol.respondWithError(statusCode: 500)
        let env = TestEnvironment()

        ViewRender.render(
            CommentSheetView(
                client: env.client,
                galleryUri: "at://did:plc:test/social.grain.gallery/1"
            )
            .withTestEnvironment(env)
        )
    }

    // MARK: - Story comment sheet

    func testRendersStoryCommentSheet() {
        MockURLProtocol.respondWithJSON(Fixtures.commentThread)
        let env = TestEnvironment()
        let viewModel = StoryCommentsViewModel(client: env.client)

        ViewRender.render(
            StoryCommentSheet(
                viewModel: viewModel,
                storyUri: "at://did:plc:test/social.grain.story/1",
                client: env.client,
                onProfileTap: { _ in },
                onDismiss: {}
            )
            .withTestEnvironment(env),
            settle: 0.2
        )
    }

    /// Opening the sheet from the comment button focuses the input, which puts
    /// the keyboard accessory and the mention strip on screen.
    func testRendersStoryCommentSheetWithTheInputFocused() {
        MockURLProtocol.respondWithJSON(#"{"comments": [], "cursor": null}"#)
        let env = TestEnvironment()

        ViewRender.render(
            StoryCommentSheet(
                viewModel: StoryCommentsViewModel(client: env.client),
                storyUri: "at://did:plc:test/social.grain.story/1",
                client: env.client,
                focusInput: true
            )
            .withTestEnvironment(env),
            settle: 0.2
        )
    }

    // MARK: - Comment presenter

    /// Without `configure` the presenter has no environment to hand the sheet,
    /// so it must decline rather than present a sheet with no auth in it.
    func testTheCommentPresenterDeclinesToOpenBeforeItIsConfigured() {
        let env = TestEnvironment()
        let presenter = StoryCommentPresenter()

        presenter.open(
            storyUri: "at://did:plc:test/social.grain.story/1",
            focusInput: false,
            commentsViewModel: StoryCommentsViewModel(client: env.client),
            client: env.client
        )

        XCTAssertNil(presenter.presentedStoryUri)
    }

    /// Closing something that was never opened has to be harmless — the story
    /// viewer calls it on teardown regardless.
    func testClosingAnUnopenedCommentPresenterIsHarmless() {
        let presenter = StoryCommentPresenter()
        presenter.close()

        XCTAssertNil(presenter.presentedStoryUri)
    }
}

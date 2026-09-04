@testable import Grain
import SwiftUI
import XCTest

/// The comment sheet, which is reused from three places — the gallery detail,
/// a feed card, and the story viewer — each handing it a different set of
/// callbacks and a different way to dismiss.
@MainActor
final class CommentSheetRenderTests: GrainTestCase {
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

    /// The sheet is used from the gallery detail, the card, and the story
    /// viewer, each handing it a different set of callbacks and a different
    /// dismiss affordance.
    func testTheCommentSheetRendersInEachOfItsConfigurations() {
        MockURLProtocol.respondByPath(Fixtures.routes)
        let env = TestEnvironment()

        let author = GrainProfile(
            cid: "c1", did: "did:plc:someone", handle: "someone.test",
            displayName: "Someone", avatar: "https://test.local/a.jpg"
        )
        let comments = [
            GrainComment(
                uri: "at://did:plc:someone/social.grain.comment/1", cid: "bafy1", author: author,
                text: "A comment with a #hashtag and an @someone.test mention.",
                createdAt: Fixtures.freshTimestamp, favCount: 3,
                viewer: CommentViewerState(fav: "at://did:plc:test/social.grain.favorite/1")
            ),
            GrainComment(
                uri: "at://did:plc:test/social.grain.comment/2", cid: "bafy2",
                author: GrainProfile(cid: "c2", did: "did:plc:test", handle: "tester.grain.social"),
                text: "Your own comment, which you can delete.",
                replyTo: "at://did:plc:someone/social.grain.comment/1",
                createdAt: Fixtures.freshTimestamp
            ),
        ]

        for style in [CommentDismissStyle.xmark, .done] {
            ViewRender.render(
                CommentSheetContent(
                    comments: comments,
                    isLoading: false,
                    isPostingComment: false,
                    client: env.client,
                    onPost: { _, _ in },
                    onDelete: { _ in },
                    onDismiss: {},
                    onProfileTap: { _ in },
                    onHashtagTap: { _ in },
                    onStoryTap: { _ in },
                    dismissStyle: style,
                    focusOnAppear: style == .done
                )
                .withTestEnvironment(env),
                settle: settle
            )
        }
    }

    /// Signed out there is nothing to post with, so the input is absent.
    func testTheCommentSheetRendersWhileSignedOut() {
        MockURLProtocol.respondByPath(Fixtures.routes)
        let env = TestEnvironment(authenticated: false)

        ViewRender.render(
            CommentSheetContent(
                comments: [],
                isLoading: false,
                isPostingComment: false,
                client: env.client,
                onPost: { _, _ in },
                onDelete: { _ in }
            )
            .withTestEnvironment(env),
            settle: settle
        )
    }
}

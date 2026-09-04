@testable import Grain
import SwiftUI
import XCTest

/// How a screen changes with who is looking at it — the relationship between
/// the viewer and the account on screen, and whether there is a signed-in
/// account at all.
///
/// Signed out is not a smaller version of signed in: whole action rows and
/// sections are absent, and a block in either direction replaces the content
/// entirely. Those branches are easy to break without noticing, because the
/// signed-in path is the one anyone developing the app looks at.
@MainActor
final class ViewerStateRenderTests: XCTestCase {
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

    private let settle: TimeInterval = 0.4

    private static func profile(viewer: String) -> String {
        """
        {
          "cid": "bafycid",
          "did": "did:plc:someone",
          "handle": "someone.test",
          "displayName": "Someone",
          "description": "A profile with a description long enough to wrap onto a second line.",
          "followersCount": 1200,
          "followsCount": 34,
          "galleryCount": 5,
          "createdAt": "2025-01-01T00:00:00Z",
          "viewer": \(viewer)
        }
        """
    }

    // MARK: - Relationship to the account on screen

    /// Following, followed-back, mutual, blocking, blocked-by and muted each
    /// swap the action row — and the two block states replace the body.
    func testAProfileRendersForEachRelationship() {
        let relationships = [
            #"{}"#,
            #"{"following": "at://did:plc:test/social.grain.graph.follow/1"}"#,
            #"{"followedBy": "at://did:plc:someone/social.grain.graph.follow/1"}"#,
            #"{"following": "at://f/1", "followedBy": "at://f/2"}"#,
            #"{"blocking": "at://did:plc:test/social.grain.graph.block/1"}"#,
            #"{"blockedBy": true}"#,
            #"{"muted": true}"#,
        ]

        for viewer in relationships {
            MockURLProtocol.respondByPath(["getActorProfile": Self.profile(viewer: viewer)], fallback: "{}")
            let env = TestEnvironment()
            ViewRender.render(
                ProfileView(client: env.client, did: "did:plc:someone", isRoot: false)
                    .withTestEnvironment(env),
                settle: settle
            )
        }
    }

    // MARK: - Signed out

    /// A profile still has to render for someone with no account — just
    /// without follow, block or report.
    func testAProfileRendersWhileSignedOut() {
        MockURLProtocol.respondByPath(["getActorProfile": Self.profile(viewer: "{}")], fallback: "{}")
        let env = TestEnvironment(authenticated: false)

        ViewRender.render(
            ProfileView(client: env.client, did: "did:plc:someone", isRoot: false).withTestEnvironment(env),
            settle: settle
        )
    }

    func testTheFeedRendersWhileSignedOut() {
        MockURLProtocol.respondByPath(Fixtures.routes)
        let env = TestEnvironment(authenticated: false)

        ViewRender.render(FeedView(client: env.client).withTestEnvironment(env), settle: settle)
    }

    func testSettingsRendersWhileSignedOut() {
        MockURLProtocol.respondByPath(Fixtures.routes)
        let env = TestEnvironment(authenticated: false)

        ViewRender.render(SettingsView(client: env.client).withTestEnvironment(env), settle: settle)
    }

    // MARK: - The account switcher

    /// The switcher only draws rows once the Keychain has accounts in it, so
    /// this section is unreachable from a default environment.
    func testSettingsRendersTheSwitcherWithSeveralAccounts() {
        MockURLProtocol.respondByPath(Fixtures.routes)
        let env = TestEnvironment()
        env.auth.accounts = [
            StoredAccount(did: "did:plc:test", handle: "tester.grain.social", avatar: "https://test.local/a.jpg"),
            StoredAccount(did: "did:plc:other", handle: "other.test", avatar: nil),
        ]
        env.auth.userHandle = "tester.grain.social"
        env.auth.userAvatar = "https://test.local/a.jpg"

        ViewRender.render(SettingsView(client: env.client).withTestEnvironment(env), settle: settle)
    }

    // MARK: - Labelled content

    /// A content-level label replaces a card with its warning, so none of the
    /// photo layout below it runs.
    func testAFeedOfLabelledGalleriesRendersBehindItsWarning() {
        MockURLProtocol.respondByPath([
            "getFeed": """
            {"items": [{
              "uri": "at://did:plc:test/social.grain.gallery/1",
              "cid": "bafyg",
              "title": "A labelled gallery",
              "creator": {"cid": "c1", "did": "did:plc:test", "handle": "tester.test"},
              "items": [{
                "uri": "at://did:plc:test/social.grain.photo/1",
                "cid": "bafyp",
                "thumb": "https://test.local/thumb.jpg",
                "fullsize": "https://test.local/full.jpg",
                "aspectRatio": {"width": 3, "height": 2}
              }],
              "labels": [{"val": "!warn"}],
              "indexedAt": "2025-01-02T00:00:00Z"
            }], "cursor": null}
            """,
        ], fallback: "{}")
        let env = TestEnvironment()

        ViewRender.render(FeedView(client: env.client).withTestEnvironment(env), settle: settle)
    }
}

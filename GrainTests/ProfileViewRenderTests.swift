@testable import Grain
import SwiftUI
import XCTest

/// ProfileView is the largest view in the app and none of it was reachable from
/// the existing suite. These render it in each of the states it branches on so
/// the layout code runs at all.
@MainActor
final class ProfileViewRenderTests: XCTestCase {
    private var keychain: KeychainGuard!

    /// Async overrides: the synchronous `setUp`/`tearDown` are nonisolated, so
    /// touching main-actor state from them warns.
    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainGuard(userDID: "did:plc:test")
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        keychain.restore()
        try await super.tearDown()
    }

    private static let profileJSON = """
    {
      "cid": "bafycid",
      "did": "did:plc:test",
      "handle": "tester.grain.social",
      "displayName": "Tester",
      "description": "A test profile with a description long enough to wrap.",
      "followersCount": 12,
      "followsCount": 34,
      "galleryCount": 5,
      "createdAt": "2025-01-01T00:00:00Z"
    }
    """

    func testRendersOwnProfile() {
        MockURLProtocol.respondWithJSON(Self.profileJSON)
        let env = TestEnvironment()

        ViewRender.render(
            ProfileView(client: env.client, did: "did:plc:test", isRoot: true)
                .withTestEnvironment(env)
        )
    }

    func testRendersOtherUsersProfile() {
        MockURLProtocol.respondWithJSON(Self.profileJSON)
        let env = TestEnvironment()

        ViewRender.render(
            ProfileView(client: env.client, did: "did:plc:someone-else", isRoot: false)
                .withTestEnvironment(env)
        )
    }

    /// The empty/failed load path renders a different branch than the loaded one.
    func testRendersWhenTheProfileFailsToLoad() {
        MockURLProtocol.respondWithError(statusCode: 500)
        let env = TestEnvironment()

        ViewRender.render(
            ProfileView(client: env.client, did: "did:plc:test", isRoot: true)
                .withTestEnvironment(env)
        )
    }
}

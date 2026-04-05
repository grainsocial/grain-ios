@testable import Grain
import XCTest

@MainActor
final class ProfileDetailViewModelTests: XCTestCase {
    private var client: XRPCClient!
    private var vm: ProfileDetailViewModel!

    override func setUp() {
        super.setUp()
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        vm = ProfileDetailViewModel(client: client)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeProfile(
        did: String = "did:plc:target",
        followersCount: Int? = 10,
        following: String? = nil
    ) -> GrainProfileDetailed {
        GrainProfileDetailed(
            cid: "cid",
            did: did,
            handle: "target.test",
            followersCount: followersCount,
            viewer: ActorViewerState(following: following)
        )
    }

    private func makeDummyAuth() -> AuthContext {
        // DPoP needs a real key for signing — create one for tests
        do {
            let key = try CryptoKit.P256.Signing.PrivateKey()
            let dpop = DPoP(privateKey: key)
            return AuthContext(accessToken: "test-token", dpop: dpop)
        } catch {
            XCTFail("Failed to create P256 private key: \(error)")
            fatalError("Unreachable")
        }
    }

    // MARK: - toggleFollow (follow)

    func testFollowOptimisticallyUpdatesState() async {
        vm.profile = makeProfile(followersCount: 10, following: nil)
        TokenStorage.userDID = "did:plc:me"

        // Mock createRecord response
        MockURLProtocol.respondWithJSON("""
        {"uri": "at://did:plc:me/social.grain.graph.follow/abc123", "cid": "newcid"}
        """)

        await vm.toggleFollow(auth: makeDummyAuth())

        XCTAssertEqual(vm.profile?.followersCount, 11)
        XCTAssertEqual(vm.profile?.viewer?.following, "at://did:plc:me/social.grain.graph.follow/abc123")
    }

    func testFollowRollsBackOnFailure() async {
        vm.profile = makeProfile(followersCount: 10, following: nil)
        TokenStorage.userDID = "did:plc:me"

        MockURLProtocol.respondWithError(statusCode: 500)

        await vm.toggleFollow(auth: makeDummyAuth())

        // Should roll back to original state
        XCTAssertEqual(vm.profile?.followersCount, 10)
        XCTAssertNil(vm.profile?.viewer?.following)
    }

    // MARK: - toggleFollow (unfollow)

    func testUnfollowOptimisticallyUpdatesState() async {
        vm.profile = makeProfile(followersCount: 10, following: "at://did:plc:me/social.grain.graph.follow/xyz")

        MockURLProtocol.respondWithJSON("{}")

        await vm.toggleFollow(auth: makeDummyAuth())

        XCTAssertEqual(vm.profile?.followersCount, 9)
        XCTAssertNil(vm.profile?.viewer?.following)
    }

    func testUnfollowRollsBackOnFailure() async {
        let followUri = "at://did:plc:me/social.grain.graph.follow/xyz"
        vm.profile = makeProfile(followersCount: 10, following: followUri)

        MockURLProtocol.respondWithError(statusCode: 500)

        await vm.toggleFollow(auth: makeDummyAuth())

        XCTAssertEqual(vm.profile?.followersCount, 10)
        XCTAssertEqual(vm.profile?.viewer?.following, followUri)
    }

    func testUnfollowClampsCountAtZero() async {
        vm.profile = makeProfile(followersCount: 0, following: "at://did:plc:me/social.grain.graph.follow/xyz")

        MockURLProtocol.respondWithJSON("{}")

        await vm.toggleFollow(auth: makeDummyAuth())

        XCTAssertEqual(vm.profile?.followersCount, 0)
    }

    // MARK: - toggleFollow guards

    func testToggleFollowBailsWithoutAuth() async {
        vm.profile = makeProfile()
        let initialCount = vm.profile?.followersCount

        await vm.toggleFollow(auth: nil)

        XCTAssertEqual(vm.profile?.followersCount, initialCount)
    }

    func testToggleFollowBailsWithoutProfile() async {
        vm.profile = nil

        await vm.toggleFollow(auth: makeDummyAuth())
        // Should not crash
    }
}

import CryptoKit

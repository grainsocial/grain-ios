@testable import Grain
import SwiftUI
import XCTest

/// The pieces of a profile header: the follower and gallery counts, and the
/// full-screen lightbox a profile picture opens into.
@MainActor
final class ProfileHeaderRenderTests: GrainTestCase {
    private var account: TestAccount!

    /// Async overrides: the synchronous `setUp`/`tearDown` are nonisolated, so
    /// touching main-actor state from them warns.
    override func setUp() async throws {
        try await super.setUp()
        account = TestAccount()
        MockURLProtocol.respondByPath(Fixtures.routes)
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        account.restore()
        try await super.tearDown()
    }

    // MARK: - Avatar lightbox

    /// Tapping a profile picture opens it full screen with its own zoom state
    /// and a swipe-to-dismiss.
    func testRendersTheAvatarOverlay() {
        ViewRender.render(
            AvatarOverlay(url: "https://test.local/avatar.jpg", onDismiss: {}), settle: 0.3
        )
    }

    /// An avatar URL the loader can't parse still has to put the overlay up —
    /// otherwise the tap appears to do nothing.
    func testRendersTheAvatarOverlayWithAnUnusableURL() {
        ViewRender.render(AvatarOverlay(url: "", onDismiss: {}), settle: 0.2)
        ViewRender.render(AvatarOverlay(url: "not a url", onDismiss: {}), settle: 0.2)
    }

    // MARK: - Profile stats

    func testRendersEachProfileStat() {
        for (count, label) in [(0, "galleries"), (1, "follower"), (1200, "followers")] {
            ViewRender.render(StatView(count: count, label: label), settle: 0)
        }
    }
}

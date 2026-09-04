@testable import Grain
import SwiftUI
import XCTest

/// The app's top-level screens, none of which were reachable from the existing
/// suite. Rendering a screen also renders the cards, rows and strips it is
/// built from, so these cover a good deal more than the file they name.
@MainActor
final class ScreenRenderTests: XCTestCase {
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

    // MARK: - Feed

    func testRendersFeed() {
        MockURLProtocol.respondWithJSON(Fixtures.feed)
        let env = TestEnvironment()
        ViewRender.render(FeedView(client: env.client).withTestEnvironment(env))
    }

    func testRendersFeedWhenItFailsToLoad() {
        MockURLProtocol.respondWithError(statusCode: 500)
        let env = TestEnvironment()
        ViewRender.render(FeedView(client: env.client).withTestEnvironment(env))
    }

    func testRendersFeedWhenEmpty() {
        MockURLProtocol.respondWithJSON(#"{"items": [], "cursor": null}"#)
        let env = TestEnvironment()
        ViewRender.render(FeedView(client: env.client).withTestEnvironment(env))
    }

    // MARK: - Search

    func testRendersSearch() {
        MockURLProtocol.respondWithJSON(Fixtures.feed)
        let env = TestEnvironment()
        ViewRender.render(SearchView(client: env.client).withTestEnvironment(env))
    }

    func testRendersSearchWhenItFailsToLoad() {
        MockURLProtocol.respondWithError(statusCode: 500)
        let env = TestEnvironment()
        ViewRender.render(SearchView(client: env.client).withTestEnvironment(env))
    }

    // MARK: - Notifications

    func testRendersNotifications() {
        MockURLProtocol.respondWithJSON(Fixtures.notifications)
        let env = TestEnvironment()
        let vm = NotificationsViewModel(client: env.client)
        ViewRender.render(
            NotificationsView(client: env.client, viewModel: vm).withTestEnvironment(env)
        )
    }

    func testRendersNotificationsWhenEmpty() {
        MockURLProtocol.respondWithJSON(#"{"notifications": [], "cursor": null}"#)
        let env = TestEnvironment()
        let vm = NotificationsViewModel(client: env.client)
        ViewRender.render(
            NotificationsView(client: env.client, viewModel: vm).withTestEnvironment(env)
        )
    }

    // MARK: - Settings

    func testRendersSettings() {
        MockURLProtocol.respondWithJSON("{}")
        let env = TestEnvironment()
        ViewRender.render(SettingsView(client: env.client).withTestEnvironment(env))
    }

    // MARK: - Tab tree

    /// MainTabView builds the whole signed-in tree, so this reaches the tab
    /// bar, the selected tab's screen and the shared chrome around them.
    func testRendersMainTabTree() {
        MockURLProtocol.respondWithJSON(Fixtures.feed)
        let env = TestEnvironment()
        ViewRender.render(
            MainTabView(pendingDeepLink: .constant(nil)).withTestEnvironment(env),
            settle: 0.2
        )
    }
}

@testable import Grain
import SwiftUI
import XCTest

/// The screens behind Settings' navigation links. Each is its own view with its
/// own load, so rendering the Settings list never reaches them — they only
/// appear once something is pushed.
@MainActor
final class SettingsDestinationRenderTests: XCTestCase {
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
        MockURLProtocol.stopInterceptingSharedSession()
        MockURLProtocol.handler = nil
        account.restore()
        try await super.tearDown()
    }

    private let settle: TimeInterval = 0.3

    // MARK: - Account rows

    /// The switcher draws a row per account, and the active one is marked and
    /// unselectable so you can't switch to where you already are.
    func testRendersAnAccountRowInEachState() {
        let signedIn = StoredAccount(did: "did:plc:test", handle: "tester.grain.social", avatar: "https://test.local/a.jpg")
        let other = StoredAccount(did: "did:plc:other", handle: "other.test", avatar: nil)

        ViewRender.render(AccountRow(account: signedIn, isActive: true, isSwitching: false, onTap: {}), settle: 0)
        ViewRender.render(AccountRow(account: other, isActive: false, isSwitching: false, onTap: {}), settle: 0)
        ViewRender.render(AccountRow(account: other, isActive: false, isSwitching: true, onTap: {}), settle: 0)
    }

    /// An account whose handle never resolved falls back to its DID rather than
    /// drawing a blank row.
    func testAnAccountWithNoHandleFallsBackToItsDID() {
        let nameless = StoredAccount(did: "did:plc:nameless", handle: nil, avatar: nil)

        ViewRender.render(AccountRow(account: nameless, isActive: false, isSwitching: false, onTap: {}), settle: 0)
    }

    // MARK: - Account detail

    func testRendersTheAccountDetailScreen() {
        let env = TestEnvironment()
        env.auth.userHandle = "tester.grain.social"

        ViewRender.render(
            AccountDetailView(client: env.client).withTestEnvironment(env), settle: settle
        )
    }

    /// Signed out there is no handle or DID to show, and the destructive
    /// actions have nothing to act on.
    func testRendersTheAccountDetailScreenWithNoSession() {
        let env = TestEnvironment(authenticated: false)

        ViewRender.render(
            AccountDetailView(client: env.client).withTestEnvironment(env), settle: settle
        )
    }

    // MARK: - Adding an account

    /// Signing in to a second account without disturbing the first.
    func testRendersTheAddAccountScreen() {
        let env = TestEnvironment()

        ViewRender.render(AddAccountView().withTestEnvironment(env), settle: settle)
    }

    // MARK: - Feeds and appearance

    func testRendersTheFeedsSettingsScreen() {
        ViewRender.render(FeedsSettingsView(), settle: 0)
    }

    /// The appearance list marks whichever option is stored, so it has to be
    /// rendered against each of them.
    func testRendersTheAppearanceScreenForEachOption() {
        let key = "appearance"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        for option in ["auto", "light", "dark"] {
            UserDefaults.standard.set(option, forKey: key)
            ViewRender.render(AppearanceSettingsView(), settle: 0.1)
        }
    }

    // MARK: - Upload defaults

    /// The toggles are seeded from the account's stored preferences, so this
    /// only shows real state once that fetch lands.
    func testRendersTheUploadDefaultsScreen() {
        let env = TestEnvironment()

        ViewRender.render(
            UploadDefaultsView(client: env.client).withTestEnvironment(env), settle: settle
        )
    }

    /// With the preferences fetch failing the toggles stay on their defaults
    /// rather than the screen breaking.
    func testRendersTheUploadDefaultsScreenWhenPreferencesFailToLoad() {
        MockURLProtocol.respondWithError(statusCode: 500)
        let env = TestEnvironment()

        ViewRender.render(
            UploadDefaultsView(client: env.client).withTestEnvironment(env), settle: settle
        )
    }

    /// Signed out there is no context to fetch preferences with.
    func testRendersTheUploadDefaultsScreenWithNoSession() {
        let env = TestEnvironment(authenticated: false)

        ViewRender.render(
            UploadDefaultsView(client: env.client).withTestEnvironment(env), settle: settle
        )
    }
}

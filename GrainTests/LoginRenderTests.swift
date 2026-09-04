@testable import Grain
import SwiftUI
import XCTest

/// The sign-in screen once a handle is being typed. Most of it — the
/// suggestions list, the highlighted row, the error line, the re-auth notice —
/// only exists past a keystroke, so an empty render never reaches it.
@MainActor
final class LoginRenderTests: GrainTestCase {
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

    private func suggestions(_ count: Int) -> [ActorSuggestion] {
        let names = ["alice", "alastair", "alba", "aled", "alex", "alfie"]
        return (0 ..< count).map { index in
            ActorSuggestion(
                handle: "\(names[index % names.count]).grain.social",
                displayName: index.isMultiple(of: 2) ? names[index % names.count].capitalized : nil,
                avatar: index.isMultiple(of: 3) ? nil : "https://test.local/\(index).jpg"
            )
        }
    }

    private func render(handle: String = "", suggestions: [ActorSuggestion] = [], settle: TimeInterval = 0.3) {
        let env = TestEnvironment(authenticated: false)
        ViewRender.render(
            LoginView(handle: handle, suggestions: suggestions).withTestEnvironment(env),
            settle: settle
        )
    }

    /// The screen as it opens — marketing copy, no field content, no results.
    func testRendersTheSignInScreenBeforeAnyTyping() {
        render()
    }

    /// A partial handle with matches behind it: the suggestions list replaces
    /// the copy above the field.
    func testRendersTheSuggestionsList() {
        render(handle: "al", suggestions: suggestions(5))
    }

    /// One result and a full list are laid out differently — the last row has
    /// no separator under it.
    func testRendersTheSuggestionsListAtEachSize() {
        for count in [1, 2, 6] {
            render(handle: "al", suggestions: suggestions(count))
        }
    }

    /// A suggestion with no display name falls back to the handle, and one with
    /// no avatar falls back to the placeholder.
    func testRendersSuggestionsMissingTheirDetails() {
        render(handle: "al", suggestions: [
            ActorSuggestion(handle: "bare.grain.social", displayName: nil, avatar: nil),
            ActorSuggestion(handle: "named.grain.social", displayName: "Named", avatar: nil),
        ])
    }

    /// Typed something that matched nothing — the field is filled but the list
    /// stays empty, which is a third state again.
    func testRendersATypedHandleWithNoMatches() {
        render(handle: "nobodyhasthishandle", suggestions: [])
    }

    /// A full handle is what the Go key submits.
    func testRendersACompleteHandle() {
        render(handle: "tester.grain.social", suggestions: [])
    }

    /// After a scope bump the screen carries a notice explaining why everyone
    /// got signed out.
    func testRendersTheReauthNotice() {
        let env = TestEnvironment(authenticated: false)
        env.auth.reauthReason = "Grain has been updated. Please sign in again to enable new features."

        ViewRender.render(LoginView().withTestEnvironment(env), settle: 0.3)
    }

    /// The notice is suppressed while suggestions are up, so the list isn't
    /// pushed off screen by it.
    func testTheReauthNoticeStepsAsideForSuggestions() {
        let env = TestEnvironment(authenticated: false)
        env.auth.reauthReason = "Grain has been updated."

        ViewRender.render(
            LoginView(handle: "al", suggestions: suggestions(3)).withTestEnvironment(env),
            settle: 0.3
        )
    }

    // MARK: - Suggestion model

    /// Rows are diffed on the handle, so two accounts must never collide.
    func testSuggestionsAreIdentifiedByHandle() {
        let alice = ActorSuggestion(handle: "alice.grain.social", displayName: "Alice", avatar: nil)

        XCTAssertEqual(alice.id, "alice.grain.social")
        XCTAssertEqual(alice, ActorSuggestion(handle: "alice.grain.social", displayName: "Alice", avatar: nil))
        XCTAssertNotEqual(alice, ActorSuggestion(handle: "bob.grain.social", displayName: "Alice", avatar: nil))
    }

    // MARK: - Legal copy

    /// The three links are a compliance requirement, so they're pinned
    /// alongside the rendering.
    func testTheLegalLineCarriesAllThreeLinks() throws {
        let attributed = try AttributedString(markdown: LoginView.legalMarkdown)
        let urls = attributed.runs.compactMap { $0.link?.absoluteString }

        XCTAssertEqual(Set(urls).count, 3)
    }
}

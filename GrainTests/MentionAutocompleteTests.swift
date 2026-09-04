@testable import Grain
import XCTest

/// The @ detection runs on every keystroke in a comment box, and getting it
/// wrong either pops a suggestion strip over an email address or fails to offer
/// one at all. Detection and completion are synchronous; only the lookup they
/// trigger is not, so these stay off the network by clearing before it fires.
@MainActor
final class MentionAutocompleteTests: XCTestCase {
    private var state: MentionAutocompleteState!

    override func setUp() async throws {
        try await super.setUp()
        state = MentionAutocompleteState()
    }

    override func tearDown() async throws {
        // Cancels the debounced lookup so it can't outlive the test.
        state.clear()
        state = nil
        try await super.tearDown()
    }

    /// `update` sets the query synchronously and only then schedules the search,
    /// so the query can be read without waiting for the network.
    private func query(after text: String) -> String? {
        state.update(text: text)
        let result = state.activeQuery
        state.clear()
        return result
    }

    // MARK: - Detection

    func testAnAtAtTheStartOfTheTextStartsAMention() {
        XCTAssertEqual(query(after: "@ali"), "ali")
    }

    func testAnAtAfterASpaceStartsAMention() {
        XCTAssertEqual(query(after: "nice shot @ali"), "ali")
    }

    func testAnAtAfterANewlineStartsAMention() {
        XCTAssertEqual(query(after: "nice shot\n@ali"), "ali")
    }

    /// The classic false positive: an email address is not a mention.
    func testAnAtInTheMiddleOfAWordIsNotAMention() {
        XCTAssertNil(query(after: "mail me at chad@example.com"))
    }

    func testABareAtIsNotYetAMention() {
        XCTAssertNil(query(after: "@"))
        XCTAssertNil(query(after: "hello @"))
    }

    /// Once a space follows the handle the user has moved on, so the strip has
    /// to go away rather than keep matching the finished handle.
    func testASpaceAfterTheHandleEndsTheMention() {
        XCTAssertNil(query(after: "@alice.grain.social nice"))
    }

    func testTextWithNoAtIsNotAMention() {
        XCTAssertNil(query(after: "just a caption"))
        XCTAssertNil(query(after: ""))
    }

    /// Only the mention being typed matters, not one already finished earlier
    /// in the sentence.
    func testTheLastAtWins() {
        XCTAssertEqual(query(after: "@alice.test and @bo"), "bo")
    }

    func testAPartialHandleWithDotsIsCarriedThrough() {
        XCTAssertEqual(query(after: "@alice.grain."), "alice.grain.")
    }

    // MARK: - isActive

    func testTheStripIsOnlyActiveWhileAMentionIsBeingTyped() {
        XCTAssertFalse(state.isActive)

        state.update(text: "@ali")
        XCTAssertTrue(state.isActive)

        state.update(text: "@alice.test done")
        XCTAssertFalse(state.isActive)
    }

    func testClearingTakesTheStripDownAndDropsTheSuggestions() {
        state.update(text: "@ali")
        state.suggestions = [MentionSuggestion(handle: "alice.test", displayName: "Alice", avatar: nil)]

        state.clear()

        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.activeQuery)
        XCTAssertTrue(state.suggestions.isEmpty)
    }

    // MARK: - complete

    func testCompletingReplacesThePartialHandleAndAddsATrailingSpace() {
        var text = "nice shot @ali"
        state.update(text: text)

        state.complete(handle: "alice.grain.social", in: &text)

        XCTAssertEqual(text, "nice shot @alice.grain.social ")
    }

    func testCompletingAtTheStartOfTheText() {
        var text = "@ali"
        state.update(text: text)

        state.complete(handle: "alice.grain.social", in: &text)

        XCTAssertEqual(text, "@alice.grain.social ")
    }

    /// Only the mention under the cursor should be rewritten — an earlier,
    /// already-complete mention has to survive untouched.
    func testCompletingLeavesAnEarlierMentionAlone() {
        var text = "@bob.test hi @ali"
        state.update(text: text)

        state.complete(handle: "alice.test", in: &text)

        XCTAssertEqual(text, "@bob.test hi @alice.test ")
    }

    func testCompletingTakesTheStripDown() {
        var text = "@ali"
        state.update(text: text)

        state.complete(handle: "alice.test", in: &text)

        XCTAssertFalse(state.isActive)
        XCTAssertTrue(state.suggestions.isEmpty)
    }

    /// Nothing is being typed, so there is nothing to replace — the text must
    /// come back unchanged rather than gaining a stray handle.
    func testCompletingWithNoActiveMentionLeavesTheTextAlone() {
        var text = "just a caption"

        state.complete(handle: "alice.test", in: &text)

        XCTAssertEqual(text, "just a caption")
    }

    // MARK: - MentionSuggestion

    func testSuggestionsAreIdentifiedByHandle() {
        let suggestion = MentionSuggestion(handle: "alice.test", displayName: "Alice", avatar: nil)

        XCTAssertEqual(suggestion.id, "alice.test")
        XCTAssertEqual(suggestion, MentionSuggestion(handle: "alice.test", displayName: "Alice", avatar: nil))
        XCTAssertNotEqual(suggestion, MentionSuggestion(handle: "bob.test", displayName: "Alice", avatar: nil))
    }
}

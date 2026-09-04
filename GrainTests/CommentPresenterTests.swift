@testable import Grain
import SwiftUI
import UIKit
import XCTest

/// The story comment sheet is presented from its own `UIWindow` so the sheet's
/// lifecycle can't tear down the story viewer underneath it. That means the
/// presenter has real preconditions — an environment, and a foreground-active
/// scene — and a dismissal path that has to be deferred off the current run
/// loop turn or it re-enters SwiftUI mid-teardown.
@MainActor
final class CommentPresenterTests: GrainTestCase {
    private var env: TestEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.respondByPath(Fixtures.routes)
        env = TestEnvironment()
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        env = nil
        try await super.tearDown()
    }

    private func makePresenter(configured: Bool = true) -> StoryCommentPresenter {
        let presenter = StoryCommentPresenter()
        if configured {
            presenter.configure(
                auth: env.auth,
                storyStatusCache: env.storyStatus,
                viewedStories: env.viewedStories
            )
        }
        return presenter
    }

    private func open(_ presenter: StoryCommentPresenter, focusInput: Bool = false) {
        presenter.open(
            storyUri: "at://did:plc:test/social.grain.story/1",
            focusInput: focusInput,
            commentsViewModel: StoryCommentsViewModel(client: env.client),
            client: env.client
        )
    }

    /// Lets the presentation (or its dismissal) actually run.
    private func pump(_ seconds: TimeInterval = 0.4) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Let the sheet finish presenting.
    ///
    /// This one genuinely has to be a fixed wait: `presentedStoryUri` is set
    /// synchronously inside `open()`, so it is not a signal that the
    /// presentation has completed — and closing a sheet mid-present is ignored,
    /// which wedges the dismissal that follows.
    private func pumpUntilPresented(_ presenter: StoryCommentPresenter) {
        pump(0.5)
        XCTAssertNotNil(presenter.presentedStoryUri)
    }

    /// Presentation and dismissal are real SwiftUI sheet transitions, so how
    /// long they take depends on how busy the machine is. Pump until the state
    /// settles rather than for a fixed spell.
    private func pump(until condition: () -> Bool, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            pump(0.1)
        }
        return condition()
    }

    /// The window has to come from a scene that's actually on screen.
    private func requireForegroundScene() throws {
        let hasScene = UIApplication.shared.connectedScenes.contains {
            ($0 as? UIWindowScene)?.activationState == .foregroundActive
        }
        try XCTSkipUnless(hasScene, "No foreground-active window scene in this test host")
    }

    // MARK: - Preconditions

    /// Without `configure` there is no auth to hand the sheet, so presenting
    /// one would put a signed-out comment box over someone's story.
    func testOpeningBeforeConfiguringIsDeclined() {
        let presenter = makePresenter(configured: false)

        open(presenter)

        XCTAssertNil(presenter.presentedStoryUri)
    }

    /// Called on teardown regardless of whether anything was ever opened.
    func testClosingWithNothingOpenIsHarmless() {
        let presenter = makePresenter()

        presenter.close()

        XCTAssertNil(presenter.presentedStoryUri)
    }

    // MARK: - Presenting

    func testOpeningRecordsTheStoryItIsShowing() throws {
        try requireForegroundScene()
        let presenter = makePresenter()
        defer { presenter.close(); pump(0.1) }

        open(presenter)
        pumpUntilPresented(presenter)

        XCTAssertEqual(presenter.presentedStoryUri, "at://did:plc:test/social.grain.story/1")
    }

    /// A double-tap on the comment button must not stack two sheets.
    func testASecondOpenWhileOneIsUpIsIgnored() throws {
        try requireForegroundScene()
        let presenter = makePresenter()
        defer { presenter.close(); pump(0.1) }

        open(presenter)
        pumpUntilPresented(presenter)
        presenter.open(
            storyUri: "at://did:plc:test/social.grain.story/2",
            focusInput: false,
            commentsViewModel: StoryCommentsViewModel(client: env.client),
            client: env.client
        )
        pump(0.1)

        XCTAssertEqual(
            presenter.presentedStoryUri, "at://did:plc:test/social.grain.story/1",
            "The second open should have been turned away, not retargeted the sheet"
        )
    }

    /// Closing has to clear the presented story so the story viewer's own state
    /// mirror follows it back down.
    func testClosingClearsThePresentedStory() throws {
        try requireForegroundScene()
        let presenter = makePresenter()

        open(presenter)
        pumpUntilPresented(presenter)
        XCTAssertNotNil(presenter.presentedStoryUri)

        presenter.close()

        XCTAssertTrue(
            pump(until: { presenter.presentedStoryUri == nil }),
            "The sheet never finished dismissing"
        )
    }

    /// The window is built once per session and reused, so a second open after
    /// a close has to work rather than being blocked by leftover state.
    func testTheSheetCanBeOpenedAgainAfterItIsClosed() throws {
        try requireForegroundScene()
        let presenter = makePresenter()
        defer { presenter.close(); pump(0.1) }

        open(presenter)
        pumpUntilPresented(presenter)
        presenter.close()
        XCTAssertTrue(pump(until: { presenter.presentedStoryUri == nil }), "The first sheet never dismissed")

        open(presenter)

        XCTAssertTrue(
            pump(until: { presenter.presentedStoryUri != nil }),
            "The window is reused across opens, so a second open has to work"
        )
    }

    /// Opening from the comment button focuses the input, which is a different
    /// presentation than opening from the count.
    func testOpeningWithTheInputFocused() throws {
        try requireForegroundScene()
        let presenter = makePresenter()
        defer { presenter.close(); pump(0.1) }

        open(presenter, focusInput: true)
        pumpUntilPresented(presenter)

        XCTAssertNotNil(presenter.presentedStoryUri)
    }

    // MARK: - The sheet target

    /// `.sheet(item:)` treats each new identity as a new presentation, so two
    /// targets for the same story must not compare equal.
    func testEachSheetTargetIsItsOwnPresentation() {
        let viewModel = StoryCommentsViewModel(client: env.client)
        let first = CommentSheetTarget(
            storyUri: "at://did:plc:test/social.grain.story/1",
            focusInput: false,
            viewModel: viewModel,
            client: env.client
        )
        let second = CommentSheetTarget(
            storyUri: "at://did:plc:test/social.grain.story/1",
            focusInput: false,
            viewModel: viewModel,
            client: env.client
        )

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, first)
        XCTAssertEqual(first.id, first.id)
    }
}

@testable import Grain
import SwiftUI
import XCTest

/// What advances a story. Five seconds per story, ticking twenty times a
/// second, with a pause that has to resume where it left off rather than start
/// over — holding a finger down mid-story and letting go shouldn't rewind it.
@MainActor
final class StoryTimerTests: GrainTestCase {
    /// A story that runs in a fifth of a second rather than five. The ticker
    /// works in fractions of the duration, so every assertion below holds at
    /// either speed — it just isn't worth a minute of the suite's time to watch
    /// real stories play out.
    private func makeTimer(duration: TimeInterval = 0.2) -> StoryTimer {
        StoryTimer(duration: duration)
    }

    /// Pump the run loop so the timer's task gets to tick.
    private func advance(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            advance(0.01)
        }
        return condition()
    }

    func testATimerStartsIdleAtZero() {
        let timer = makeTimer()

        XCTAssertEqual(timer.progress, 0)
        XCTAssertFalse(timer.isRunning)
    }

    func testStartingRunsTheProgressForward() {
        let timer = makeTimer(duration: 1)
        defer { timer.stop() }

        timer.start()

        XCTAssertTrue(timer.isRunning)
        XCTAssertTrue(waitUntil { timer.progress > 0.1 }, "The bar never moved")
    }

    /// The story advances when the bar fills, so this is what pages the viewer.
    func testItReportsCompletionWhenTheBarFills() {
        let timer = makeTimer()
        defer { timer.stop() }
        var completed = false
        timer.onComplete = { completed = true }

        timer.start()

        XCTAssertTrue(waitUntil({ completed }, timeout: 30), "The story never finished")
        XCTAssertEqual(timer.progress, 1, accuracy: 0.01)
        XCTAssertFalse(timer.isRunning)
    }

    /// Fires once, early, so a story counts as viewed almost immediately rather
    /// than only if you sit through all five seconds.
    func testItReportsTheViewOnceShortlyAfterStarting() {
        let timer = makeTimer()
        defer { timer.stop() }
        var quarterCount = 0
        timer.onQuarter = { quarterCount += 1 }

        timer.start()

        XCTAssertTrue(waitUntil { quarterCount > 0 }, "The story was never marked viewed")
        _ = waitUntil({ timer.progress > 0.5 }, timeout: 5)
        XCTAssertEqual(quarterCount, 1, "Marking viewed more than once would re-post the read receipt")
    }

    /// Holding a finger on a story pauses it; letting go resumes from where it
    /// stopped, not from the beginning.
    func testResumingPicksUpWhereItStopped() {
        let timer = makeTimer(duration: 1)
        defer { timer.stop() }

        timer.start()
        XCTAssertTrue(waitUntil { timer.progress > 0.2 })
        timer.stop()
        let paused = timer.progress
        XCTAssertFalse(timer.isRunning)

        timer.resume()

        XCTAssertTrue(timer.isRunning)
        XCTAssertGreaterThanOrEqual(timer.progress, paused - 0.01, "Resuming rewound the story")
    }

    /// Touch-down and touch-up can arrive in a burst; resuming something that's
    /// already running must not start a second ticker.
    func testResumingSomethingAlreadyRunningIsANoOp() {
        // A longer story and a generous timeout: this one waits for a real
        // completion rather than a state flip, so it is the one test here that
        // a loaded machine can starve.
        let timer = makeTimer(duration: 0.5)
        defer { timer.stop() }
        var completions = 0
        timer.onComplete = { completions += 1 }

        timer.start()
        timer.resume()
        timer.resume()

        XCTAssertTrue(waitUntil({ completions > 0 }, timeout: 30), "The story never finished")
        advance(0.3)
        XCTAssertEqual(completions, 1, "A second ticker would advance the story twice")
    }

    /// Resuming a story that already ran out restarts it rather than sitting
    /// finished — that's what re-opening a watched story does.
    func testResumingAFinishedStoryStartsItOver() {
        let timer = makeTimer()
        defer { timer.stop() }
        timer.progress = 1

        timer.resume()

        XCTAssertTrue(timer.isRunning)
        XCTAssertLessThan(timer.progress, 1)
    }

    /// Paging away has to stop the outgoing story, or two stories advance at once.
    func testStoppingHaltsProgressAndReportsNothing() {
        let timer = makeTimer(duration: 1)
        var completed = false
        timer.onComplete = { completed = true }

        timer.start()
        XCTAssertTrue(waitUntil { timer.progress > 0.1 })
        timer.stop()
        let stopped = timer.progress

        advance(0.3)

        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.progress, stopped, accuracy: 0.001, "The bar kept moving after being stopped")
        XCTAssertFalse(completed)
    }

    func testStoppingSomethingThatNeverStartedIsHarmless() {
        let timer = makeTimer()

        timer.stop()
        timer.stop()

        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.progress, 0)
    }

    /// Paging back to a story restarts its bar from zero.
    func testStartingAgainResetsTheBar() {
        let timer = makeTimer(duration: 1)
        defer { timer.stop() }

        timer.start()
        XCTAssertTrue(waitUntil { timer.progress > 0.2 })

        timer.start()

        XCTAssertLessThan(timer.progress, 0.2)
    }

    /// The view marks a story viewed off `onQuarter`, so a restart has to arm
    /// it again for the next story.
    func testRestartingArmsTheViewReportAgain() {
        let timer = makeTimer()
        defer { timer.stop() }
        var quarterCount = 0
        timer.onQuarter = { quarterCount += 1 }

        timer.start()
        XCTAssertTrue(waitUntil { quarterCount == 1 })

        timer.start()

        XCTAssertTrue(waitUntil { quarterCount == 2 }, "The next story would never be marked viewed")
    }

    // MARK: - Progress bars

    /// One bar per story, filled up to the one playing.
    func testRendersTheProgressBars() {
        let timer = makeTimer()
        defer { timer.stop() }
        let stories = (0 ..< 4).map { index in
            GrainStory(
                uri: "at://did:plc:test/social.grain.story/\(index)",
                cid: "bafy\(index)",
                creator: GrainProfile(cid: "c", did: "did:plc:test", handle: "tester.test"),
                thumb: "https://test.local/t.jpg",
                fullsize: "https://test.local/f.jpg",
                aspectRatio: AspectRatio(width: 3, height: 4),
                createdAt: Fixtures.freshTimestamp
            )
        }

        for index in [0, 2, 3] {
            ViewRender.render(
                StoryProgressBars(timer: timer, stories: stories, currentStoryIndex: index),
                settle: 0
            )
        }
    }

    /// Before the stories land the bars are drawn from the author's count, so
    /// the header doesn't pop in a beat later than everything else.
    func testRendersPlaceholderBarsBeforeTheStoriesArrive() {
        let timer = makeTimer()
        defer { timer.stop() }

        ViewRender.render(
            StoryProgressBars(timer: timer, stories: [], currentStoryIndex: 0, placeholderCount: 3),
            settle: 0
        )
    }

    /// Nothing known at all — no stories and no count — still has to lay out.
    func testRendersNoBarsWithNothingToShow() {
        let timer = makeTimer()
        defer { timer.stop() }

        ViewRender.render(
            StoryProgressBars(timer: timer, stories: [], currentStoryIndex: 0),
            settle: 0
        )
    }
}

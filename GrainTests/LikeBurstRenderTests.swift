@testable import Grain
import SwiftUI
import XCTest

/// The animation a double-tap plays over a photo — a heart, three ripples and a
/// scatter of particles, each on its own curve and delay.
@MainActor
final class LikeBurstRenderTests: XCTestCase {
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

    /// The burst that plays when a card is double-tapped: a heart plus three
    /// ripples, each on its own curve and delay.
    func testRendersTheDoubleTapHeartThroughItsBurst() {
        let state = HeartAnimationState(position: CGPoint(x: 120, y: 200))
        ViewRender.render(DoubleTapHeartView(state: state), settle: 0)

        state.start()
        ViewRender.render(DoubleTapHeartView(state: state), settle: 0.2)

        // The burst runs on transforms and opacity, which don't move any
        // frames — so wait on the state rather than on the rendered tree.
        let deadline = Date().addingTimeInterval(5)
        while !state.isComplete, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(state.isComplete, "The heart never finished, so it would stay on the card")

        // Finished, and the view stops drawing rather than lingering.
        ViewRender.render(DoubleTapHeartView(state: state), settle: 0)
    }

    func testTheHeartIsGivenARandomTilt() {
        let tilts = (0 ..< 12).map { _ in HeartAnimationState(position: .zero).rotation }

        XCTAssertTrue(tilts.allSatisfy { $0 >= -20 && $0 <= 20 })
        XCTAssertGreaterThan(Set(tilts).count, 1, "Every heart landing at the same angle would read as a glitch")
    }

    /// Each particle in the burst sits at its own offset, so the slots have to
    /// be distinct — and the view indexes a fixed table, so every slot the card
    /// can ask for has to exist.
    func testRendersEveryLikeParticleSlot() {
        for index in 0 ..< 5 {
            ViewRender.render(LikeParticleView(index: index), settle: 0)
        }
    }
}

import AVFoundation
import Foundation
@testable import Grain
import Testing

/// The story camera's state machine, as far as it can be driven without a
/// camera. The simulator has none, so the ready state is device-only; what
/// these pin is that every path short of it ends in a state the capture stage
/// knows how to draw, and that nothing tries to shoot from those states.
@MainActor
struct StoryCameraTests {
    @Test func deniedAccessLeavesTheCameraUnauthorized() async {
        let camera = StoryCamera(requestAccess: { false })

        await camera.start()

        #expect(camera.status == .unauthorized)
        #expect(await camera.capture() == nil, "there is nothing to shoot with")
    }

    /// Granted access with no camera behind it — the simulator — must land on
    /// the unavailable placeholder rather than hang in `starting`.
    @Test func grantedAccessWithoutACameraIsUnavailable() async {
        let camera = StoryCamera(requestAccess: { true })

        await camera.start()

        #expect(camera.status == .unavailable)
        #expect(await camera.capture() == nil)
    }

    @Test func theCameraStartsOutStartingOnTheBackLensWithFlashOff() {
        let camera = StoryCamera(requestAccess: { true })

        #expect(camera.status == .starting)
        #expect(camera.position == .back)
        #expect(camera.flashMode == .off)
        #expect(!camera.hasFlash, "flash is only offered once a lens reports having one")
        #expect(!camera.isCapturing)
    }

    @Test func flashTogglesBetweenOffAndOn() {
        let camera = StoryCamera(requestAccess: { true })

        camera.toggleFlash()
        #expect(camera.flashMode == .on)
        camera.toggleFlash()
        #expect(camera.flashMode == .off)
    }

    /// A flip that can't find the other lens keeps the current one, so the
    /// controls don't claim a lens that isn't feeding the preview.
    @Test func flippingWithoutACameraKeepsThePosition() async {
        let camera = StoryCamera(requestAccess: { true })
        await camera.start()

        await camera.flip()

        #expect(camera.position == .back)
    }

    @Test func nothingIsAskedOfTheSessionUntilStart() async {
        let asked = Flag()
        let camera = StoryCamera(requestAccess: {
            asked.raise()
            return false
        })

        #expect(!asked.isRaised, "the permission prompt waits for the composer to appear")
        await camera.start()
        #expect(asked.isRaised)
    }
}

/// A flag a `@Sendable` closure can raise.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    var isRaised: Bool {
        lock.withLock { raised }
    }

    func raise() {
        lock.withLock { raised = true }
    }
}

import os

@MainActor
enum LaunchMetrics {
    static let signposter = OSSignposter(subsystem: "social.grain.grain", category: "AppLaunch")

    private static var tfpState: OSSignpostIntervalState?
    private static var preBodyState: OSSignpostIntervalState?
    private static var preBodyEnded = false
    private static var tfpEnded = false

    static func beginTFP() {
        tfpState = signposter.beginInterval("TFP", id: signposter.makeSignpostID())
    }

    static func endTFPOnce() {
        guard !tfpEnded, let state = tfpState else { return }
        tfpEnded = true
        signposter.endInterval("TFP", state)
        tfpState = nil
    }

    static func beginPreBody() {
        preBodyState = signposter.beginInterval("PreBody", id: signposter.makeSignpostID())
    }

    static func endPreBodyOnce() {
        guard !preBodyEnded, let state = preBodyState else { return }
        preBodyEnded = true
        signposter.endInterval("PreBody", state)
        preBodyState = nil
    }
}

import Foundation

/// True when code is running inside an Xcode preview canvas.
/// Use to skip network calls that would block or slow down previews.
var isPreview: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

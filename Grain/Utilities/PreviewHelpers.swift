import Foundation
import SwiftUI

/// True when code is running inside an Xcode preview canvas.
/// Use to skip network calls that would block or slow down previews.
var isPreview: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

// MARK: - Preview Modifiers

extension XRPCClient {
    /// Shared preview client — avoids repeating `XRPCClient(baseURL: AuthManager.serverURL)`.
    static var preview: XRPCClient {
        XRPCClient(baseURL: AuthManager.serverURL)
    }
}

extension View {
    /// Applies the standard Grain preview styling: dark mode + accent color.
    /// Use on every #Preview so the canvas matches the real app.
    func grainPreview() -> some View {
        preferredColorScheme(.dark)
            .tint(Color.accentColor)
    }

    /// Injects the standard Grain environment objects required by most previews.
    func previewEnvironments() -> some View {
        environment(AuthManager())
            .environment(StoryStatusCache())
            .environment(ViewedStoryStorage())
            .environment(LabelDefinitionsCache())
    }
}

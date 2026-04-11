import os
import SwiftUI
import UIKit

private let spLogger = Logger(subsystem: "social.grain.grain", category: "StoryCommentPresenter")
private let spSignposter = OSSignposter(subsystem: "social.grain.grain", category: "StoryCommentPresenter")

// MARK: - Sheet target

/// Payload for the comment sheet. `id` changes per `open()` call so SwiftUI's
/// `.sheet(item:)` treats each presentation as a new item.
struct CommentSheetTarget: Identifiable, Equatable {
    let id = UUID()
    let storyUri: String
    let focusInput: Bool
    let viewModel: StoryCommentsViewModel
    let client: XRPCClient
    var onProfileTap: ((String) -> Void)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - State holder (backing store for the dedicated window's root view)

@Observable
@MainActor
private final class CommentSheetWindowState {
    var target: CommentSheetTarget?
    @ObservationIgnored var onDismissed: (() -> Void)?
    /// Tracks which code path first cleared `target` so the dismiss log can
    /// distinguish swipe-down (default) from dim-tap, Done-button, and
    /// `close()`. Cleared inside `.sheet` `onDismiss`.
    @ObservationIgnored var pendingDismissSource: String?
}

// MARK: - Root view of the dedicated window

/// Lives inside the comment window's `UIHostingController`. It's a transparent
/// container with a SwiftUI `.sheet(item:)` modifier — all presentation,
/// animation, swipe-dismiss, and keyboard handling is native SwiftUI. The
/// manual dim is necessary because iOS's sheet dims its own window's
/// background, and ours is transparent.
private struct CommentSheetHostView: View {
    let auth: AuthManager
    let storyStatusCache: StoryStatusCache
    let viewedStories: ViewedStoryStorage
    @Bindable var state: CommentSheetWindowState

    var body: some View {
        ZStack {
            if state.target != nil {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        spSignposter.emitEvent("dim.tap")
                        state.pendingDismissSource = "dim.tap"
                        state.target = nil
                    }
                    .transition(.opacity)
            }
        }
        // Match the sheet's native dismissal duration so the dim fade finishes
        // at the same moment the sheet finishes sliding off screen. If it ends
        // earlier we get a stale transparent frame; if later, the window hide
        // in `onDismiss` truncates it and the user sees a pop.
        .animation(.easeInOut(duration: 0.35), value: state.target != nil)
        .sheet(item: $state.target, onDismiss: {
            let source = state.pendingDismissSource ?? "swipe"
            state.pendingDismissSource = nil
            spLogger.info("[sheet.onDismiss] source=\(source)")
            spSignposter.emitEvent("sheet.onDismiss", "source=\(source)")
            let cb = state.onDismissed
            state.onDismissed = nil
            cb?()
        }) { target in
            StoryCommentSheet(
                viewModel: target.viewModel,
                storyUri: target.storyUri,
                client: target.client,
                focusInput: target.focusInput,
                onProfileTap: target.onProfileTap,
                onDismiss: {
                    state.pendingDismissSource = "content.onDismiss"
                    state.target = nil
                }
            )
            .environment(auth)
            .environment(storyStatusCache)
            .environment(viewedStories)
            // Disables iOS's own dim + the default "tap dim to expand detent"
            // behavior. We draw our own dim above (tappable to dismiss), and
            // this also lets background taps reach it.
            .presentationBackgroundInteraction(.enabled)
        }
    }
}

// MARK: - Presenter

/// Presents the story comment sheet via SwiftUI's native `.sheet` modifier,
/// hosted inside a dedicated `UIWindow` at `.alert - 1`. UIKit's role is
/// limited to providing the isolated window — everything the user sees and
/// interacts with is standard SwiftUI. The window keeps the main window's VC
/// hierarchy (StoryViewer's fullScreenCover host) untouched by the sheet
/// presentation's lifecycle, which was causing SwiftUI to rebuild StoryViewer
/// with fresh `@State` on every open/close.
///
/// Presentation state is intentionally not observation-tracked: callers drive
/// their own local `@State` mirror via the `onDidClose` callback passed to
/// `open()`. Reading presentation state from a view body would re-run the
/// body on every open/close.
@Observable
@MainActor
final class StoryCommentPresenter {
    @ObservationIgnored var presentedStoryUri: String?

    @ObservationIgnored private weak var authManager: AuthManager?
    @ObservationIgnored private weak var storyStatusCache: StoryStatusCache?
    @ObservationIgnored private weak var viewedStories: ViewedStoryStorage?

    @ObservationIgnored private var commentWindow: UIWindow?
    @ObservationIgnored private let state = CommentSheetWindowState()
    @ObservationIgnored private var openSignpostState: OSSignpostIntervalState?

    func configure(
        auth: AuthManager,
        storyStatusCache: StoryStatusCache,
        viewedStories: ViewedStoryStorage
    ) {
        authManager = auth
        self.storyStatusCache = storyStatusCache
        self.viewedStories = viewedStories
    }

    func open(
        storyUri: String,
        focusInput: Bool,
        commentsViewModel: StoryCommentsViewModel,
        client: XRPCClient,
        onProfileTap: ((String) -> Void)? = nil,
        onDidClose: (() -> Void)? = nil
    ) {
        guard state.target == nil else {
            spLogger.info("[open] SKIPPED — target already set")
            spSignposter.emitEvent("open.skipped", "reason=target-set")
            return
        }
        guard state.onDismissed == nil else {
            spLogger.info("[open] SKIPPED — dismiss in progress")
            spSignposter.emitEvent("open.skipped", "reason=dismiss-in-progress")
            return
        }
        guard let auth = authManager,
              let statusCache = storyStatusCache,
              let viewed = viewedStories
        else {
            spLogger.info("[open] SKIPPED — env missing")
            spSignposter.emitEvent("open.skipped", "reason=env-missing")
            return
        }
        guard let scene = Self.foregroundActiveScene() else {
            spLogger.info("[open] ABORT — no foreground-active UIWindowScene")
            spSignposter.emitEvent("open.aborted", "reason=no-scene")
            return
        }

        let intervalState = spSignposter.beginInterval("open", "focusInput=\(focusInput)")
        openSignpostState = intervalState
        spLogger.info("[open] storyUri=\(storyUri) focusInput=\(focusInput)")

        // Lazy window creation — built once per app session and reused. The
        // root view's state/bindings persist across open/close cycles.
        ensureWindow(
            auth: auth,
            statusCache: statusCache,
            viewed: viewed,
            scene: scene
        )

        commentWindow?.isHidden = false
        commentWindow?.makeKeyAndVisible()
        spSignposter.emitEvent("open.window-visible")

        presentedStoryUri = storyUri

        // Wire the dismissal callback BEFORE setting the target so SwiftUI's
        // onDismiss closure sees the correct handler.
        state.onDismissed = { [weak self] in
            guard let self else { return }
            spLogger.info("[onDismissed] begin")
            spSignposter.emitEvent("onDismissed.begin")

            presentedStoryUri = nil

            // Hiding the comment window (or calling endEditing on it) crashes
            // when done synchronously inside SwiftUI's .sheet onDismiss:
            // resigning the @FocusState-bound TextField mid-sheet-teardown
            // re-enters SwiftUI while the sheet view tree is still unwinding.
            // Defer both to the next main-runloop tick so the current dismiss
            // callback returns first. Do NOT inline these — the crash is
            // easy to re-introduce.
            let windowToHide = commentWindow
            DispatchQueue.main.async {
                windowToHide?.endEditing(true)
                windowToHide?.isHidden = true
                spSignposter.emitEvent("onDismissed.window-hidden")
            }

            if let intervalState = openSignpostState {
                spSignposter.endInterval("open", intervalState)
                openSignpostState = nil
            }
            onDidClose?()
            spSignposter.emitEvent("onDismissed.end")
        }

        state.target = CommentSheetTarget(
            storyUri: storyUri,
            focusInput: focusInput,
            viewModel: commentsViewModel,
            client: client,
            onProfileTap: onProfileTap
        )
        spLogger.info("[open] end — state.target set")
        spSignposter.emitEvent("open.target-set")
    }

    func close() {
        spLogger.info("[close] programmatic close")
        spSignposter.emitEvent("close.programmatic")
        state.pendingDismissSource = "close.programmatic"
        state.target = nil
    }

    private func ensureWindow(
        auth: AuthManager,
        statusCache: StoryStatusCache,
        viewed: ViewedStoryStorage,
        scene: UIWindowScene
    ) {
        guard commentWindow == nil else { return }

        let root = CommentSheetHostView(
            auth: auth,
            storyStatusCache: statusCache,
            viewedStories: viewed,
            state: state
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear

        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level.alert - 1
        window.rootViewController = host
        window.backgroundColor = .clear
        window.isHidden = true

        commentWindow = window
        spLogger.info("[ensureWindow] created at level \(window.windowLevel.rawValue)")
        spSignposter.emitEvent("ensureWindow.created")
    }

    private static func foregroundActiveScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}

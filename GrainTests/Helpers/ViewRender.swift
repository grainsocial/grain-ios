@testable import Grain
import SwiftUI
import XCTest

/// SwiftUI only evaluates a view's `body` when something actually lays the view
/// out, so exercising a view file means hosting and rendering it rather than
/// calling into it. `FacepileLayoutTests` uses `UIHostingController` the same
/// way to measure layout; this is the reusable form of that trick.
@MainActor
enum ViewRender {
    /// An iPhone-sized canvas, so views that branch on size class take the
    /// phone path rather than the iPad one.
    static let canvas = CGSize(width: 402, height: 874)

    /// Host `view` in a real window and lay it out. Attaching to a window (not
    /// just calling `sizeThatFits`) is what makes `onAppear` and `task` fire,
    /// which is where most of a view's state handling lives.
    ///
    /// `settle` is a *ceiling* on how long the run loop is pumped afterwards so
    /// async `task` work can land and re-render the loaded state — not a fixed
    /// wait. The pump stops as soon as the view tree has held still for
    /// `quietPeriod`, which for most views is far sooner. Content arriving late
    /// restarts that window, so a slow load still gets the full ceiling.
    static func render(_ view: some View, settle: TimeInterval = 0.05) {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: canvas))
        window.rootViewController = host
        window.isHidden = false

        host.view.frame = CGRect(origin: .zero, size: canvas)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        _ = host.sizeThatFits(in: canvas)

        if settle > 0 {
            pumpUntilQuiet(host, ceiling: settle)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        window.isHidden = true
        window.rootViewController = nil
    }

    /// One slice of run loop per pump. Small enough that a view which settles
    /// immediately costs almost nothing.
    private static let slice: TimeInterval = 0.02

    /// How long the tree has to hold still before it counts as settled. Long
    /// enough to cover the gap between a mocked response landing and SwiftUI
    /// re-rendering off the back of it.
    private static let quietPeriod: TimeInterval = 0.06

    private static func pumpUntilQuiet(_ host: UIHostingController<some View>, ceiling: TimeInterval) {
        let deadline = Date().addingTimeInterval(ceiling)
        var lastChange = Date()
        var previous = fingerprint(host.view)

        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(slice))
            host.view.layoutIfNeeded()

            let current = fingerprint(host.view)
            if current != previous {
                previous = current
                lastChange = Date()
                continue
            }
            // Views with a looping animation — a shimmer, a spinner — never go
            // quiet, and simply run out the ceiling as they did before.
            if Date().timeIntervalSince(lastChange) >= quietPeriod {
                return
            }
        }
    }

    /// A cheap structural signature of the rendered tree. Content arriving
    /// changes the subview count and the frames, which is what marks the view
    /// as still busy.
    private static func fingerprint(_ view: UIView) -> Int {
        var hasher = Hasher()
        var stack = [view]
        var count = 0
        while let next = stack.popLast() {
            count += 1
            hasher.combine(next.frame.origin.x)
            hasher.combine(next.frame.origin.y)
            hasher.combine(next.frame.size.width)
            hasher.combine(next.frame.size.height)
            hasher.combine(next.isHidden)
            stack.append(contentsOf: next.subviews)
        }
        hasher.combine(count)
        return hasher.finalize()
    }
}

/// The environment objects `GrainApp` installs above the tab tree. Views pull
/// these out with `@Environment`, so rendering one in isolation means supplying
/// the same set or the view traps on a missing value.
@MainActor
struct TestEnvironment {
    let auth = AuthManager()
    let viewedStories = ViewedStoryStorage(did: "did:plc:test")
    let labelDefs = LabelDefinitionsCache()
    let storyStatus = StoryStatusCache()
    let uploadCenter = GalleryUploadCenter()
    let pushManager = PushManager()
    let commentPresenter = StoryCommentPresenter()

    /// A client whose traffic is served by `MockURLProtocol`, so rendering a
    /// view never reaches the network.
    let client = XRPCClient(
        baseURL: URL(string: "https://test.local")!,
        session: MockURLProtocol.mockSession()
    )

    init(authenticated: Bool = true, did: String = "did:plc:test") {
        auth.isAuthenticated = authenticated
        auth.userDID = did
    }
}

extension View {
    /// Attach the full environment set `GrainApp` provides.
    @MainActor
    func withTestEnvironment(_ env: TestEnvironment) -> some View {
        environment(env.auth)
            .environment(env.viewedStories)
            .environment(env.labelDefs)
            .environment(env.storyStatus)
            .environment(env.uploadCenter)
            .environment(env.pushManager)
            .environment(env.commentPresenter)
    }
}

/// `TokenStorage` is Keychain-backed and the test host shares that Keychain
/// with the installed simulator app, so any test that writes it has to put the
/// old value back or it corrupts the signed-in account. Mirrors the save and
/// restore that `ProfileDetailViewModelTests` does by hand.
@MainActor
final class KeychainGuard {
    private let savedUserDID: String?

    init(userDID: String?) {
        savedUserDID = TokenStorage.userDID
        TokenStorage.userDID = userDID
    }

    func restore() {
        TokenStorage.userDID = savedUserDID
    }
}

/// A synthetic signed-in account, so `AuthManager.authContext()` resolves.
///
/// Screens gate whole sections on having a context — the moderation lists, the
/// settings preferences, every favorite and follow button — so an environment
/// without one renders only their signed-out half, which is a large share of
/// the view code going unexercised.
///
/// The test host shares its Keychain with the app installed on the simulator,
/// so this saves the real active account and `restore()` puts it back.
@MainActor
final class TestAccount {
    let did: String
    let handle: String
    private let savedActiveDID: String?
    private let savedActiveAccountID: String?

    /// `AuthManager` runs a one-shot scope migration on first launch that can
    /// sign every account out. Storing a full scope keeps it from firing, but
    /// it still writes its "done" flag — so put that back too.
    private static let scopeMigrationKey = "scopeMigrationDone_v2"
    private let savedScopeMigration: Bool

    init(did: String = "did:plc:test", handle: String = "tester.grain.social") {
        self.did = did
        self.handle = handle
        savedActiveDID = TokenStorage.activeDID
        savedActiveAccountID = AccountScopedStorage.activeAccountID
        savedScopeMigration = UserDefaults.standard.bool(forKey: Self.scopeMigrationKey)

        _ = try? DPoP.loadOrCreate(for: did)
        TokenStorage.storeTokens(
            did: did,
            accessToken: "test-access",
            refreshToken: "test-refresh",
            handle: handle,
            // Comfortably in the future: `authContext()` refreshes anything
            // expiring within a minute, and a refresh has nowhere to go here.
            expiresAt: Date().addingTimeInterval(3600),
            scope: AuthManager.requiredScopes.joined(separator: " ")
        )
        TokenStorage.upsertAccount(StoredAccount(did: did, handle: handle, avatar: nil))

        // Making it the active account is what matters: `AuthManager.init`
        // restores from here and installs the DPoP key, so every environment
        // built afterwards has a working `authContext()`.
        TokenStorage.activeDID = did
        AccountScopedStorage.activeAccountID = did
    }

    /// Explicitly hand the account to an `AuthManager` that was built before
    /// this account existed.
    func activate(_ auth: AuthManager) async {
        // `TestEnvironment` pre-sets `userDID`; clear it so `switchTo` doesn't
        // early-return as a no-op.
        auth.userDID = nil
        try? await auth.switchTo(did: did)
    }

    func restore() {
        TokenStorage.removeAccount(did)
        try? DPoP.clearKey(for: did)
        AccountScopedStorage.purge(did: did)
        TokenStorage.activeDID = savedActiveDID
        AccountScopedStorage.activeAccountID = savedActiveAccountID
        UserDefaults.standard.set(savedScopeMigration, forKey: Self.scopeMigrationKey)
    }
}

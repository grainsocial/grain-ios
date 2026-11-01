import AuthenticationServices
import CryptoKit
import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "Auth")
private let authSignposter = OSSignposter(subsystem: "social.grain.grain", category: "Auth")

/// Signs accounts in at their own PDS with atproto OAuth, as a public native
/// client, and holds their sessions.
///
/// Several accounts can be signed in at once. Their credentials live side by
/// side in the Keychain, keyed by DID; this class tracks which one is active
/// and swaps the app over to another on request.
@Observable
@MainActor
final class AuthManager {
    var isAuthenticated = false
    var userDID: String?
    var userHandle: String?
    var userAvatar: String?
    var avatarImage: UIImage?
    /// Every account signed in on this device, active one included.
    var accounts: [StoredAccount] = []
    /// Set when a launch-time session migration forced the user to sign out.
    /// LoginView reads this to display an explanation above the sign-in form.
    var reauthReason: String?

    private(set) var dpop: DPoP?
    private var refreshTask: Task<Void, Error>?
    /// The OAuth flow currently on screen, if any. At most one at a time.
    private var loginTask: Task<Void, Error>?

    #if PRODUCTION_API || !targetEnvironment(simulator)
        nonisolated static let serverURL = URL(string: "https://grain.social")!
        /// Where the sign-up button makes an account.
        nonisolated static let signUpPDS = URL(string: "https://selfhosted.social")!
    #else
        nonisolated static let serverURL = URL(string: "http://127.0.0.1:3000")!
        nonisolated static let signUpPDS = URL(string: "http://localhost:2583")!
    #endif

    /// The client metadata document grain-serve publishes for the apps. A PDS
    /// fetches it, so it must be https: a dev build signing in against a
    /// local server needs that server behind an https tunnel.
    nonisolated static let clientID = serverURL.appendingPathComponent("oauth/app-client-metadata.json").absoluteString
    /// The app's bundle id reversed into a URL scheme, with one slash, as
    /// atproto OAuth asks of a native client.
    nonisolated static let redirectURI = "social.grain:/oauth/callback"
    nonisolated static let callbackScheme = "social.grain"

    /// The server's `did:web`, port and all (`:` as `%3A`).
    nonisolated static let appviewDID: String = {
        var host = serverURL.host ?? "grain.social"
        if let port = serverURL.port {
            host += "%3A\(port)"
        }
        return "did:web:\(host)"
    }()

    /// The AppView service a PDS proxies Grain's calls to.
    nonisolated static let appviewService = "\(appviewDID)#grain_appview"

    /// OAuth scopes the app requests at sign-in. Update here, then bump
    /// `sessionMigrationKey` if existing installs should be forced through a
    /// fresh sign-in to pick the new scope up.
    nonisolated static let requiredScopes: [String] = [
        "atproto",
        "blob:image/*",
        "repo:social.grain.gallery",
        "repo:social.grain.gallery.item",
        "repo:social.grain.photo",
        "repo:social.grain.photo.exif",
        "repo:social.grain.actor.profile",
        "repo:social.grain.graph.follow",
        "repo:social.grain.favorite",
        "repo:social.grain.comment",
        "repo:social.grain.story",
        "repo:social.grain.graph.block",
        // Both actions: the cross-post uses putRecord so a resumed publish
        // overwrites its own post rather than posting twice, and the PDS
        // asserts create *and* update for that call.
        "repo:app.bsky.feed.post?action=create&action=update",
        // Every Grain method, through the PDS's proxy to the AppView.
        "rpc:*?aud=\(appviewDID)%23grain_appview",
    ]

    nonisolated static var scope: String {
        requiredScopes.joined(separator: " ")
    }

    /// Version-tagged UserDefaults key marking that the one-shot session
    /// migration has already run for this install. Prevents re-auth loops
    /// when a re-login still yields a token without the newly added scopes.
    /// To force another migration, bump the suffix.
    private static let sessionMigrationKey = "scopeMigrationDone_v3"

    nonisolated static let reauthMessage = "Grain has been updated. Please sign in again to enable new features."

    /// The session every OAuth call goes through. Injectable so tests can serve
    /// discovery and the PAR/token/refresh endpoints.
    private let session: URLSession

    /// Shows the authorization page and returns the URL the browser came back
    /// with. Injectable so tests can stand in for the user.
    var presentAuthorization: @MainActor (URL) async throws -> URL = AuthManager.webAuthentication

    var oauth: OAuthClient {
        OAuthClient(session: session, clientID: Self.clientID, redirectURI: Self.redirectURI)
    }

    init(session: URLSession = NetworkEnvironment.session) {
        self.session = session
        let spid = authSignposter.makeSignpostID()
        let state = authSignposter.beginInterval("SessionRestore", id: spid)
        logger.debug("[SessionRestore] begin")

        // Installs that predate multi-account keep one unsuffixed credential
        // set; fold it into the account list before reading anything back.
        if let migrated = TokenStorage.migrateLegacyAccountIfNeeded() {
            DPoP.migrateLegacyKey(to: migrated)
            AccountScopedStorage.migrateLegacyState(to: migrated)
        }
        runSessionMigrationIfNeeded()
        accounts = TokenStorage.accounts
        AccountScopedStorage.activeAccountID = TokenStorage.activeDID

        // Restore session from Keychain; allow expired tokens since we can refresh
        if let did = TokenStorage.activeDID, TokenStorage.hasSession(for: did) {
            isAuthenticated = true
            userDID = did
            userHandle = TokenStorage.handle(for: did)
            userAvatar = TokenStorage.avatar(for: did)
            authSignposter.emitEvent("KeychainRead", id: spid, "authenticated=true")
            logger.debug("[KeychainRead] authenticated=true")
            let dpopSpid = authSignposter.makeSignpostID()
            let dpopState = authSignposter.beginInterval("DPoPLoad", id: dpopSpid)
            logger.debug("[DPoPLoad] begin")
            dpop = try? DPoP.loadOrCreate(for: did)
            authSignposter.endInterval("DPoPLoad", dpopState)
            logger.debug("[DPoPLoad] end")
        } else {
            authSignposter.emitEvent("KeychainRead", id: spid, "authenticated=false")
            logger.debug("[KeychainRead] authenticated=false")
        }
        authSignposter.endInterval("SessionRestore", state)
        logger.debug("[SessionRestore] end")
    }

    /// One-shot check at launch: drop every account that can't make a
    /// signed-in call as this build makes them (no PDS and authorization
    /// server on record) or whose grant lacks a required scope, so it signs
    /// in again. The UserDefaults flag guarantees this fires at most once per
    /// install per version: even if a re-login somehow still returns an
    /// insufficient grant, it doesn't loop.
    private func runSessionMigrationIfNeeded() {
        guard !StorageEnvironment.defaults.bool(forKey: Self.sessionMigrationKey) else { return }
        StorageEnvironment.defaults.set(true, forKey: Self.sessionMigrationKey)

        let required = Set(Self.requiredScopes)
        let stale = TokenStorage.accounts.filter { account in
            let granted = TokenStorage.grantedScope(for: account.did).map { Set($0.split(separator: " ").map(String.init)) } ?? []
            return TokenStorage.hasCredentials(for: account.did)
                && (TokenStorage.server(for: account.did) == nil || !required.isSubset(of: granted))
        }
        guard !stale.isEmpty else { return }

        logger.info("[SessionMigration] signing out \(stale.count) account(s)")
        let active = TokenStorage.activeDID
        for account in stale {
            forget(did: account.did)
        }
        if let active, stale.contains(where: { $0.did == active }) {
            let next = TokenStorage.accounts.first { TokenStorage.hasSession(for: $0.did) }
            setActiveDID(next?.did)
            if next == nil {
                reauthReason = Self.reauthMessage
            }
        }
    }

    /// Start the OAuth login flow, making the resulting account active. Set
    /// `createAccount` to show the sign-up page.
    ///
    /// Safe to call while another account is signed in: the new grant is kept
    /// in memory until the token exchange succeeds, so cancelling or failing
    /// leaves the current account exactly as it was.
    ///
    /// Concurrent calls join the flow already running rather than starting a
    /// rival one. Every sign-in screen has more than one way to submit (a
    /// button, the keyboard's Go key, tapping a suggestion) and discovery and
    /// PAR happen before the web sheet appears, so a second trigger during
    /// that gap would otherwise stack a second sheet onto the PDS.
    func login(handle: String = "", createAccount: Bool = false) async throws {
        if let existing = loginTask {
            return try await existing.value
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.loginTask = nil }
            try await performLogin(handle: handle, createAccount: createAccount)
        }
        loginTask = task
        try await task.value
    }

    private func performLogin(handle: String, createAccount: Bool) async throws {
        let oauth = oauth
        let pending: PendingAuthorization
        if createAccount {
            pending = try await oauth.signUp(at: Self.signUpPDS, scope: Self.scope)
        } else {
            let identity = try await oauth.resolver.resolve(handle)
            let hint = identity.handle ?? IdentityResolver.normalize(handle)
            pending = try await oauth.authorize(identity, hint: hint, scope: Self.scope)
        }

        let callback = try await presentAuthorization(pending.url)
        let signedIn = try await oauth.redeem(pending, callback: callback)
        store(signedIn)
        await fetchAndStoreAvatar()
    }

    /// The system's web authentication sheet, coming back on the app's
    /// OAuth scheme.
    static func webAuthentication(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(callbackScheme)
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error); return
                }
                guard let url else { continuation.resume(throwing: XRPCError.invalidURL); return }
                continuation.resume(returning: url)
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = WebAuthContextProvider.shared
            session.start()
        }
    }

    /// Refresh the access token only if it expires within 60 seconds.
    func refreshIfNeeded() async throws {
        guard let did = userDID,
              let expiresAt = TokenStorage.tokenExpiresAt(for: did),
              expiresAt.timeIntervalSinceNow < 60 else { return }
        try await refresh()
    }

    /// Refresh the active account's access token. Coalesces concurrent calls.
    func refresh() async throws {
        if let existing = refreshTask {
            return try await existing.value
        }
        guard let did = userDID else { throw XRPCError.unauthorized }
        let task = Task { @MainActor [weak self] in
            guard let self else { throw XRPCError.unauthorized }
            defer { self.refreshTask = nil }
            try await performRefresh(did: did)
        }
        refreshTask = task
        try await task.value
    }

    /// `did` is captured when the refresh starts: the user may switch accounts
    /// while it's in flight, and the result belongs to the account that asked
    /// for it, not to whoever is active when it lands.
    private func performRefresh(did: String) async throws {
        guard let dpop = try? DPoP.loadOrCreate(for: did),
              let refreshToken = TokenStorage.refreshToken(for: did),
              let server = TokenStorage.server(for: did)
        else {
            throw XRPCError.unauthorized
        }

        let tokens: OAuthTokens
        do {
            tokens = try await oauth.refresh(refreshToken: refreshToken, tokenEndpoint: server.tokenEndpoint, dpop: dpop)
        } catch let OAuthError.refused(status, error, _) {
            logger.error("Token refresh failed (\(status)): \(error ?? "no error", privacy: .public)")
            if (400 ... 499).contains(status) {
                // The grant is gone: drop this account. If it's the one on
                // screen, fall through to whichever account is left.
                forget(did: did)
                if userDID == did {
                    activateNextAccountOrSignOut()
                }
            }
            throw XRPCError.unauthorized
        } catch {
            logger.error("Token refresh failed: \(error)")
            throw XRPCError.unauthorized
        }

        TokenStorage.storeTokens(
            did: did,
            accessToken: tokens.accessToken,
            // A server that doesn't rotate keeps the one it was given.
            refreshToken: tokens.refreshToken ?? refreshToken,
            handle: nil,
            expiresAt: tokens.expiresAt,
            scope: tokens.scope
        )
    }

    /// Build an AuthContext for making authenticated requests.
    /// Proactively refreshes if the token expires within 60 seconds.
    func authContext() async -> AuthContext? {
        guard dpop != nil, let did = userDID else { return nil }
        if let expiresAt = TokenStorage.tokenExpiresAt(for: did), expiresAt.timeIntervalSinceNow < 60 {
            try? await refresh()
        }
        // Re-read after the await: the active account may have changed.
        guard let currentDpop = dpop,
              let currentDID = userDID,
              let token = TokenStorage.accessToken(for: currentDID),
              let server = TokenStorage.server(for: currentDID) else { return nil }
        return AuthContext(accessToken: token, dpop: currentDpop, did: currentDID, pds: server.pds)
    }

    /// Create an XRPCClient with automatic token refresh on 401.
    func makeClient() -> XRPCClient {
        XRPCClient(baseURL: Self.serverURL) { [weak self] in
            try await self?.refresh()
            return await self?.authContext()
        }
    }

    // MARK: - Account switching

    /// Called with the outgoing account's auth context, while it's still valid,
    /// before that account stops being active. Push registration unwinds here.
    var onAccountWillDeactivate: ((AuthContext?) async -> Void)?
    /// Called with the new active DID once it has taken over, or nil when the
    /// last account signed out. Per-account caches re-point themselves here.
    var onAccountDidActivate: ((String?) -> Void)?

    // MARK: - Private

    /// Persist a fresh sign-in and make it the active account.
    private func store(_ signedIn: OAuthSession) {
        let did = signedIn.identity.did
        try? signedIn.dpop.persist(for: did)
        TokenStorage.storeTokens(
            did: did,
            accessToken: signedIn.tokens.accessToken,
            refreshToken: signedIn.tokens.refreshToken,
            handle: signedIn.identity.handle,
            expiresAt: signedIn.tokens.expiresAt,
            scope: signedIn.scope
        )
        TokenStorage.storeServer(
            AccountServer(
                pds: signedIn.identity.pds,
                issuer: signedIn.server.issuer,
                tokenEndpoint: signedIn.server.tokenEndpoint,
                revocationEndpoint: signedIn.server.revocationEndpoint
            ),
            for: did
        )
        TokenStorage.upsertAccount(StoredAccount(did: did, handle: signedIn.identity.handle, avatar: nil))
        accounts = TokenStorage.accounts

        setActiveDID(did)
        refreshTask = nil
        dpop = signedIn.dpop

        // Guard each @Observable assignment: the macro's setter always fires the
        // observation registrar even when the value is unchanged.
        if !isAuthenticated {
            isAuthenticated = true
        }
        if userDID != did {
            userDID = did
            userAvatar = TokenStorage.avatar(for: did)
            avatarImage = nil
        }
        let storedHandle = TokenStorage.handle(for: did)
        if userHandle != storedHandle {
            userHandle = storedHandle
        }
        if reauthReason != nil {
            reauthReason = nil
        }
        onAccountDidActivate?(did)
    }

    func fetchAvatarIfNeeded() async {
        if userAvatar != nil, avatarImage == nil {
            await downloadAvatarImage()
        }
        if userAvatar == nil, userDID != nil {
            await fetchAndStoreAvatar()
        }
    }

    func refreshAvatar() async {
        await fetchAndStoreAvatar()
    }

    private func fetchAndStoreAvatar() async {
        guard let did = userDID else { return }
        let client = XRPCClient(baseURL: Self.serverURL)
        do {
            let profile = try await client.getActorProfile(actor: did)
            // Keep the switcher's row for this account current, not just the
            // active-account fields.
            TokenStorage.upsertAccount(StoredAccount(did: did, handle: profile.handle, avatar: profile.avatar))
            accounts = TokenStorage.accounts
            guard did == userDID else { return }
            if userAvatar != profile.avatar {
                userAvatar = profile.avatar
                TokenStorage.setAvatar(profile.avatar, for: did)
            }
        } catch {
            logger.error("Avatar fetch failed: \(error)")
        }
        await downloadAvatarImage()
    }

    private func downloadAvatarImage() async {
        guard let urlString = userAvatar, let url = URL(string: urlString) else { return }
        do {
            let (data, _) = try await session.data(from: url)
            if let image = UIImage(data: data) {
                avatarImage = image
            }
        } catch {
            logger.error("Avatar download failed: \(error)")
        }
    }
}

// MARK: - Account switching

/// Split out of the class body so the switching logic reads as its own unit —
/// and stays out of `AuthManager`'s already-long body.
@MainActor
extension AuthManager {
    enum AccountError: LocalizedError {
        /// The account is in the list but its credentials are gone — the only
        /// way back in is a fresh sign-in.
        case signInRequired(handle: String?)

        var errorDescription: String? {
            switch self {
            case let .signInRequired(handle):
                "Sign in again to use \(handle.map { "@\($0)" } ?? "this account")."
            }
        }
    }

    /// Make an already-signed-in account the active one.
    func switchTo(did: String) async throws {
        guard did != userDID else { return }
        guard TokenStorage.hasSession(for: did), let newDpop = try? DPoP.loadOrCreate(for: did) else {
            throw AccountError.signInRequired(handle: accounts.first { $0.did == did }?.handle)
        }

        await deactivateCurrentAccount()

        // Renew the incoming account's token *before* handing the app over. A
        // dead grant then surfaces as an error on the switcher rather than as a
        // wall of empty views, and everything after this point is synchronous:
        // flipping `userDID` tears down the view tree that's awaiting this call,
        // so an await past here can be cancelled mid-switch.
        if let expiresAt = TokenStorage.tokenExpiresAt(for: did), expiresAt.timeIntervalSinceNow < 60 {
            do {
                try await performRefresh(did: did)
            } catch {
                logger.error("[Switch] refresh failed for \(did, privacy: .public): \(error)")
                // performRefresh drops the account when the grant is terminally
                // gone; anything else (offline, 5xx) is worth switching through,
                // since the 401 path retries.
                if !TokenStorage.hasSession(for: did) {
                    throw AccountError.signInRequired(handle: accounts.first { $0.did == did }?.handle)
                }
            }
        }

        setActiveDID(did)
        refreshTask = nil
        dpop = newDpop
        userDID = did
        userHandle = TokenStorage.handle(for: did)
        userAvatar = TokenStorage.avatar(for: did)
        avatarImage = nil
        accounts = TokenStorage.accounts
        isAuthenticated = true

        onAccountDidActivate?(did)
        Task { await fetchAndStoreAvatar() }
    }

    /// Sign out of one account. Signing out of the active account falls back to
    /// another signed-in account when there is one, so the switcher never
    /// bounces a multi-account user out to the login screen unnecessarily.
    func signOut(did: String) async {
        if did == userDID {
            await deactivateCurrentAccount()
            await revoke(did: did)
            forget(did: did)
            activateNextAccountOrSignOut()
        } else {
            await revoke(did: did)
            forget(did: did)
        }
    }

    /// Ask the account's authorization server to revoke its refresh token.
    /// Best effort: signing out locally never waits on the answer's success.
    private func revoke(did: String) async {
        guard let server = TokenStorage.server(for: did),
              let endpoint = server.revocationEndpoint,
              let refreshToken = TokenStorage.refreshToken(for: did),
              let dpop = try? DPoP.loadOrCreate(for: did)
        else { return }
        do {
            try await oauth.revoke(refreshToken: refreshToken, revocationEndpoint: endpoint, dpop: dpop)
        } catch {
            logger.error("[SignOut] revocation failed: \(error)")
        }
    }

    /// Sign out of the account currently on screen.
    func logout() async {
        guard let did = userDID else { return }
        await signOut(did: did)
    }

    /// Let the outgoing account clean up server-side state (push tokens) while
    /// its credentials still work.
    private func deactivateCurrentAccount() async {
        guard userDID != nil, let hook = onAccountWillDeactivate else { return }
        await hook(authContext())
    }

    /// Erase one account's credentials, keys, and cached content. Purely local
    /// — no observable state changes, no server calls.
    private func forget(did: String) {
        TokenStorage.removeAccount(did)
        try? DPoP.clearKey(for: did)
        AccountScopedStorage.purge(did: did)
        accounts = TokenStorage.accounts
    }

    /// Move to whichever account is left, or drop to the signed-out state.
    private func activateNextAccountOrSignOut() {
        refreshTask = nil
        guard let next = TokenStorage.accounts.first(where: { TokenStorage.hasSession(for: $0.did) }),
              let nextDpop = try? DPoP.loadOrCreate(for: next.did)
        else {
            applySignedOutState()
            return
        }

        setActiveDID(next.did)
        dpop = nextDpop
        userDID = next.did
        userHandle = TokenStorage.handle(for: next.did)
        userAvatar = TokenStorage.avatar(for: next.did)
        avatarImage = nil
        isAuthenticated = true
        onAccountDidActivate?(next.did)
        Task { await fetchAndStoreAvatar() }
    }

    /// The Keychain holds the authoritative active DID; UserDefaults carries a
    /// copy for code that can't afford a Keychain read. Always move both.
    private func setActiveDID(_ did: String?) {
        TokenStorage.activeDID = did
        AccountScopedStorage.activeAccountID = did
    }

    private func applySignedOutState() {
        setActiveDID(nil)
        refreshTask = nil
        isAuthenticated = false
        userDID = nil
        userHandle = nil
        userAvatar = nil
        avatarImage = nil
        dpop = nil
        accounts = TokenStorage.accounts
        onAccountDidActivate?(nil)
    }
}

// MARK: - ASWebAuthenticationSession Context

import UIKit

final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthContextProvider()

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        if let scene {
            return ASPresentationAnchor(windowScene: scene)
        }
        preconditionFailure("No window scene available for ASPresentationAnchor")
    }
}

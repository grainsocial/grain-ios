import AuthenticationServices
import CryptoKit
import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "Auth")
private let authSignposter = OSSignposter(subsystem: "social.grain.grain", category: "Auth")

/// Manages OAuth + DPoP authentication flow against the hatk server.
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
    /// Set when a launch-time scope migration forced the user to sign out.
    /// LoginView reads this to display an explanation above the sign-in form.
    var reauthReason: String?

    private(set) var dpop: DPoP?
    private var codeVerifier: String?
    private var client: XRPCClient?
    private var refreshTask: Task<Void, Error>?
    /// The OAuth flow currently on screen, if any. At most one at a time.
    private var loginTask: Task<Void, Error>?

    #if PRODUCTION_API || !targetEnvironment(simulator)
        nonisolated static let serverURL = URL(string: "https://grain.social")!
    #else
        nonisolated static let serverURL = URL(string: "http://127.0.0.1:3000")!
    #endif
    nonisolated static let clientID = "grain-native://app"
    nonisolated static let redirectURI = "grain://oauth/callback"

    /// OAuth scopes the app currently requests at sign-in. Update here, then
    /// bump a `scopeMigration*` flag below if you want existing installs to
    /// be forced through a fresh sign-in to pick the new scope up.
    nonisolated static let requiredScopes: [String] = [
        "atproto",
        "blob:image/*",
        "repo:social.grain.gallery",
        "repo:social.grain.gallery.item",
        "repo:social.grain.photo",
        "repo:social.grain.photo.exif",
        "repo:social.grain.actor.profile",
        "repo:social.grain.graph.follow",
        "repo:social.grain.graph.block",
        "repo:social.grain.favorite",
        "repo:social.grain.comment",
        "repo:social.grain.story",
        "repo:app.bsky.feed.post?action=create",
    ]

    /// Version-tagged UserDefaults key marking that a one-shot scope
    /// migration has already run for this install. Prevents re-auth loops
    /// when a re-login still yields a token without the newly added scopes.
    /// To force another migration (e.g. after adding a scope), bump the
    /// suffix: `scopeMigrationDone_v2`, `_v3`, etc.
    private static let scopeMigrationKey = "scopeMigrationDone_v1"

    init() {
        let spid = authSignposter.makeSignpostID()
        let state = authSignposter.beginInterval("SessionRestore", id: spid)
        logger.debug("[SessionRestore] begin")

        // Installs that predate multi-account keep one unsuffixed credential
        // set; fold it into the account list before reading anything back.
        if let migrated = TokenStorage.migrateLegacyAccountIfNeeded() {
            DPoP.migrateLegacyKey(to: migrated)
            AccountScopedStorage.migrateLegacyState(to: migrated)
        }
        accounts = TokenStorage.accounts
        AccountScopedStorage.activeAccountID = TokenStorage.activeDID

        // Restore session from Keychain — allow expired tokens since we can refresh
        if let did = TokenStorage.activeDID, TokenStorage.hasCredentials(for: did) {
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

            runScopeMigrationIfNeeded(did: did)
        } else {
            authSignposter.emitEvent("KeychainRead", id: spid, "authenticated=false")
            logger.debug("[KeychainRead] authenticated=false")
        }
        authSignposter.endInterval("SessionRestore", state)
        logger.debug("[SessionRestore] end")
    }

    /// One-shot check at launch: if the currently-stored token predates the
    /// scope-persistence code (or is missing any required scope) and we
    /// haven't already run this migration, log the user out so they re-auth
    /// with a fresh grant. The UserDefaults flag guarantees this fires at
    /// most once per install per version — even if the re-login somehow
    /// still returns an insufficient grant, we don't loop.
    private func runScopeMigrationIfNeeded(did: String) {
        guard !UserDefaults.standard.bool(forKey: Self.scopeMigrationKey) else { return }

        let stored = TokenStorage.grantedScope(for: did).map { Set($0.split(separator: " ").map(String.init)) } ?? []
        let missing = Self.requiredScopes.filter { !stored.contains($0) }
        guard !missing.isEmpty else {
            // Nothing to do — stored token already covers every required scope.
            UserDefaults.standard.set(true, forKey: Self.scopeMigrationKey)
            return
        }

        logger.info("[ScopeMigration] forcing re-auth; missing=\(missing.joined(separator: ","), privacy: .public)")
        UserDefaults.standard.set(true, forKey: Self.scopeMigrationKey)
        // A scope bump applies to every grant, so drop them all rather than
        // leaving stale accounts in the switcher that can't be switched to.
        for account in TokenStorage.accounts {
            forget(did: account.did)
        }
        applySignedOutState()
        reauthReason = "Grain has been updated. Please sign in again to enable new features."
    }

    /// Start the OAuth login flow, making the resulting account active. Set
    /// `createAccount` to show the sign-up page.
    ///
    /// Safe to call while another account is signed in: the new grant is kept
    /// in memory until the token exchange succeeds, so cancelling or failing
    /// leaves the current account exactly as it was.
    ///
    /// Concurrent calls join the flow already running rather than starting a
    /// rival one. Every sign-in screen has more than one way to submit — a
    /// button, the keyboard's Go key, tapping a suggestion — and the PAR round
    /// trip happens before the web sheet appears, so a second trigger during
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
        let dpop = DPoP.createEphemeral()

        let client = XRPCClient(baseURL: Self.serverURL)
        self.client = client

        // Generate PKCE code verifier + challenge
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(verifier: verifier)

        // Step 1: Pushed Authorization Request
        var parBody: [String: String] = [
            "client_id": Self.clientID,
            "redirect_uri": Self.redirectURI,
            "response_type": "code",
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            "scope": Self.requiredScopes.joined(separator: " "),
        ]
        if createAccount {
            parBody["prompt"] = "create"
            #if PRODUCTION_API || !targetEnvironment(simulator)
                parBody["login_hint"] = "selfhosted.social"
            #else
                parBody["login_hint"] = "localhost:2583"
            #endif
        } else if !handle.isEmpty {
            parBody["login_hint"] = handle
        }

        let parURL = Self.serverURL.appendingPathComponent("oauth/par")
        var parRequest = URLRequest(url: parURL)
        parRequest.httpMethod = "POST"
        parRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        parRequest.httpBody = parBody.urlEncoded.data(using: .utf8)

        let parProof = try await dpop.createProof(httpMethod: "POST", url: parURL)
        parRequest.setValue(parProof, forHTTPHeaderField: "DPoP")

        var (parData, parHTTPResponse) = try await URLSession.shared.data(for: parRequest)

        // Handle DPoP nonce requirement on PAR
        if let httpResp = parHTTPResponse as? HTTPURLResponse,
           httpResp.statusCode == 400,
           let nonce = httpResp.value(forHTTPHeaderField: "DPoP-Nonce")
        {
            let retryProof = try await dpop.createProof(httpMethod: "POST", url: parURL, nonce: nonce)
            parRequest.setValue(retryProof, forHTTPHeaderField: "DPoP")
            (parData, parHTTPResponse) = try await URLSession.shared.data(for: parRequest)
        }

        if let httpResp = parHTTPResponse as? HTTPURLResponse,
           !(200 ... 299).contains(httpResp.statusCode)
        {
            throw XRPCError.httpError(statusCode: httpResp.statusCode, body: parData)
        }

        let parResponse = try JSONDecoder().decode(PARResponse.self, from: parData)

        // Step 2: Open browser for authorization
        var authComponents = URLComponents(url: Self.serverURL.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false)!
        authComponents.queryItems = [
            URLQueryItem(name: "request_uri", value: parResponse.requestUri),
            URLQueryItem(name: "client_id", value: Self.clientID),
        ]

        let authURL = authComponents.url!
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callback: .customScheme("grain")
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

        // Step 3: Exchange code for tokens
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL
        }

        // hatk sends `error` instead of `code` when the PDS rejects the request,
        // most often because the user tapped "Deny" on the sign-in screen.
        if let errorCode = components.queryItems?.first(where: { $0.name == "error" })?.value {
            let description = components.queryItems?.first(where: { $0.name == "error_description" })?.value
            throw errorCode == "access_denied"
                ? XRPCError.authorizationDenied
                : XRPCError.authorizationFailed(code: errorCode, description: description)
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw XRPCError.invalidURL
        }

        try await exchangeCode(code: code, dpop: dpop)
        await fetchAndStoreAvatar()
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
              let refreshToken = TokenStorage.refreshToken(for: did)
        else {
            throw XRPCError.unauthorized
        }

        let tokenURL = Self.serverURL.appendingPathComponent("oauth/token")
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ]
        request.httpBody = body.urlEncoded.data(using: .utf8)

        let proof = try await dpop.createProof(httpMethod: "POST", url: tokenURL)
        request.setValue(proof, forHTTPHeaderField: "DPoP")

        var (data, response) = try await URLSession.shared.data(for: request)

        // Handle DPoP nonce requirement
        if let httpResp = response as? HTTPURLResponse,
           httpResp.statusCode == 400,
           let nonce = httpResp.value(forHTTPHeaderField: "DPoP-Nonce")
        {
            let retryProof = try await dpop.createProof(httpMethod: "POST", url: tokenURL, nonce: nonce)
            request.setValue(retryProof, forHTTPHeaderField: "DPoP")
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw XRPCError.unauthorized
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
            logger.error("Token refresh failed (\(httpResponse.statusCode)): \(bodyStr)")

            // Body keyword check covers legacy hatk (HTTP 500 + plain message) before it returned RFC 6749 invalid_grant.
            let lower = bodyStr.lowercased()
            let bodyClaimsTerminal = lower.contains("invalid_grant")
                || lower.contains("refresh token")
                || lower.contains("revoked")
                || lower.contains("expired")
            let isTerminal = (400 ... 499).contains(httpResponse.statusCode) || bodyClaimsTerminal
            if isTerminal {
                // The grant is gone — drop this account. If it's the one on
                // screen, fall through to whichever account is left.
                forget(did: did)
                if userDID == did {
                    activateNextAccountOrSignOut()
                }
            }
            throw XRPCError.unauthorized
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        store(tokenResponse, for: did, dpop: nil, makeActive: false)
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
              let token = TokenStorage.accessToken(for: currentDID) else { return nil }
        return AuthContext(accessToken: token, dpop: currentDpop)
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

    private func exchangeCode(code: String, dpop: DPoP) async throws {
        let tokenURL = Self.serverURL.appendingPathComponent("oauth/token")
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": Self.clientID,
            "code_verifier": codeVerifier ?? "",
        ]
        request.httpBody = body.urlEncoded.data(using: .utf8)

        let proof = try await dpop.createProof(httpMethod: "POST", url: tokenURL)
        request.setValue(proof, forHTTPHeaderField: "DPoP")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Handle DPoP nonce retry
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 400,
           let nonce = httpResponse.value(forHTTPHeaderField: "DPoP-Nonce")
        {
            let retryProof = try await dpop.createProof(httpMethod: "POST", url: tokenURL, nonce: nonce)
            var retryRequest = request
            retryRequest.setValue(retryProof, forHTTPHeaderField: "DPoP")
            let (retryData, _) = try await URLSession.shared.data(for: retryRequest)
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: retryData)
            store(tokenResponse, for: tokenResponse.sub, dpop: dpop, makeActive: true)
            return
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        store(tokenResponse, for: tokenResponse.sub, dpop: dpop, makeActive: true)
    }

    /// Persist a token response under `did`. Pass the `dpop` the tokens were
    /// minted with on a fresh sign-in so it's saved alongside them; refreshes
    /// reuse the account's stored key and pass nil.
    private func store(_ response: TokenResponse, for did: String, dpop: DPoP?, makeActive: Bool) {
        if let dpop {
            try? dpop.persist(for: did)
        }
        TokenStorage.storeTokens(
            did: did,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            handle: response.handle,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            scope: response.scope
        )
        TokenStorage.upsertAccount(StoredAccount(did: did, handle: response.handle, avatar: nil))
        accounts = TokenStorage.accounts

        guard makeActive else { return }
        setActiveDID(did)
        self.dpop = dpop ?? (try? DPoP.loadOrCreate(for: did))

        // Guard each @Observable assignment: the macro's setter always fires the
        // observation registrar even when the value is unchanged, so token refreshes
        // would otherwise invalidate every observer (including GrainApp.body).
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
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                avatarImage = image
            }
        } catch {
            logger.error("Avatar download failed: \(error)")
        }
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
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
        guard TokenStorage.hasCredentials(for: did), let newDpop = try? DPoP.loadOrCreate(for: did) else {
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
                if !TokenStorage.hasCredentials(for: did) {
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
            forget(did: did)
            activateNextAccountOrSignOut()
        } else {
            forget(did: did)
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
        guard let next = TokenStorage.accounts.first(where: { TokenStorage.hasCredentials(for: $0.did) }),
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

// MARK: - Response Types

private struct PARResponse: Codable {
    let requestUri: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case requestUri = "request_uri"
        case expiresIn = "expires_in"
    }
}

private struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let sub: String
    let handle: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case sub
        case handle
        case scope
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

// MARK: - Helpers

extension [String: String] {
    var urlEncoded: String {
        map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }
}

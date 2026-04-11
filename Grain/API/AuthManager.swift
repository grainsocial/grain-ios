import AuthenticationServices
import CryptoKit
import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "Auth")
private let authSignposter = OSSignposter(subsystem: "social.grain.grain", category: "Auth")

/// Manages OAuth + DPoP authentication flow against the hatk server.
@Observable
@MainActor
final class AuthManager {
    var isAuthenticated = false
    var userDID: String?
    var userHandle: String?
    var userAvatar: String?
    var avatarImage: UIImage?
    /// Set when a launch-time scope migration forced the user to sign out.
    /// LoginView reads this to display an explanation above the sign-in form.
    var reauthReason: String?

    private(set) var dpop: DPoP?
    private var codeVerifier: String?
    private var client: XRPCClient?
    private var refreshTask: Task<Void, Error>?

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
        // Restore session from Keychain — allow expired tokens since we can refresh
        if TokenStorage.accessToken != nil,
           let did = TokenStorage.userDID,
           TokenStorage.refreshToken != nil
        {
            isAuthenticated = true
            userDID = did
            userHandle = TokenStorage.userHandle
            userAvatar = TokenStorage.userAvatar
            authSignposter.emitEvent("KeychainRead", id: spid, "authenticated=true")
            logger.debug("[KeychainRead] authenticated=true")
            let dpopSpid = authSignposter.makeSignpostID()
            let dpopState = authSignposter.beginInterval("DPoPLoad", id: dpopSpid)
            logger.debug("[DPoPLoad] begin")
            dpop = try? DPoP.loadOrCreate()
            authSignposter.endInterval("DPoPLoad", dpopState)
            logger.debug("[DPoPLoad] end")

            runScopeMigrationIfNeeded()
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
    private func runScopeMigrationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.scopeMigrationKey) else { return }

        let stored = TokenStorage.grantedScope.map { Set($0.split(separator: " ").map(String.init)) } ?? []
        let missing = Self.requiredScopes.filter { !stored.contains($0) }
        guard !missing.isEmpty else {
            // Nothing to do — stored token already covers every required scope.
            UserDefaults.standard.set(true, forKey: Self.scopeMigrationKey)
            return
        }

        logger.info("[ScopeMigration] forcing re-auth; missing=\(missing.joined(separator: ","), privacy: .public)")
        UserDefaults.standard.set(true, forKey: Self.scopeMigrationKey)
        logout()
        reauthReason = "Grain has been updated. Please sign in again to enable new features."
    }

    /// Start the OAuth login flow. Set `createAccount` to show the sign-up page.
    func login(handle: String = "", createAccount: Bool = false) async throws {
        let dpop = try DPoP.loadOrCreate()
        self.dpop = dpop

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
            #if DEBUG
                parBody["login_hint"] = "localhost:2583"
            #else
                parBody["login_hint"] = "selfhosted.social"
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
                if let error { continuation.resume(throwing: error); return }
                guard let url else { continuation.resume(throwing: XRPCError.invalidURL); return }
                continuation.resume(returning: url)
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = WebAuthContextProvider.shared
            session.start()
        }

        // Step 3: Exchange code for tokens
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw XRPCError.invalidURL
        }

        try await exchangeCode(code: code, dpop: dpop)
        await fetchAndStoreAvatar()
    }

    /// Refresh the access token only if it expires within 60 seconds.
    func refreshIfNeeded() async throws {
        guard let expiresAt = TokenStorage.tokenExpiresAt, expiresAt.timeIntervalSinceNow < 60 else { return }
        try await refresh()
    }

    /// Refresh the access token using the refresh token. Coalesces concurrent calls.
    func refresh() async throws {
        if let existing = refreshTask {
            return try await existing.value
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { throw XRPCError.unauthorized }
            defer { self.refreshTask = nil }
            try await performRefresh()
        }
        refreshTask = task
        try await task.value
    }

    private func performRefresh() async throws {
        guard let dpop, let refreshToken = TokenStorage.refreshToken else {
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
            if httpResponse.statusCode == 401 {
                logout()
            }
            throw XRPCError.unauthorized
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeTokens(tokenResponse)
    }

    /// Callback invoked before credentials are cleared on logout.
    var onLogout: (() -> Void)?

    /// Log out and clear all stored credentials.
    func logout() {
        onLogout?()
        TokenStorage.clear()
        try? DPoP.clearKey()
        isAuthenticated = false
        userDID = nil
        userHandle = nil
        dpop = nil
    }

    /// Build an AuthContext for making authenticated requests.
    /// Proactively refreshes if the token expires within 60 seconds.
    func authContext() async -> AuthContext? {
        guard let dpop else { return nil }
        if let expiresAt = TokenStorage.tokenExpiresAt, expiresAt.timeIntervalSinceNow < 60 {
            try? await refresh()
        }
        guard let token = TokenStorage.accessToken else { return nil }
        return AuthContext(accessToken: token, dpop: dpop)
    }

    /// Create an XRPCClient with automatic token refresh on 401.
    func makeClient() -> XRPCClient {
        XRPCClient(baseURL: Self.serverURL) { [weak self] in
            try await self?.refresh()
            return await self?.authContext()
        }
    }

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
            storeTokens(tokenResponse)
            return
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeTokens(tokenResponse)
    }

    private func storeTokens(_ response: TokenResponse) {
        TokenStorage.accessToken = response.accessToken
        TokenStorage.refreshToken = response.refreshToken
        TokenStorage.userDID = response.sub
        TokenStorage.userHandle = response.handle
        TokenStorage.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        if let scope = response.scope {
            TokenStorage.grantedScope = scope
        }

        // Guard each @Observable assignment: the macro's setter always fires the
        // observation registrar even when the value is unchanged, so token refreshes
        // would otherwise invalidate every observer (including GrainApp.body).
        if !isAuthenticated { isAuthenticated = true }
        if userDID != response.sub { userDID = response.sub }
        if userHandle != response.handle { userHandle = response.handle }
        if reauthReason != nil { reauthReason = nil }
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
            if userAvatar != profile.avatar {
                userAvatar = profile.avatar
                TokenStorage.userAvatar = profile.avatar
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

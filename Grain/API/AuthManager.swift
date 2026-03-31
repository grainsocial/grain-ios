import AuthenticationServices
import CryptoKit
import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "Auth")

/// Manages OAuth + DPoP authentication flow against the hatk server.
@Observable
@MainActor
final class AuthManager {
    var isAuthenticated = false
    var userDID: String?
    var userHandle: String?
    var userAvatar: String?
    var avatarImage: UIImage?

    private(set) var dpop: DPoP?
    private var codeVerifier: String?
    private var client: XRPCClient?

    #if DEBUG
    static let serverURL = URL(string: "http://127.0.0.1:3000")!
    #else
    static let serverURL = URL(string: "https://grain.social")!
    #endif
    static let clientID = "grain-native://app"
    static let redirectURI = "grain://oauth/callback"

    init() {
        // Restore session from Keychain
        if let token = TokenStorage.accessToken,
           let did = TokenStorage.userDID,
           !TokenStorage.isExpired {
            self.isAuthenticated = true
            self.userDID = did
            self.userHandle = TokenStorage.userHandle
            self.userAvatar = TokenStorage.userAvatar
            self.dpop = try? DPoP.loadOrCreate()
            _ = token // Token is available via TokenStorage
        }
    }

    /// Start the OAuth login flow.
    func login(handle: String) async throws {
        let dpop = try DPoP.loadOrCreate()
        self.dpop = dpop

        let client = XRPCClient(baseURL: Self.serverURL)
        self.client = client

        // Generate PKCE code verifier + challenge
        let verifier = generateCodeVerifier()
        self.codeVerifier = verifier
        let challenge = generateCodeChallenge(verifier: verifier)

        // Step 1: Pushed Authorization Request
        let parBody: [String: String] = [
            "client_id": Self.clientID,
            "redirect_uri": Self.redirectURI,
            "response_type": "code",
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            "scope": "atproto blob:image/* repo:social.grain.gallery repo:social.grain.gallery.item repo:social.grain.photo repo:social.grain.photo.exif repo:social.grain.actor.profile repo:social.grain.graph.follow repo:social.grain.favorite repo:social.grain.comment repo:social.grain.story repo:app.bsky.feed.post?action=create",
            "login_hint": handle
        ]

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
           let nonce = httpResp.value(forHTTPHeaderField: "DPoP-Nonce") {
            let retryProof = try await dpop.createProof(httpMethod: "POST", url: parURL, nonce: nonce)
            parRequest.setValue(retryProof, forHTTPHeaderField: "DPoP")
            (parData, parHTTPResponse) = try await URLSession.shared.data(for: parRequest)
        }

        // Log response for debugging
        if let httpResp = parHTTPResponse as? HTTPURLResponse, httpResp.statusCode != 200 && httpResp.statusCode != 201 {
            let body = String(data: parData, encoding: .utf8) ?? "no body"
            print("[Grain Auth] PAR failed (\(httpResp.statusCode)): \(body)")
            throw XRPCError.httpError(statusCode: httpResp.statusCode, body: parData)
        }

        let parResponse = try JSONDecoder().decode(PARResponse.self, from: parData)

        // Step 2: Open browser for authorization
        var authComponents = URLComponents(url: Self.serverURL.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false)!
        authComponents.queryItems = [
            URLQueryItem(name: "request_uri", value: parResponse.requestUri),
            URLQueryItem(name: "client_id", value: Self.clientID)
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
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw XRPCError.invalidURL
        }

        try await exchangeCode(code: code, dpop: dpop)
        await fetchAndStoreAvatar()
    }

    /// Refresh the access token using the refresh token.
    func refresh() async throws {
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
            "client_id": Self.clientID
        ]
        request.httpBody = body.urlEncoded.data(using: .utf8)

        let proof = try await dpop.createProof(httpMethod: "POST", url: tokenURL)
        request.setValue(proof, forHTTPHeaderField: "DPoP")

        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeTokens(tokenResponse)
    }

    /// Log out and clear all stored credentials.
    func logout() {
        TokenStorage.clear()
        try? DPoP.clearKey()
        isAuthenticated = false
        userDID = nil
        userHandle = nil
        dpop = nil
    }

    /// Build an AuthContext for making authenticated requests.
    func authContext() -> AuthContext? {
        guard let dpop, let token = TokenStorage.accessToken else { return nil }
        return AuthContext(accessToken: token, dpop: dpop)
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
            "code_verifier": codeVerifier ?? ""
        ]
        request.httpBody = body.urlEncoded.data(using: .utf8)

        let proof = try await dpop.createProof(httpMethod: "POST", url: tokenURL)
        request.setValue(proof, forHTTPHeaderField: "DPoP")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Handle DPoP nonce retry
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 400,
           let nonce = httpResponse.value(forHTTPHeaderField: "DPoP-Nonce") {
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

        isAuthenticated = true
        userDID = response.sub
        userHandle = response.handle
    }

    func fetchAvatarIfNeeded() async {
        if userAvatar != nil && avatarImage == nil {
            await downloadAvatarImage()
        }
        if userAvatar == nil && userDID != nil {
            await fetchAndStoreAvatar()
        }
    }

    private func fetchAndStoreAvatar() async {
        guard let did = userDID else { return }
        let client = XRPCClient(baseURL: Self.serverURL)
        do {
            let profile = try await client.getActorProfile(actor: did)
            userAvatar = profile.avatar
            TokenStorage.userAvatar = profile.avatar
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

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case sub
        case handle
    }
}

// MARK: - ASWebAuthenticationSession Context

import UIKit

final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

// MARK: - Helpers

extension Dictionary where Key == String, Value == String {
    var urlEncoded: String {
        map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }
}

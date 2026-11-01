import CryptoKit
import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "OAuth")

/// Why signing in failed, in words the login screen can show.
enum OAuthError: Error, LocalizedError, Equatable {
    case handleRequired
    case handleNotFound(String)
    case unsupportedDID(String)
    case noPDS(String)
    /// The PDS names no authorization server, or that server publishes no
    /// metadata.
    case noAuthorizationServer(String)
    /// The authorization server's metadata names a different issuer than the
    /// one the PDS pointed at.
    case issuerMismatch(expected: String, found: String)
    /// The browser came back from a sign-in this one did not start.
    case callbackMismatch
    /// The tokens are for another account than the one asked for.
    case wrongAccount(expected: String, found: String)
    /// A sign-up named an account whose PDS signs in somewhere else.
    case accountElsewhere(did: String)
    case unsupportedTokenType(String)
    /// The authorization server refused a request.
    case refused(status: Int, error: String?, description: String?)

    var errorDescription: String? {
        switch self {
        case .handleRequired:
            "Enter your handle to sign in."
        case let .handleNotFound(handle):
            "Couldn't find an account for \(handle)."
        case let .unsupportedDID(did):
            "\(did) isn't a kind of account Grain can sign in to."
        case let .noPDS(did):
            "Couldn't find where \(did) is hosted."
        case let .noAuthorizationServer(pds):
            "\(pds) doesn't support signing in with OAuth."
        case let .issuerMismatch(expected, _):
            "The sign-in server at \(expected) is misconfigured."
        case .callbackMismatch:
            "Sign-in didn't complete. Try again."
        case .wrongAccount:
            "You signed in to a different account than the one you entered."
        case .accountElsewhere:
            "The new account isn't hosted where it was created."
        case let .unsupportedTokenType(type):
            "The sign-in server issued an unsupported token (\(type))."
        case let .refused(status, error, description):
            description ?? error.map { "Sign-in failed (\($0))" } ?? "Sign-in failed (HTTP \(status))"
        }
    }
}

/// An authorization server's endpoints, from its metadata.
struct AuthorizationServer: Codable, Sendable, Equatable {
    let issuer: String
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let pushedAuthorizationRequestEndpoint: URL
    let revocationEndpoint: URL?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case pushedAuthorizationRequestEndpoint = "pushed_authorization_request_endpoint"
        case revocationEndpoint = "revocation_endpoint"
    }
}

/// A token response.
struct OAuthTokens: Decodable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int?
    let refreshToken: String?
    let sub: String
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case sub
        case scope
    }

    var expiresAt: Date {
        Date().addingTimeInterval(TimeInterval(expiresIn ?? 300))
    }
}

/// An authorization request pushed to the account's server, waiting for the
/// user to approve it in the browser.
struct PendingAuthorization: Sendable {
    /// The page where the user approves it.
    let url: URL
    let state: String
    /// Who the user said they are: nil for an account they are making.
    let identity: ResolvedIdentity?
    let server: AuthorizationServer
    let dpop: DPoP
    let verifier: String
    let scope: String
}

/// A redeemed sign-in: everything an account keeps.
struct OAuthSession: Sendable {
    let identity: ResolvedIdentity
    let server: AuthorizationServer
    let tokens: OAuthTokens
    let dpop: DPoP
    /// The scope granted, or the one asked for when the server does not say.
    let scope: String
}

/// atproto OAuth as a public native client: PAR, PKCE (S256) and DPoP-bound
/// tokens, with each server's nonce kept per origin.
struct OAuthClient: Sendable {
    let session: URLSession
    let clientID: String
    let redirectURI: String
    var resolver: IdentityResolver

    init(session: URLSession, clientID: String, redirectURI: String) {
        self.session = session
        self.clientID = clientID
        self.redirectURI = redirectURI
        resolver = IdentityResolver(session: session)
    }

    // MARK: - Discovery

    /// The authorization server for accounts on `pds`.
    func server(forPDS pds: URL) async throws -> AuthorizationServer {
        struct Resource: Decodable {
            let authorizationServers: [String]?
            enum CodingKeys: String, CodingKey { case authorizationServers = "authorization_servers" }
        }
        let base = pds.absoluteString.trimmingSuffix("/")
        guard let resourceURL = URL(string: "\(base)/.well-known/oauth-protected-resource"),
              let resource: Resource = try? await getJSON(resourceURL),
              let issuer = resource.authorizationServers?.first,
              let metadataURL = URL(string: "\(issuer.trimmingSuffix("/"))/.well-known/oauth-authorization-server")
        else { throw OAuthError.noAuthorizationServer(base) }
        guard let server: AuthorizationServer = try? await getJSON(metadataURL) else {
            throw OAuthError.noAuthorizationServer(issuer)
        }
        guard server.issuer == issuer else {
            throw OAuthError.issuerMismatch(expected: issuer, found: server.issuer)
        }
        return server
    }

    private func getJSON<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OAuthError.refused(status: (response as? HTTPURLResponse)?.statusCode ?? 0, error: nil, description: nil)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Authorization

    /// Push a request to act as `identity` with `scope`. `hint` is who the
    /// user said they are.
    func authorize(_ identity: ResolvedIdentity, hint: String, scope: String) async throws -> PendingAuthorization {
        let server = try await server(forPDS: identity.pds)
        return try await push(to: server, identity: identity, asking: ["login_hint": hint], scope: scope)
    }

    /// Push a request to act with `scope` as an account the user makes first
    /// on `pds`, on the sign-up page its authorization server shows for
    /// `prompt=create`. Who they are is known once it is redeemed.
    func signUp(at pds: URL, scope: String) async throws -> PendingAuthorization {
        let server = try await server(forPDS: pds)
        return try await push(to: server, identity: nil, asking: ["prompt": "create"], scope: scope)
    }

    private func push(
        to server: AuthorizationServer,
        identity: ResolvedIdentity?,
        asking: [String: String],
        scope: String
    ) async throws -> PendingAuthorization {
        let dpop = DPoP.createEphemeral()
        let verifier = Self.random(32)
        let state = Self.random(16)
        var form = [
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "response_type": "code",
            "code_challenge": Self.challenge(for: verifier),
            "code_challenge_method": "S256",
            "scope": scope,
            "state": state,
        ]
        form.merge(asking) { _, new in new }

        struct Pushed: Decodable {
            let requestURI: String
            enum CodingKeys: String, CodingKey { case requestURI = "request_uri" }
        }
        let pushed: Pushed = try await post(server.pushedAuthorizationRequestEndpoint, form: form, dpop: dpop)

        var components = URLComponents(url: server.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "request_uri", value: pushed.requestURI),
        ]
        guard let url = components.url else { throw XRPCError.invalidURL }
        return PendingAuthorization(
            url: url, state: state, identity: identity, server: server,
            dpop: dpop, verifier: verifier, scope: scope
        )
    }

    /// Trade the code the browser came back with for tokens, and check they
    /// are for the account asked for.
    func redeem(_ pending: PendingAuthorization, callback: URL) async throws -> OAuthSession {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let params = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })

        guard params["state"] == pending.state else { throw OAuthError.callbackMismatch }
        if let iss = params["iss"], iss != pending.server.issuer {
            throw OAuthError.callbackMismatch
        }
        if let error = params["error"] {
            throw error == "access_denied"
                ? XRPCError.authorizationDenied
                : XRPCError.authorizationFailed(code: error, description: params["error_description"])
        }
        guard let code = params["code"] else { throw OAuthError.callbackMismatch }

        let tokens: OAuthTokens = try await post(
            pending.server.tokenEndpoint,
            form: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectURI,
                "client_id": clientID,
                "code_verifier": pending.verifier,
            ],
            dpop: pending.dpop
        )
        guard tokens.tokenType.caseInsensitiveCompare("DPoP") == .orderedSame else {
            throw OAuthError.unsupportedTokenType(tokens.tokenType)
        }

        let identity: ResolvedIdentity = if let asked = pending.identity {
            asked
        } else {
            try await made(tokens.sub, at: pending.server.issuer)
        }
        guard tokens.sub == identity.did else {
            throw OAuthError.wrongAccount(expected: identity.did, found: tokens.sub)
        }
        return OAuthSession(
            identity: identity, server: pending.server, tokens: tokens,
            dpop: pending.dpop, scope: tokens.scope ?? pending.scope
        )
    }

    /// The account `did`, which a sign-up at the server `issuer` made. As
    /// atproto's OAuth asks, it is taken only if its PDS signs in there: else
    /// any server could name any account.
    func made(_ did: String, at issuer: String) async throws -> ResolvedIdentity {
        let identity = try await resolver.resolve(did)
        let theirs = try await server(forPDS: identity.pds).issuer
        guard theirs == issuer else { throw OAuthError.accountElsewhere(did: did) }
        return identity
    }

    // MARK: - Tokens

    /// New tokens for a session, from the token endpoint it signed in at.
    func refresh(refreshToken: String, tokenEndpoint: URL, dpop: DPoP) async throws -> OAuthTokens {
        try await post(
            tokenEndpoint,
            form: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID,
            ],
            dpop: dpop
        )
    }

    /// Revoke a session's refresh token, as far as its server lets it.
    func revoke(refreshToken: String, revocationEndpoint: URL, dpop: DPoP) async throws {
        _ = try await postForm(
            revocationEndpoint,
            form: ["token": refreshToken, "client_id": clientID],
            dpop: dpop
        )
    }

    // MARK: - Requests

    private func post<T: Decodable>(_ url: URL, form: [String: String], dpop: DPoP) async throws -> T {
        let data = try await postForm(url, form: form, dpop: dpop)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw XRPCError.decodingError(error)
        }
    }

    /// POST `form` with a DPoP proof, sending it again once when the server
    /// answers `use_dpop_nonce`.
    private func postForm(_ url: URL, form: [String: String], dpop: DPoP) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(form.formEncoded.utf8)

        var attempt = 0
        while true {
            attempt += 1
            try await request.setValue(dpop.createProof(httpMethod: "POST", url: url), forHTTPHeaderField: "DPoP")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OAuthError.refused(status: 0, error: nil, description: nil)
            }
            DPoPNonces.shared.keep(from: http, for: url)
            if (200 ... 299).contains(http.statusCode) {
                return data
            }
            struct Refusal: Decodable {
                let error: String?
                let errorDescription: String?
                enum CodingKeys: String, CodingKey {
                    case error
                    case errorDescription = "error_description"
                }
            }
            let refusal = try? JSONDecoder().decode(Refusal.self, from: data)
            if refusal?.error == "use_dpop_nonce", attempt == 1 {
                continue
            }
            logger.error("OAuth \(url.path, privacy: .public) refused (\(http.statusCode)): \(refusal?.error ?? "no error", privacy: .public)")
            throw OAuthError.refused(status: http.statusCode, error: refusal?.error, description: refusal?.errorDescription)
        }
    }

    // MARK: - PKCE

    static func random(_ bytes: Int) -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64URLEncoded()
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }
}

// MARK: - Helpers

extension [String: String] {
    /// `application/x-www-form-urlencoded`, every byte but the unreserved
    /// ones escaped: a scope carries `?`, `&`, `=` and `%`.
    var formEncoded: String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return sorted { $0.key < $1.key }.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: unreserved) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        var trimmed = self
        while trimmed.hasSuffix(suffix) {
            trimmed.removeLast(suffix.count)
        }
        return trimmed
    }
}

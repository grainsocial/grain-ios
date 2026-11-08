import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "XRPC")

enum XRPCError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, body: Data?)
    case decodingError(Error)
    case unauthorized
    /// The authorization server refused the request, usually the user tapping "Deny".
    case authorizationDenied
    /// Any other OAuth error handed back on the callback URL.
    case authorizationFailed(code: String, description: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid URL"
        case let .httpError(code, _): "HTTP error \(code)"
        case let .decodingError(error): "Decoding error: \(error.localizedDescription)"
        case .unauthorized: "Unauthorized"
        case .authorizationDenied: "Sign-in canceled"
        case let .authorizationFailed(code, description): description ?? "Sign-in failed (\(code))"
        }
    }
}

/// XRPC client for Grain's calls.
///
/// A call without an auth context goes to `baseURL`, Grain's AppView, as is.
/// A call with one goes to the account's PDS, with a DPoP-bound token and a
/// proof per request; every method outside `com.atproto.*`, and a report,
/// also carries an `atproto-proxy` header, so the PDS forwards it to the
/// AppView with a service token, as Bluesky's apps reach their AppView.
final class XRPCClient: Sendable {
    let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let onUnauthorized: (@Sendable () async throws -> AuthContext?)?

    init(baseURL: URL, session: URLSession = NetworkEnvironment.session, onUnauthorized: (@Sendable () async throws -> AuthContext?)? = nil) {
        self.baseURL = baseURL
        self.session = session
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        self.onUnauthorized = onUnauthorized
    }

    /// Execute an XRPC query (GET request).
    func query<T: Decodable>(
        _ nsid: String,
        params: [String: String] = [:],
        auth: AuthContext? = nil,
        as type: T.Type
    ) async throws -> T {
        let data = try await perform(nsid, auth: auth) { base in
            var components = URLComponents(url: base.appendingPathComponent("xrpc/\(nsid)"), resolvingAgainstBaseURL: false)!
            if !params.isEmpty {
                components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
            }
            guard let url = components.url else { throw XRPCError.invalidURL }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            return request
        }
        return try decode(type, from: data)
    }

    /// Execute an XRPC procedure (POST request).
    func procedure<O: Decodable>(
        _ nsid: String,
        input: some Encodable,
        auth: AuthContext? = nil,
        as type: O.Type
    ) async throws -> O {
        let body = try encoder.encode(input)
        let data = try await perform(nsid, auth: auth) { base in
            Self.post(base, nsid, body: body, contentType: "application/json")
        }
        return try decode(type, from: data)
    }

    /// Execute an XRPC procedure with no response body.
    func procedure(
        _ nsid: String,
        input: some Encodable,
        auth: AuthContext? = nil
    ) async throws {
        let body = try encoder.encode(input)
        _ = try await perform(nsid, auth: auth) { base in
            Self.post(base, nsid, body: body, contentType: "application/json")
        }
    }

    /// Upload a blob to the account's PDS.
    func uploadBlob(
        data: Data,
        mimeType: String,
        auth: AuthContext? = nil
    ) async throws -> UploadBlobResponse {
        let nsid = "com.atproto.repo.uploadBlob"
        let response = try await perform(nsid, auth: auth) { base in
            Self.post(base, nsid, body: data, contentType: mimeType)
        }
        return try decode(UploadBlobResponse.self, from: response)
    }

    /// The `atproto-proxy` value a signed-in call to `nsid` carries, if any:
    /// grain's AppView for every method outside `com.atproto.*`, and for a
    /// report, which grain files rather than the PDS's moderation service.
    static func proxy(for nsid: String) -> String? {
        if nsid == createReportMethod {
            return AuthManager.appviewService
        }
        return nsid.hasPrefix("com.atproto.") ? nil : AuthManager.appviewService
    }

    // MARK: - Private

    private static func post(_ base: URL, _ nsid: String, body: Data, contentType: String) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent("xrpc/\(nsid)"))
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw XRPCError.decodingError(error)
        }
    }

    /// Send the request `build` makes against the base URL a context calls
    /// for, and return the body of a 2xx answer.
    ///
    /// A DPoP nonce refusal (401 with `use_dpop_nonce` in `WWW-Authenticate`,
    /// or 400 with it as the error) is sent again once with the nonce. Any
    /// other 401 asks `onUnauthorized` for a renewed context once and sends
    /// the request again with it.
    private func perform(
        _ nsid: String,
        auth initial: AuthContext?,
        build: (URL) throws -> URLRequest
    ) async throws -> Data {
        var auth = initial
        var refreshed = false
        var nonceRetried = false

        while true {
            var request = try build(auth?.pds ?? baseURL)
            try await applyAuth(&request, nsid: nsid, auth: auth)

            let (data, response) = try await send(request)
            guard let http = response as? HTTPURLResponse else {
                throw XRPCError.httpError(statusCode: 0, body: data)
            }
            if let url = request.url {
                DPoPNonces.shared.keep(from: http, for: url)
            }

            if auth != nil, !nonceRetried, Self.isNonceRefusal(http, body: data) {
                logger.info("DPoP nonce required, retrying with nonce")
                nonceRetried = true
                continue
            }

            if http.statusCode == 401 {
                let wwwAuth = http.value(forHTTPHeaderField: "WWW-Authenticate")
                logger.error("401 \(nsid, privacy: .public): wwwAuth=\(wwwAuth ?? "nil", privacy: .public)")
                if !refreshed, let onUnauthorized {
                    refreshed = true
                    do {
                        if let renewed = try await onUnauthorized() {
                            logger.info("Token refreshed, retrying request")
                            auth = renewed
                            nonceRetried = false
                            continue
                        }
                    } catch {
                        logger.error("Token refresh failed: \(error)")
                    }
                }
                throw XRPCError.unauthorized
            }

            guard (200 ... 299).contains(http.statusCode) else {
                logger.error("HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
                throw XRPCError.httpError(statusCode: http.statusCode, body: data)
            }
            return data
        }
    }

    static func isNonceRefusal(_ response: HTTPURLResponse, body: Data) -> Bool {
        switch response.statusCode {
        case 401:
            return response.value(forHTTPHeaderField: "WWW-Authenticate")?.contains("use_dpop_nonce") ?? false
        case 400:
            struct Refusal: Decodable { let error: String? }
            return (try? JSONDecoder().decode(Refusal.self, from: body))?.error == "use_dpop_nonce"
        default:
            return false
        }
    }

    /// Single funnel for network I/O, so DEBUG latency simulation covers every
    /// request including retries. See `DebugDelay`.
    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        #if DEBUG
            await DebugDelay.wait()
        #endif
        return try await session.data(for: request)
    }

    private func applyAuth(_ request: inout URLRequest, nsid: String, auth: AuthContext?) async throws {
        guard let auth, let url = request.url else { return }
        request.setValue("DPoP \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        let proof = try await auth.dpop.createProof(
            httpMethod: request.httpMethod ?? "GET",
            url: url,
            accessToken: auth.accessToken
        )
        request.setValue(proof, forHTTPHeaderField: "DPoP")
        if let proxy = Self.proxy(for: nsid) {
            request.setValue(proxy, forHTTPHeaderField: "atproto-proxy")
        }
    }
}

/// Context for authenticated requests: the active account's token, its DPoP
/// key, and where its repo lives.
struct AuthContext: Sendable {
    let accessToken: String
    let dpop: DPoP
    /// The account's DID, the repo its writes go to.
    let did: String
    /// The account's PDS, where every call carrying this context goes.
    let pds: URL
}

struct UploadBlobResponse: Codable, Sendable {
    let blob: BlobRef
}

import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "XRPC")

enum XRPCError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, body: Data?)
    case decodingError(Error)
    case unauthorized
    case dpopNonceRequired(nonce: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid URL"
        case let .httpError(code, _): "HTTP error \(code)"
        case let .decodingError(error): "Decoding error: \(error.localizedDescription)"
        case .unauthorized: "Unauthorized"
        case .dpopNonceRequired: "DPoP nonce required"
        }
    }
}

/// XRPC client for communicating with the hatk server.
final class XRPCClient: Sendable {
    let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let onUnauthorized: (@Sendable () async throws -> AuthContext?)?

    init(baseURL: URL, session: URLSession = .shared, onUnauthorized: (@Sendable () async throws -> AuthContext?)? = nil) {
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
        var components = URLComponents(url: baseURL.appendingPathComponent("xrpc/\(nsid)"), resolvingAgainstBaseURL: false)!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw XRPCError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        return try await executeWithRetry(request, auth: auth, as: type)
    }

    /// Execute an XRPC procedure (POST request).
    func procedure<O: Decodable>(
        _ nsid: String,
        input: some Encodable,
        auth: AuthContext? = nil,
        as type: O.Type
    ) async throws -> O {
        let url = baseURL.appendingPathComponent("xrpc/\(nsid)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(input)

        return try await executeWithRetry(request, auth: auth, as: type)
    }

    /// Execute an XRPC procedure with no response body.
    func procedure(
        _ nsid: String,
        input: some Encodable,
        auth: AuthContext? = nil
    ) async throws {
        let url = baseURL.appendingPathComponent("xrpc/\(nsid)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(input)

        try await executeVoidWithRetry(request, auth: auth)
    }

    /// Upload a blob (binary data).
    func uploadBlob(
        data: Data,
        mimeType: String,
        auth: AuthContext? = nil
    ) async throws -> UploadBlobResponse {
        let url = baseURL.appendingPathComponent("xrpc/dev.hatk.uploadBlob")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        return try await executeWithRetry(request, auth: auth, as: UploadBlobResponse.self)
    }

    // MARK: - Private

    private func executeWithRetry<T: Decodable>(
        _ request: URLRequest,
        auth: AuthContext?,
        as type: T.Type,
        retryCount: Int = 0
    ) async throws -> T {
        var req = request
        try await applyAuth(&req, auth: auth)

        do {
            return try await execute(req, as: type)
        } catch let XRPCError.dpopNonceRequired(nonce) where retryCount < 2 {
            logger.info("DPoP nonce required, retrying with nonce")
            var updatedAuth = auth
            updatedAuth?.nonce = nonce
            var retryReq = request
            try await applyAuth(&retryReq, auth: updatedAuth)
            return try await execute(retryReq, as: type)
        } catch XRPCError.unauthorized where retryCount < 1 {
            if let onUnauthorized {
                do {
                    if let newAuth = try await onUnauthorized() {
                        logger.info("Token refreshed, retrying request")
                        return try await executeWithRetry(request, auth: newAuth, as: type, retryCount: retryCount + 1)
                    }
                } catch {
                    logger.error("Token refresh failed: \(error)")
                }
            }
            throw XRPCError.unauthorized
        }
    }

    private func executeVoidWithRetry(
        _ request: URLRequest,
        auth: AuthContext?,
        retryCount: Int = 0
    ) async throws {
        var req = request
        try await applyAuth(&req, auth: auth)

        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { return }

        if httpResponse.statusCode == 400,
           let nonce = httpResponse.value(forHTTPHeaderField: "DPoP-Nonce"),
           retryCount < 2
        {
            logger.info("DPoP nonce required (void), retrying")
            var updatedAuth = auth
            updatedAuth?.nonce = nonce
            var retryReq = request
            try await applyAuth(&retryReq, auth: updatedAuth)
            let (_, retryResponse) = try await session.data(for: retryReq)
            guard let retryHttp = retryResponse as? HTTPURLResponse else { return }
            if retryHttp.statusCode == 401 { throw XRPCError.unauthorized }
            guard (200 ... 299).contains(retryHttp.statusCode) else {
                throw XRPCError.httpError(statusCode: retryHttp.statusCode, body: nil)
            }
            return
        }

        if httpResponse.statusCode == 401 {
            // Try once more with DPoP-Nonce from response if present
            if let nonce = httpResponse.value(forHTTPHeaderField: "DPoP-Nonce"), retryCount < 2 {
                logger.info("401 with nonce, retrying")
                var updatedAuth = auth
                updatedAuth?.nonce = nonce
                var retryReq = request
                try await applyAuth(&retryReq, auth: updatedAuth)
                let (_, retryResponse) = try await session.data(for: retryReq)
                guard let retryHttp = retryResponse as? HTTPURLResponse else { return }
                if retryHttp.statusCode == 401 { throw XRPCError.unauthorized }
                guard (200 ... 299).contains(retryHttp.statusCode) else {
                    throw XRPCError.httpError(statusCode: retryHttp.statusCode, body: nil)
                }
                return
            }
            // Try token refresh
            if retryCount < 1, let onUnauthorized {
                do {
                    if let newAuth = try await onUnauthorized() {
                        logger.info("Token refreshed, retrying void request")
                        try await executeVoidWithRetry(request, auth: newAuth, retryCount: retryCount + 1)
                        return
                    }
                } catch {
                    logger.error("Token refresh failed: \(error)")
                }
            }
            throw XRPCError.unauthorized
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            logger.error("HTTP \(httpResponse.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
            throw XRPCError.httpError(statusCode: httpResponse.statusCode, body: data)
        }
    }

    private func execute<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw XRPCError.httpError(statusCode: 0, body: data)
        }

        // Check for DPoP nonce requirement
        if httpResponse.statusCode == 400,
           let nonce = httpResponse.value(forHTTPHeaderField: "DPoP-Nonce")
        {
            throw XRPCError.dpopNonceRequired(nonce: nonce)
        }

        if httpResponse.statusCode == 401 {
            let body = String(data: data, encoding: .utf8) ?? ""
            let nonce = httpResponse.value(forHTTPHeaderField: "DPoP-Nonce")
            let wwwAuth = httpResponse.value(forHTTPHeaderField: "WWW-Authenticate")
            logger.error("401: body=\(body), nonce=\(nonce ?? "nil"), wwwAuth=\(wwwAuth ?? "nil")")
            if let nonce {
                throw XRPCError.dpopNonceRequired(nonce: nonce)
            }
            throw XRPCError.unauthorized
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            logger.error("HTTP \(httpResponse.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
            throw XRPCError.httpError(statusCode: httpResponse.statusCode, body: data)
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw XRPCError.decodingError(error)
        }
    }

    private func applyAuth(_ request: inout URLRequest, auth: AuthContext?) async throws {
        guard let auth else { return }
        request.setValue("DPoP \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        let proof = try await auth.dpop.createProof(
            httpMethod: request.httpMethod ?? "GET",
            url: request.url!,
            accessToken: auth.accessToken,
            nonce: auth.nonce
        )
        request.setValue(proof, forHTTPHeaderField: "DPoP")
    }
}

/// Context for authenticated requests.
struct AuthContext: Sendable {
    let accessToken: String
    let dpop: DPoP
    var nonce: String?
}

struct UploadBlobResponse: Codable, Sendable {
    let blob: BlobRef
}

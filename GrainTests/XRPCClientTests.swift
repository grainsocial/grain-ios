@testable import Grain
import XCTest

private struct Echo: Codable, Equatable {
    let value: String
}

private struct Input: Encodable {
    let key: String
}

/// Every call in the app goes through this client, and most of its code is the
/// awkward middle: DPoP nonce handshakes, 401 refresh, and turning a response
/// into either a value or a typed error. Those paths only run against a real
/// PDS in production, so they're worth pinning here.
final class XRPCClientTests: XCTestCase {
    private let baseURL = URL(string: "https://test.local")!

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeClient(
        onUnauthorized: (@Sendable () async throws -> AuthContext?)? = nil
    ) -> XRPCClient {
        XRPCClient(baseURL: baseURL, session: MockURLProtocol.mockSession(), onUnauthorized: onUnauthorized)
    }

    private func respond(
        status: Int = 200,
        body: String = #"{"value": "ok"}"#,
        headers: [String: String]? = nil,
        record: (@Sendable (URLRequest) -> Void)? = nil
    ) {
        MockURLProtocol.handler = { request in
            record?(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers
            )!
            return (Data(body.utf8), response)
        }
    }

    // MARK: - Request construction

    func testAQueryHitsTheXrpcPathForItsNsid() async throws {
        let seen = Recorder()
        respond { seen.record($0) }

        _ = try await makeClient().query("social.grain.unspecced.getFeed", as: Echo.self)

        XCTAssertEqual(seen.url?.path, "/xrpc/social.grain.unspecced.getFeed")
        XCTAssertEqual(seen.method, "GET")
    }

    func testQueryParametersAreSentAsQueryItems() async throws {
        let seen = Recorder()
        respond { seen.record($0) }

        _ = try await makeClient().query(
            "social.grain.unspecced.getFeed",
            params: ["feed": "recent", "limit": "30"],
            as: Echo.self
        )

        let items = try URLComponents(url: XCTUnwrap(seen.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "feed" }?.value, "recent")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "30")
    }

    /// A search term arrives with spaces and accents in it, and has to survive
    /// the round trip into the URL.
    func testQueryParametersAreEscaped() async throws {
        let seen = Recorder()
        respond { seen.record($0) }

        _ = try await makeClient().query(
            "social.grain.unspecced.searchGalleries", params: ["q": "café film"], as: Echo.self
        )

        XCTAssertFalse(try XCTUnwrap(seen.url?.absoluteString.contains("café")), "The raw term should be percent-encoded")
        let items = try URLComponents(url: XCTUnwrap(seen.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "café film")
    }

    func testAProcedurePostsItsInputAsJSON() async throws {
        let seen = Recorder()
        respond { seen.record($0) }

        _ = try await makeClient().procedure(
            "dev.hatk.putPreference", input: Input(key: "includeExif"), as: Echo.self
        )

        XCTAssertEqual(seen.method, "POST")
        XCTAssertEqual(seen.headers?["Content-Type"], "application/json")
        XCTAssertEqual(seen.body.flatMap { String(data: $0, encoding: .utf8) }, #"{"key":"includeExif"}"#)
    }

    func testABlobUploadPostsRawBytesWithItsMimeType() async throws {
        let seen = Recorder()
        respond(body: #"{"blob": {"$type": "blob", "ref": {"$link": "bafyblob"}, "mimeType": "image/jpeg", "size": 3}}"#) {
            seen.record($0)
        }

        let response = try await makeClient().uploadBlob(data: Data([1, 2, 3]), mimeType: "image/jpeg")

        XCTAssertEqual(seen.url?.path, "/xrpc/dev.hatk.uploadBlob")
        XCTAssertEqual(seen.headers?["Content-Type"], "image/jpeg")
        XCTAssertEqual(seen.body, Data([1, 2, 3]))
        XCTAssertEqual(response.blob.ref?.link, "bafyblob")
    }

    // MARK: - Responses

    func testASuccessfulQueryDecodesItsBody() async throws {
        respond(body: #"{"value": "decoded"}"#)

        let result = try await makeClient().query("dev.hatk.thing", as: Echo.self)

        XCTAssertEqual(result, Echo(value: "decoded"))
    }

    /// A response the client can't decode has to be distinguishable from a
    /// transport failure, because only one of them is worth retrying.
    func testABodyThatDoesNotMatchTheTypeIsADecodingError() async {
        respond(body: #"{"unexpected": true}"#)

        do {
            _ = try await makeClient().query("dev.hatk.thing", as: Echo.self)
            XCTFail("Expected a decoding error")
        } catch XRPCError.decodingError {
            // expected
        } catch {
            XCTFail("Expected decodingError, got \(error)")
        }
    }

    func testAServerErrorCarriesItsStatusAndBody() async {
        respond(status: 503, body: #"{"error": "Unavailable"}"#)

        do {
            _ = try await makeClient().query("dev.hatk.thing", as: Echo.self)
            XCTFail("Expected an HTTP error")
        } catch let XRPCError.httpError(statusCode, body) {
            XCTAssertEqual(statusCode, 503)
            XCTAssertEqual(body.flatMap { String(data: $0, encoding: .utf8) }, #"{"error": "Unavailable"}"#)
        } catch {
            XCTFail("Expected httpError, got \(error)")
        }
    }

    /// A 401 with no nonce and nowhere to refresh from is a plain sign-out.
    func testAnUnauthorizedResponseWithNoRefreshHookIsUnauthorized() async {
        respond(status: 401)

        do {
            _ = try await makeClient().query("dev.hatk.thing", as: Echo.self)
            XCTFail("Expected unauthorized")
        } catch XRPCError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected unauthorized, got \(error)")
        }
    }

    // MARK: - Token refresh

    /// The refresh hook exists so a token expiring mid-scroll doesn't sign the
    /// user out — the request has to be replayed with the new token.
    func testAnUnauthorizedRequestIsReplayedAfterARefresh() async throws {
        let did = "did:plc:xrpc-\(UUID().uuidString)"
        let dpop = try DPoP.loadOrCreate(for: did)
        defer { try? DPoP.clearKey(for: did) }

        let attempts = Counter()
        MockURLProtocol.handler = { request in
            let first = attempts.next() == 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: first ? 401 : 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"value": "after refresh"}"#.utf8), response)
        }

        let refreshed = Counter()
        let client = XRPCClient(baseURL: baseURL, session: MockURLProtocol.mockSession()) { () -> AuthContext? in
            refreshed.next()
            return AuthContext(accessToken: "fresh-token", dpop: dpop, nonce: nil)
        }

        let result = try await client.query("dev.hatk.thing", as: Echo.self)

        XCTAssertEqual(result, Echo(value: "after refresh"))
        XCTAssertEqual(refreshed.count, 1)
        XCTAssertEqual(attempts.count, 2, "The original request should be sent again, not abandoned")
    }

    /// A refresh that itself fails must surface as unauthorized rather than the
    /// refresh's own error — the caller's job is to sign out, not to explain.
    func testAFailedRefreshStillEndsAsUnauthorized() async {
        respond(status: 401)
        let client = XRPCClient(baseURL: baseURL, session: MockURLProtocol.mockSession()) { () -> AuthContext? in
            throw XRPCError.unauthorized
        }

        do {
            _ = try await client.query("dev.hatk.thing", as: Echo.self)
            XCTFail("Expected unauthorized")
        } catch XRPCError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected unauthorized, got \(error)")
        }
    }

    /// A hook that declines to produce a new context (no stored refresh token)
    /// must not loop.
    func testARefreshThatYieldsNoContextDoesNotRetry() async {
        let attempts = Counter()
        MockURLProtocol.handler = { request in
            _ = attempts.next()
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        let client = XRPCClient(baseURL: baseURL, session: MockURLProtocol.mockSession()) { () -> AuthContext? in nil }

        do {
            _ = try await client.query("dev.hatk.thing", as: Echo.self)
            XCTFail("Expected unauthorized")
        } catch XRPCError.unauthorized {
            XCTAssertEqual(attempts.count, 1)
        } catch {
            XCTFail("Expected unauthorized, got \(error)")
        }
    }

    // MARK: - DPoP

    private func authContext(nonce: String? = nil) throws -> (AuthContext, String) {
        let did = "did:plc:xrpc-\(UUID().uuidString)"
        let dpop = try DPoP.loadOrCreate(for: did)
        return (AuthContext(accessToken: "token", dpop: dpop, nonce: nonce), did)
    }

    func testAnAuthenticatedRequestCarriesABearerTokenAndAProof() async throws {
        let (auth, did) = try authContext()
        defer { try? DPoP.clearKey(for: did) }
        let seen = Recorder()
        respond { seen.record($0) }

        _ = try await makeClient().query("dev.hatk.thing", auth: auth, as: Echo.self)

        XCTAssertEqual(seen.headers?["Authorization"], "DPoP token")
        XCTAssertFalse(seen.headers?["DPoP"]?.isEmpty ?? true, "Every authenticated request needs a fresh proof")
    }

    /// The PDS answers the first authenticated request with a nonce it wants
    /// echoed back. Not replaying it means nothing ever authenticates.
    func testANonceChallengeIsReplayedWithTheNonce() async throws {
        let (auth, did) = try authContext()
        defer { try? DPoP.clearKey(for: did) }

        let attempts = Counter()
        MockURLProtocol.handler = { request in
            if attempts.next() == 1 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 400, httpVersion: nil,
                    headerFields: ["DPoP-Nonce": "server-nonce"]
                )!
                return (Data(), response)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"value": "with nonce"}"#.utf8), response)
        }

        let result = try await makeClient().query("dev.hatk.thing", auth: auth, as: Echo.self)

        XCTAssertEqual(result, Echo(value: "with nonce"))
        XCTAssertEqual(attempts.count, 2)
    }

    /// A 401 that carries a nonce is a nonce challenge, not an expired token —
    /// treating it as expiry would sign the user out on every cold launch.
    func testA401CarryingANonceIsTreatedAsANonceChallenge() async throws {
        let (auth, did) = try authContext()
        defer { try? DPoP.clearKey(for: did) }

        let attempts = Counter()
        MockURLProtocol.handler = { request in
            if attempts.next() == 1 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 401, httpVersion: nil,
                    headerFields: ["DPoP-Nonce": "server-nonce"]
                )!
                return (Data(), response)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"value": "recovered"}"#.utf8), response)
        }

        let result = try await makeClient().query("dev.hatk.thing", auth: auth, as: Echo.self)

        XCTAssertEqual(result, Echo(value: "recovered"))
    }

    /// A 400 with no nonce header is an ordinary bad request, not a handshake.
    func testAPlainBadRequestIsNotANonceChallenge() async {
        respond(status: 400, body: #"{"error": "InvalidRequest"}"#)

        do {
            _ = try await makeClient().query("dev.hatk.thing", as: Echo.self)
            XCTFail("Expected an HTTP error")
        } catch let XRPCError.httpError(statusCode, _) {
            XCTAssertEqual(statusCode, 400)
        } catch {
            XCTFail("Expected httpError, got \(error)")
        }
    }

    // MARK: - Void procedures

    func testAVoidProcedureSucceedsOnA2xx() async throws {
        respond(status: 204, body: "")

        try await makeClient().procedure("dev.hatk.putPreference", input: Input(key: "k"))
    }

    func testAVoidProcedureThrowsOnAServerError() async {
        respond(status: 500, body: "")

        do {
            try await makeClient().procedure("dev.hatk.putPreference", input: Input(key: "k"))
            XCTFail("Expected an HTTP error")
        } catch let XRPCError.httpError(statusCode, _) {
            XCTAssertEqual(statusCode, 500)
        } catch {
            XCTFail("Expected httpError, got \(error)")
        }
    }

    func testAVoidProcedureReplaysANonceChallenge() async throws {
        let (auth, did) = try authContext()
        defer { try? DPoP.clearKey(for: did) }

        let attempts = Counter()
        MockURLProtocol.handler = { request in
            let status = attempts.next() == 1 ? 400 : 200
            let headers = status == 400 ? ["DPoP-Nonce": "server-nonce"] : nil
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers
            )!
            return (Data(), response)
        }

        try await makeClient().procedure("dev.hatk.putPreference", input: Input(key: "k"), auth: auth)

        XCTAssertEqual(attempts.count, 2)
    }

    func testAVoidProcedureIsReplayedAfterARefresh() async throws {
        let (auth, did) = try authContext()
        defer { try? DPoP.clearKey(for: did) }

        let attempts = Counter()
        MockURLProtocol.handler = { request in
            let status = attempts.next() == 1 ? 401 : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        let client = XRPCClient(baseURL: baseURL, session: MockURLProtocol.mockSession()) { () -> AuthContext? in auth }

        try await client.procedure("dev.hatk.putPreference", input: Input(key: "k"))

        XCTAssertEqual(attempts.count, 2)
    }

    func testAVoidProcedureThatStaysUnauthorizedThrows() async {
        respond(status: 401, body: "")

        do {
            try await makeClient().procedure("dev.hatk.putPreference", input: Input(key: "k"))
            XCTFail("Expected unauthorized")
        } catch XRPCError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected unauthorized, got \(error)")
        }
    }

    // MARK: - Error descriptions

    /// These reach the user in an alert, so an empty or debug-looking string is
    /// a bug.
    func testEveryErrorHasAReadableDescription() {
        let errors: [XRPCError] = [
            .invalidURL,
            .httpError(statusCode: 503, body: nil),
            .decodingError(URLError(.badServerResponse)),
            .unauthorized,
            .dpopNonceRequired(nonce: "n"),
            .authorizationDenied,
            .authorizationFailed(code: "access_denied", description: nil),
        ]

        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error) has no description")
        }

        XCTAssertEqual(XRPCError.httpError(statusCode: 503, body: nil).errorDescription, "HTTP error 503")
        XCTAssertEqual(XRPCError.authorizationDenied.errorDescription, "Sign-in canceled")
    }

    /// The PDS's own wording is better than ours when it bothers to send any.
    func testAServerSuppliedAuthorizationMessageWinsOverTheFallback() {
        XCTAssertEqual(
            XRPCError.authorizationFailed(code: "server_error", description: "Try again shortly.").errorDescription,
            "Try again shortly."
        )
        XCTAssertEqual(
            XRPCError.authorizationFailed(code: "server_error", description: nil).errorDescription,
            "Sign-in failed (server_error)"
        )
    }
}

// MARK: - Test doubles

/// `MockURLProtocol.handler` runs off the main actor, so anything a test wants
/// to observe from inside it has to be safe to touch from there.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    func record(_ request: URLRequest) {
        lock.withLock { self.request = request }
    }

    private var captured: URLRequest? {
        lock.withLock { request }
    }

    var url: URL? {
        captured?.url
    }

    var method: String? {
        captured?.httpMethod
    }

    var headers: [String: String]? {
        captured?.allHTTPHeaderFields
    }

    /// URLProtocol strips `httpBody` in favour of a stream, so read it back the
    /// way the loading system does.
    var body: Data? {
        guard let stream = captured?.httpBodyStream else { return captured?.httpBody }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    /// Returns the new count, so a handler can branch on which attempt it is.
    @discardableResult
    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }

    var count: Int {
        lock.withLock { value }
    }
}

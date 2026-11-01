@testable import Grain
import XCTest

private struct Echo: Codable, Equatable {
    let value: String
}

private struct Input: Encodable {
    let key: String
}

/// The shape of a signed-in call: it goes to the account's PDS, proves
/// possession of the token's key per request, carries the nonce each origin
/// asks for, and asks the PDS to proxy Grain's own methods to the AppView.
final class PDSCallTests: GrainTestCase {
    private let baseURL = URL(string: "https://test.local")!

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeClient() -> XRPCClient {
        XRPCClient(baseURL: baseURL, session: MockURLProtocol.mockSession())
    }

    private func respond(body: String = #"{"value": "ok"}"#, record: (@Sendable (URLRequest) -> Void)? = nil) {
        MockURLProtocol.handler = { request in
            record?(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    private func proofClaims(of proof: String?) throws -> [String: Any] {
        let parts = try XCTUnwrap(proof).split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload += "="
        }
        let data = try XCTUnwrap(Data(base64Encoded: payload))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A signed-in call goes to the account's PDS, not the AppView, and asks
    /// the PDS to proxy it to Grain's AppView.
    func testASignedInGrainCallGoesToThePDSThroughTheProxy() async throws {
        let dpop = DPoP(privateKey: .init())
        let pds = try XCTUnwrap(URL(string: "https://pds.example"))
        let auth = AuthContext(accessToken: "token", dpop: dpop, did: "did:plc:me", pds: pds)
        let seen = Recorder()
        respond { seen.record($0) }

        _ = try await makeClient().query("social.grain.feed.getFeed", params: ["feed": "recent"], auth: auth, as: Echo.self)

        XCTAssertEqual(seen.url?.host, "pds.example")
        XCTAssertEqual(seen.url?.path, "/xrpc/social.grain.feed.getFeed")
        XCTAssertEqual(seen.headers?["atproto-proxy"], "\(AuthManager.appviewDID)#grain_appview")
        XCTAssertEqual(seen.headers?["Authorization"], "DPoP token")
    }

    /// `com.atproto.*` is the PDS's own: no proxy.
    func testARepoCallIsNotProxied() async throws {
        let auth = try AuthContext(accessToken: "token", dpop: DPoP(privateKey: .init()), did: "did:plc:me", pds: XCTUnwrap(URL(string: "https://pds.example")))
        let seen = Recorder()
        respond(body: #"{"uri": "at://did:plc:me/social.grain.favorite/1", "cid": "c"}"#) { seen.record($0) }

        _ = try await makeClient().procedure("com.atproto.repo.createRecord", input: Input(key: "k"), auth: auth, as: CreateRecordResponse.self)

        XCTAssertEqual(seen.url?.host, "pds.example")
        XCTAssertNil(seen.headers?["atproto-proxy"])
    }

    /// Signed out, a call goes straight to the AppView with no credentials.
    func testASignedOutCallGoesToTheAppViewBare() async throws {
        let seen = Recorder()
        respond { seen.record($0) }

        _ = try await makeClient().query("social.grain.feed.getFeed", as: Echo.self)

        XCTAssertEqual(seen.url?.host, "test.local")
        XCTAssertNil(seen.headers?["Authorization"])
        XCTAssertNil(seen.headers?["DPoP"])
        XCTAssertNil(seen.headers?["atproto-proxy"])
    }

    /// The proof names the method, the URL without its query, and the token
    /// it is presented with.
    func testTheProofBindsMethodURLAndToken() async throws {
        let auth = try AuthContext(accessToken: "token", dpop: DPoP(privateKey: .init()), did: "did:plc:me", pds: XCTUnwrap(URL(string: "https://proof.example")))
        let seen = Recorder()
        respond { seen.record($0) }

        _ = try await makeClient().query("social.grain.feed.getFeed", params: ["limit": "3"], auth: auth, as: Echo.self)

        let claims = try proofClaims(of: seen.headers?["DPoP"])
        XCTAssertEqual(claims["htm"] as? String, "GET")
        XCTAssertEqual(claims["htu"] as? String, "https://proof.example/xrpc/social.grain.feed.getFeed")
        XCTAssertEqual(claims["ath"] as? String, OAuthClient.challenge(for: "token"))
    }

    /// The retry after a nonce refusal carries the nonce, and later calls to
    /// the same origin start with it.
    func testTheNonceIsSentAgainAndKeptForTheOrigin() async throws {
        let pds = try XCTUnwrap(URL(string: "https://nonce-\(UUID().uuidString.lowercased()).example"))
        let auth = AuthContext(accessToken: "token", dpop: DPoP(privateKey: .init()), did: "did:plc:me", pds: pds)
        let proofs = ProofLog()
        MockURLProtocol.handler = { request in
            let attempt = proofs.record(request.value(forHTTPHeaderField: "DPoP"))
            let refuse = attempt == 1
            let response = HTTPURLResponse(
                url: request.url!, statusCode: refuse ? 401 : 200, httpVersion: nil,
                headerFields: refuse
                    ? ["DPoP-Nonce": "fresh", "WWW-Authenticate": #"DPoP error="use_dpop_nonce""#]
                    : ["DPoP-Nonce": "fresh"]
            )!
            return (Data(#"{"value": "ok"}"#.utf8), response)
        }

        _ = try await makeClient().query("social.grain.feed.getFeed", auth: auth, as: Echo.self)
        _ = try await makeClient().query("social.grain.feed.getFeed", auth: auth, as: Echo.self)

        let all = proofs.all
        XCTAssertEqual(all.count, 3)
        XCTAssertNil(try proofClaims(of: all[0])["nonce"])
        XCTAssertEqual(try proofClaims(of: all[1])["nonce"] as? String, "fresh")
        XCTAssertEqual(try proofClaims(of: all[2])["nonce"] as? String, "fresh", "the second call starts with the kept nonce")
    }

    /// A PDS sends `DPoP-Nonce` on every answer, a 401 for an expired token
    /// included. That 401 is a refresh, not a nonce retry.
    func testAnExpiredTokenWithANonceHeaderRefreshes() async throws {
        let auth = try AuthContext(accessToken: "old", dpop: DPoP(privateKey: .init()), did: "did:plc:me", pds: XCTUnwrap(URL(string: "https://pds.example")))
        let attempts = Counter()
        MockURLProtocol.handler = { request in
            let first = attempts.next() == 1
            let response = HTTPURLResponse(
                url: request.url!, statusCode: first ? 401 : 200, httpVersion: nil,
                headerFields: first
                    ? ["DPoP-Nonce": "n", "WWW-Authenticate": #"DPoP error="invalid_token", error_description="exp""#]
                    : nil
            )!
            return (Data(#"{"value": "ok"}"#.utf8), response)
        }
        let refreshed = Counter()
        let client = XRPCClient(baseURL: baseURL, session: MockURLProtocol.mockSession()) { () -> AuthContext? in
            refreshed.next()
            return AuthContext(accessToken: "new", dpop: auth.dpop, did: auth.did, pds: auth.pds)
        }

        _ = try await client.query("social.grain.feed.getFeed", auth: auth, as: Echo.self)

        XCTAssertEqual(refreshed.count, 1)
        XCTAssertEqual(attempts.count, 2)
    }

    /// A 400 that merely carries a nonce header is an ordinary bad request.
    func testABadRequestCarryingANonceHeaderIsNotRetried() async throws {
        let auth = try AuthContext(accessToken: "t", dpop: DPoP(privateKey: .init()), did: "did:plc:me", pds: XCTUnwrap(URL(string: "https://pds.example")))
        let attempts = Counter()
        MockURLProtocol.handler = { request in
            attempts.next()
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: ["DPoP-Nonce": "n"])!
            return (Data(#"{"error": "InvalidRequest"}"#.utf8), response)
        }

        _ = try? await makeClient().query("social.grain.feed.getFeed", auth: auth, as: Echo.self)

        XCTAssertEqual(attempts.count, 1)
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    func record(_ request: URLRequest) {
        lock.withLock { self.request = request }
    }

    var url: URL? {
        lock.withLock { request?.url }
    }

    var headers: [String: String]? {
        lock.withLock { request?.allHTTPHeaderFields }
    }
}

private final class ProofLog: @unchecked Sendable {
    private let lock = NSLock()
    private var proofs: [String?] = []

    func record(_ proof: String?) -> Int {
        lock.withLock {
            proofs.append(proof)
            return proofs.count
        }
    }

    var all: [String?] {
        lock.withLock { proofs }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

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

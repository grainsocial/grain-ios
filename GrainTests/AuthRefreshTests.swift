@testable import Grain
import XCTest

/// Records the token requests a refresh puts on the wire.
private final class TokenLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    var count: Int {
        lock.withLock { requests.count }
    }

    var last: URLRequest? {
        lock.withLock { requests.last }
    }

    var lastForm: [String: String] {
        guard let request = last else { return [:] }
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                guard read > 0 else { break }
                collected.append(buffer, count: read)
            }
            data = collected
        }
        guard let data, let body = String(data: data, encoding: .utf8) else { return [:] }
        var form: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            form[String(parts[0])] = String(parts[1]).removingPercentEncoding ?? String(parts[1])
        }
        return form
    }
}

/// Renewing an expired token. This is the half of the OAuth code that runs on
/// every cold launch, and the half that decides whether a session survives — a
/// grant the PDS has revoked has to sign that account out, while a dropped
/// connection has to leave it alone to try again.
///
/// `URLSession.shared` is intercepted here, so no request leaves the machine.
@MainActor
final class AuthRefreshTests: XCTestCase {
    private var log: TokenLog!
    private var did = ""
    private var other = ""
    private var savedActiveDID: String?
    private var savedActiveAccountID: String?

    override func setUp() async throws {
        try await super.setUp()
        did = "did:plc:refresh-\(UUID().uuidString)"
        other = "did:plc:refresh-other-\(UUID().uuidString)"
        savedActiveDID = TokenStorage.activeDID
        savedActiveAccountID = AccountScopedStorage.activeAccountID
        log = TokenLog()
        MockURLProtocol.interceptSharedSession()
    }

    override func tearDown() async throws {
        MockURLProtocol.stopInterceptingSharedSession()
        MockURLProtocol.handler = nil
        for account in [did, other] {
            TokenStorage.removeAccount(account)
            try? DPoP.clearKey(for: account)
            AccountScopedStorage.purge(did: account)
        }
        TokenStorage.activeDID = savedActiveDID
        AccountScopedStorage.activeAccountID = savedActiveAccountID
        try await super.tearDown()
    }

    private func signIn(_ account: String, handle: String, expiresIn: TimeInterval = 3600) throws {
        _ = try DPoP.loadOrCreate(for: account)
        TokenStorage.storeTokens(
            did: account,
            accessToken: "\(handle)-access",
            refreshToken: "\(handle)-refresh",
            handle: handle,
            expiresAt: Date().addingTimeInterval(expiresIn),
            scope: AuthManager.requiredScopes.joined(separator: " ")
        )
        TokenStorage.upsertAccount(StoredAccount(did: account, handle: handle, avatar: nil))
    }

    private func respond(status: Int, body: String, headers: [String: String]? = nil) {
        let log = log!
        MockURLProtocol.handler = { request in
            log.record(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers
            )!
            return (Data(body.utf8), response)
        }
    }

    private static let renewed = """
    {
      "access_token": "renewed-access",
      "token_type": "DPoP",
      "expires_in": 3600,
      "refresh_token": "renewed-refresh",
      "sub": "did:plc:whoever"
    }
    """

    /// An `AuthManager` already holding `did` as its active session.
    private func signedInManager() -> AuthManager {
        TokenStorage.activeDID = did
        return AuthManager()
    }

    // MARK: - The happy path

    func testARefreshExchangesTheStoredRefreshToken() async throws {
        try signIn(did, handle: "tester.test")
        let auth = signedInManager()
        respond(status: 200, body: Self.renewed)

        try await auth.refresh()

        XCTAssertEqual(log.last?.url?.path, "/oauth/token")
        XCTAssertEqual(log.last?.httpMethod, "POST")
        XCTAssertEqual(log.lastForm["grant_type"], "refresh_token")
        XCTAssertEqual(log.lastForm["refresh_token"], "tester.test-refresh")
        XCTAssertEqual(log.lastForm["client_id"], AuthManager.clientID)
    }

    /// The token is bound to the account's DPoP key, so every request carries a
    /// proof or the PDS rejects it.
    func testARefreshCarriesADPoPProof() async throws {
        try signIn(did, handle: "tester.test")
        let auth = signedInManager()
        respond(status: 200, body: Self.renewed)

        try await auth.refresh()

        XCTAssertFalse(log.last?.value(forHTTPHeaderField: "DPoP")?.isEmpty ?? true)
    }

    func testARenewedTokenIsStored() async throws {
        try signIn(did, handle: "tester.test")
        let auth = signedInManager()
        respond(status: 200, body: Self.renewed)

        try await auth.refresh()

        XCTAssertEqual(TokenStorage.accessToken(for: did), "renewed-access")
        XCTAssertEqual(TokenStorage.refreshToken(for: did), "renewed-refresh")
        let expiry = try XCTUnwrap(TokenStorage.tokenExpiresAt(for: did))
        XCTAssertGreaterThan(expiry.timeIntervalSinceNow, 3000)
    }

    /// A refresh renews an existing grant, so it must not claim a scope the
    /// grant never had — that would hide the next scope migration.
    func testARefreshDoesNotInventAScope() async throws {
        try signIn(did, handle: "tester.test")
        let auth = signedInManager()
        respond(status: 200, body: Self.renewed)

        try await auth.refresh()

        XCTAssertEqual(
            TokenStorage.grantedScope(for: did),
            AuthManager.requiredScopes.joined(separator: " "),
            "The stored scope should be the one already on record, untouched"
        )
    }

    /// The PDS answers the first request with a nonce it wants echoed back.
    func testANonceChallengeIsRetriedWithTheNonce() async throws {
        try signIn(did, handle: "tester.test")
        let auth = signedInManager()

        let log = try XCTUnwrap(log)
        var attempt = 0
        MockURLProtocol.handler = { request in
            log.record(request)
            attempt += 1
            if attempt == 1 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 400, httpVersion: nil,
                    headerFields: ["DPoP-Nonce": "server-nonce"]
                )!
                return (Data(), response)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(Self.renewed.utf8), response)
        }

        try await auth.refresh()

        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(TokenStorage.accessToken(for: did), "renewed-access")
    }

    // MARK: - Terminal failures

    /// A revoked grant can't be recovered, so the account is dropped rather
    /// than left in the switcher unable to load anything.
    func testARevokedGrantSignsThatAccountOut() async throws {
        try signIn(did, handle: "tester.test")
        try signIn(other, handle: "other.test")
        let auth = signedInManager()
        respond(status: 400, body: #"{"error": "invalid_grant"}"#)

        do {
            try await auth.refresh()
            XCTFail("Expected the refresh to fail")
        } catch XRPCError.unauthorized {
            // expected
        }

        XCTAssertFalse(TokenStorage.hasCredentials(for: did))
        XCTAssertNotEqual(auth.userDID, did, "The dead account shouldn't still be on screen")
    }

    /// Losing the active account falls through to another signed-in one rather
    /// than dumping a multi-account user at the login screen.
    func testARevokedGrantFallsThroughToAnotherAccount() async throws {
        try signIn(did, handle: "tester.test")
        try signIn(other, handle: "other.test")
        let auth = signedInManager()
        respond(status: 400, body: #"{"error": "invalid_grant"}"#)

        try? await auth.refresh()

        XCTAssertTrue(TokenStorage.hasCredentials(for: other))
        XCTAssertNotEqual(auth.userDID, did)
    }

    /// Older server builds answered a dead grant with a 500 and a sentence, so
    /// the body is checked for the same meaning.
    func testALegacyServerMessageIsAlsoTreatedAsTerminal() async throws {
        try signIn(did, handle: "tester.test")
        let auth = signedInManager()
        respond(status: 500, body: "refresh token has been revoked")

        try? await auth.refresh()

        XCTAssertFalse(TokenStorage.hasCredentials(for: did))
    }

    /// Any 4xx means the grant is gone, whatever the body says.
    func testAnyClientErrorIsTerminal() async throws {
        try signIn(did, handle: "tester.test")
        let auth = signedInManager()
        respond(status: 401, body: "nope")

        try? await auth.refresh()

        XCTAssertFalse(TokenStorage.hasCredentials(for: did))
    }

    // MARK: - Recoverable failures

    /// A server having a bad day is not a revoked grant. Dropping the account
    /// here would sign people out over a blip.
    func testAServerErrorLeavesTheAccountSignedIn() async throws {
        try signIn(did, handle: "tester.test")
        let auth = signedInManager()
        respond(status: 503, body: "upstream unavailable")

        try? await auth.refresh()

        XCTAssertTrue(TokenStorage.hasCredentials(for: did), "A 5xx blip must not cost the session")
        XCTAssertEqual(TokenStorage.accessToken(for: did), "tester.test-access")
    }

    /// Offline is the same story: try again later.
    func testADroppedConnectionLeavesTheAccountSignedIn() async throws {
        try signIn(did, handle: "tester.test")
        let auth = signedInManager()
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        try? await auth.refresh()

        XCTAssertTrue(TokenStorage.hasCredentials(for: did))
    }

    // MARK: - Preconditions

    func testRefreshingWithNoSessionFails() async {
        let auth = AuthManager()
        auth.userDID = nil

        do {
            try await auth.refresh()
            XCTFail("Expected unauthorized")
        } catch XRPCError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected unauthorized, got \(error)")
        }
    }

    /// An account with no refresh token has nothing to exchange.
    func testRefreshingWithoutARefreshTokenFails() async throws {
        _ = try DPoP.loadOrCreate(for: did)
        TokenStorage.storeTokens(
            did: did, accessToken: "access", refreshToken: nil, handle: "tester.test",
            expiresAt: Date().addingTimeInterval(3600), scope: nil
        )
        TokenStorage.activeDID = did
        let auth = AuthManager()
        auth.userDID = did

        var requestMade = false
        MockURLProtocol.handler = { request in
            requestMade = true
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        try? await auth.refresh()

        XCTAssertFalse(requestMade)
    }

    // MARK: - refreshIfNeeded

    /// A token with hours left on it doesn't need renewing, and doing it anyway
    /// would put a token round trip on every launch.
    func testAHealthyTokenIsNotRefreshed() async throws {
        try signIn(did, handle: "tester.test", expiresIn: 3600)
        let auth = signedInManager()

        var requestMade = false
        MockURLProtocol.handler = { request in
            requestMade = true
            return (Data(Self.renewed.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        try await auth.refreshIfNeeded()

        XCTAssertFalse(requestMade)
    }

    func testATokenAboutToExpireIsRefreshed() async throws {
        try signIn(did, handle: "tester.test", expiresIn: 30)
        let auth = signedInManager()
        respond(status: 200, body: Self.renewed)

        try await auth.refreshIfNeeded()

        XCTAssertEqual(TokenStorage.accessToken(for: did), "renewed-access")
    }

    /// An already-expired token still gets one attempt — that's the cold launch
    /// after a day away.
    func testAnExpiredTokenIsRefreshed() async throws {
        try signIn(did, handle: "tester.test", expiresIn: -600)
        let auth = signedInManager()
        respond(status: 200, body: Self.renewed)

        try await auth.refreshIfNeeded()

        XCTAssertEqual(TokenStorage.accessToken(for: did), "renewed-access")
    }

    // MARK: - Concurrency

    /// Several screens hit a 401 at once on a cold launch. They have to join one
    /// refresh rather than each starting a rival exchange — the PDS rotates the
    /// refresh token, so a second exchange with the old one revokes the grant.
    func testConcurrentRefreshesShareOneExchange() async throws {
        try signIn(did, handle: "tester.test")
        let auth = signedInManager()
        respond(status: 200, body: Self.renewed)

        async let first: Void = auth.refresh()
        async let second: Void = auth.refresh()
        async let third: Void = auth.refresh()
        _ = try await (first, second, third)

        XCTAssertEqual(log.count, 1, "Each refresh started its own exchange, which would revoke the grant")
    }

    /// An auth context for an about-to-expire token renews it first, so the
    /// request it's built for doesn't immediately 401.
    func testBuildingAnAuthContextRenewsAnExpiringToken() async throws {
        try signIn(did, handle: "tester.test", expiresIn: 30)
        let auth = signedInManager()
        respond(status: 200, body: Self.renewed)

        let context = await auth.authContext()

        XCTAssertEqual(context?.accessToken, "renewed-access")
    }
}

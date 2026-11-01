@testable import Grain
import XCTest

/// A stand-in network: each URL (without its query) answers as set, and every
/// request is kept.
private final class Network: @unchecked Sendable {
    struct Answer {
        var status = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body = "{}"
    }

    private let lock = NSLock()
    private var routes: [String: [Answer]] = [:]
    private var seen: [URLRequest] = []

    /// Answer `url` with `answers` in turn, the last one from then on.
    func on(_ url: String, _ answers: Answer...) {
        lock.withLock { routes[url] = answers }
    }

    func on(_ url: String, json: String) {
        on(url, Answer(body: json))
    }

    func answer(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        components.query = nil
        let key = components.url!.absoluteString
        let answer: Answer? = lock.withLock {
            seen.append(request)
            guard var list = routes[key], !list.isEmpty else { return nil }
            let next = list.removeFirst()
            if list.isEmpty {
                list = [next]
            }
            routes[key] = list
            return next
        }
        guard let answer else { throw URLError(.cannotFindHost) }
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: answer.headers)!
        return (Data(answer.body.utf8), response)
    }

    func requests(to url: String) -> [URLRequest] {
        lock.withLock { seen.filter { $0.url?.absoluteString.hasPrefix(url) == true } }
    }

    var all: [URLRequest] {
        lock.withLock { seen }
    }

    static func form(_ request: URLRequest) -> [String: String] {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 4096)
                guard read > 0 else { break }
                collected.append(buffer, count: read)
            }
            data = collected
        }
        guard let data, let body = String(data: data, encoding: .utf8) else { return [:] }
        var form: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            form[parts[0].removingPercentEncoding ?? parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
        }
        return form
    }
}

/// Signing in at the account's own PDS: resolving who the user is, finding
/// where they sign in, the PAR/PKCE/DPoP exchange, and the checks that keep
/// one server from handing over another's account.
@MainActor
final class OAuthSignInTests: GrainTestCase {
    private var network: Network!
    private let did = "did:plc:alice"
    private let pds = "https://pds.alice.test"
    private let issuer = "https://auth.alice.test"

    override func setUp() async throws {
        try await super.setUp()
        network = Network()
        let network = network!
        MockURLProtocol.handler = { try network.answer($0) }
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        for account in TokenStorage.accounts {
            TokenStorage.removeAccount(account.did)
            try? DPoP.clearKey(for: account.did)
        }
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func didDocument(_ did: String, handle: String, pds: String) -> String {
        """
        {"id": "\(did)", "alsoKnownAs": ["at://\(handle)"],
         "service": [{"id": "#atproto_pds", "type": "AtprotoPersonalDataServer", "serviceEndpoint": "\(pds)"}]}
        """
    }

    private func serveAuthorizationServer(_ issuer: String, for pds: String, calls name: String? = nil) {
        network.on("\(pds)/.well-known/oauth-protected-resource", json: #"{"resource": "\#(pds)", "authorization_servers": ["\#(issuer)"]}"#)
        network.on("\(issuer)/.well-known/oauth-authorization-server", json: """
        {"issuer": "\(name ?? issuer)",
         "authorization_endpoint": "\(issuer)/oauth/authorize",
         "token_endpoint": "\(issuer)/oauth/token",
         "pushed_authorization_request_endpoint": "\(issuer)/oauth/par",
         "revocation_endpoint": "\(issuer)/oauth/revoke"}
        """)
    }

    /// alice.test: a handle on her own domain, a PLC DID, and a PDS whose
    /// authorization server lives at another origin.
    private func serveAlice() {
        network.on("https://alice.test/.well-known/atproto-did", Network.Answer(headers: [:], body: did))
        network.on("https://plc.directory/\(did)", json: didDocument(did, handle: "alice.test", pds: pds))
        serveAuthorizationServer(issuer, for: pds)
        network.on("\(issuer)/oauth/par", json: #"{"request_uri": "urn:ietf:params:oauth:request_uri:req-1", "expires_in": 60}"#)
        tokens(sub: did)
    }

    private func tokens(sub: String) {
        network.on("\(issuer)/oauth/token", json: """
        {"access_token": "access-1", "token_type": "DPoP", "expires_in": 3600,
         "refresh_token": "refresh-1", "sub": "\(sub)", "scope": "\(AuthManager.scope)"}
        """)
    }

    /// The user approving whatever was asked, the browser coming back with
    /// the request's own state unless `query` says otherwise.
    private func approve(_ auth: AuthManager, query: ((String) -> String)? = nil) {
        let network = network!
        let issuer = issuer
        auth.presentAuthorization = { url in
            let par = network.all.last { $0.url?.path.hasSuffix("/oauth/par") == true }
            let state = par.map(Network.form)?["state"] ?? ""
            let params = query?(state) ?? "code=the-code&state=\(state)&iss=\(issuer.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)"
            XCTAssertTrue(url.absoluteString.hasPrefix("\(issuer)/oauth/authorize?"))
            return URL(string: "\(AuthManager.redirectURI)?\(params)")!
        }
    }

    // MARK: - Identity

    func testAHandleResolvesThroughItsWellKnownFirst() async throws {
        serveAlice()

        let identity = try await IdentityResolver(session: MockURLProtocol.mockSession()).resolve("@Alice.test")

        XCTAssertEqual(identity, try ResolvedIdentity(did: did, handle: "alice.test", pds: XCTUnwrap(URL(string: pds))))
        XCTAssertTrue(network.requests(to: "https://public.api.bsky.app").isEmpty)
    }

    func testAHandleFallsBackToTheAppViewResolver() async throws {
        network.on("https://public.api.bsky.app/xrpc/com.atproto.identity.resolveHandle", json: #"{"did": "\#(did)"}"#)
        network.on("https://plc.directory/\(did)", json: didDocument(did, handle: "alice.test", pds: pds))

        let identity = try await IdentityResolver(session: MockURLProtocol.mockSession()).resolve("alice.test")

        XCTAssertEqual(identity.did, did)
        let asked = try XCTUnwrap(network.requests(to: "https://public.api.bsky.app").first?.url)
        XCTAssertEqual(URLComponents(url: asked, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "alice.test")
    }

    /// A DID typed directly takes its handle from the document, once that
    /// handle resolves back to it.
    func testADIDTakesTheHandleItsDocumentClaims() async throws {
        serveAlice()

        let identity = try await IdentityResolver(session: MockURLProtocol.mockSession()).resolve(did)

        XCTAssertEqual(identity.handle, "alice.test")
        XCTAssertEqual(identity.pds.absoluteString, pds)
    }

    func testAHandleThatDoesNotPointBackIsNotTaken() async throws {
        network.on("https://plc.directory/\(did)", json: didDocument(did, handle: "mallory.test", pds: pds))
        network.on("https://mallory.test/.well-known/atproto-did", Network.Answer(headers: [:], body: "did:plc:mallory"))

        let identity = try await IdentityResolver(session: MockURLProtocol.mockSession()).resolve(did)

        XCTAssertNil(identity.handle)
    }

    func testADidWebDocumentComesFromItsHost() async throws {
        network.on("https://web.example:8443/.well-known/did.json", json: didDocument("did:web:web.example%3A8443", handle: "web.example", pds: pds))

        let identity = try await IdentityResolver(session: MockURLProtocol.mockSession()).resolve("did:web:web.example%3A8443")

        XCTAssertEqual(identity.pds.absoluteString, pds)
    }

    func testAnUnknownHandleSaysSo() async {
        do {
            _ = try await IdentityResolver(session: MockURLProtocol.mockSession()).resolve("nobody.test")
            XCTFail("Expected handleNotFound")
        } catch {
            XCTAssertEqual(error as? OAuthError, .handleNotFound("nobody.test"))
        }
    }

    // MARK: - Discovery

    /// The metadata must name the issuer the PDS pointed at: else any server
    /// could claim to sign in for another.
    func testAnAuthorizationServerCallingItselfSomethingElseIsRefused() async throws {
        serveAuthorizationServer(issuer, for: pds, calls: "https://elsewhere.test")
        let client = OAuthClient(session: MockURLProtocol.mockSession(), clientID: AuthManager.clientID, redirectURI: AuthManager.redirectURI)

        do {
            _ = try await client.server(forPDS: XCTUnwrap(URL(string: pds)))
            XCTFail("Expected issuerMismatch")
        } catch {
            XCTAssertEqual(error as? OAuthError, .issuerMismatch(expected: issuer, found: "https://elsewhere.test"))
        }
    }

    // MARK: - Sign in

    func testTheRequestedScopeIsExactlyGrains() {
        XCTAssertEqual(
            AuthManager.scope,
            "atproto blob:image/* repo:social.grain.gallery repo:social.grain.gallery.item repo:social.grain.photo "
                + "repo:social.grain.photo.exif repo:social.grain.actor.profile repo:social.grain.graph.follow "
                + "repo:social.grain.favorite repo:social.grain.comment repo:social.grain.story repo:social.grain.graph.block "
                + "repo:app.bsky.feed.post?action=create&action=update rpc:*?aud=did:web:grain.social%23grain_appview"
        )
        XCTAssertEqual(AuthManager.clientID, "https://grain.social/oauth/app-client-metadata.json")
        XCTAssertEqual(AuthManager.appviewService, "did:web:grain.social#grain_appview")
    }

    func testSigningInPushesTheRequestToTheAccountsOwnServer() async throws {
        serveAlice()
        let auth = AuthManager()
        approve(auth)

        try await auth.login(handle: "alice.test")

        let par = try XCTUnwrap(network.requests(to: "\(issuer)/oauth/par").last)
        let form = Network.form(par)
        XCTAssertEqual(form["client_id"], AuthManager.clientID)
        XCTAssertEqual(form["redirect_uri"], "social.grain:/oauth/callback")
        XCTAssertEqual(form["response_type"], "code")
        XCTAssertEqual(form["code_challenge_method"], "S256")
        XCTAssertEqual(form["scope"], AuthManager.scope, "the scope survives form encoding intact")
        XCTAssertEqual(form["login_hint"], "alice.test")
        XCTAssertFalse(form["state"]?.isEmpty ?? true)
        XCTAssertNotNil(par.value(forHTTPHeaderField: "DPoP"))

        let token = try XCTUnwrap(network.requests(to: "\(issuer)/oauth/token").last)
        let tokenForm = Network.form(token)
        XCTAssertEqual(tokenForm["grant_type"], "authorization_code")
        XCTAssertEqual(tokenForm["code"], "the-code")
        XCTAssertEqual(tokenForm["client_id"], AuthManager.clientID)
        XCTAssertEqual(OAuthClient.challenge(for: tokenForm["code_verifier"] ?? ""), form["code_challenge"])
    }

    func testASignedInAccountKeepsWhereItSignedIn() async throws {
        serveAlice()
        let auth = AuthManager()
        approve(auth)

        try await auth.login(handle: "alice.test")

        XCTAssertEqual(auth.userDID, did)
        XCTAssertEqual(auth.userHandle, "alice.test")
        XCTAssertEqual(TokenStorage.server(for: did), try AccountServer(
            pds: XCTUnwrap(URL(string: pds)),
            issuer: issuer,
            tokenEndpoint: XCTUnwrap(URL(string: "\(issuer)/oauth/token")),
            revocationEndpoint: XCTUnwrap(URL(string: "\(issuer)/oauth/revoke"))
        ))
        XCTAssertEqual(TokenStorage.grantedScope(for: did), AuthManager.scope)
        let context = await auth.authContext()
        XCTAssertEqual(context?.pds.absoluteString, pds)
        XCTAssertEqual(context?.accessToken, "access-1")
    }

    /// An authorization server asks for a nonce on the first PAR; the request
    /// goes again with it.
    func testAParNonceRefusalIsSentAgainWithTheNonce() async throws {
        serveAlice()
        network.on(
            "\(issuer)/oauth/par",
            Network.Answer(status: 400, headers: ["DPoP-Nonce": "as-nonce"], body: #"{"error": "use_dpop_nonce"}"#),
            Network.Answer(body: #"{"request_uri": "urn:req", "expires_in": 60}"#)
        )
        let auth = AuthManager()
        approve(auth)

        try await auth.login(handle: "alice.test")

        XCTAssertEqual(network.requests(to: "\(issuer)/oauth/par").count, 2)
        XCTAssertEqual(try DPoPNonces.shared.nonce(for: XCTUnwrap(URL(string: issuer))), "as-nonce")
        XCTAssertEqual(auth.userDID, did)
    }

    func testABrowserReturnWithAnotherStateIsRefused() async {
        serveAlice()
        let auth = AuthManager()
        approve(auth) { _ in "code=the-code&state=forged" }

        do {
            try await auth.login(handle: "alice.test")
            XCTFail("Expected callbackMismatch")
        } catch {
            XCTAssertEqual(error as? OAuthError, .callbackMismatch)
        }
        XCTAssertTrue(network.requests(to: "\(issuer)/oauth/token").isEmpty)
        XCTAssertFalse(auth.isAuthenticated)
    }

    func testABrowserReturnFromAnotherIssuerIsRefused() async {
        serveAlice()
        let auth = AuthManager()
        approve(auth) { state in "code=c&state=\(state)&iss=https%3A%2F%2Felsewhere.test" }

        do {
            try await auth.login(handle: "alice.test")
            XCTFail("Expected callbackMismatch")
        } catch {
            XCTAssertEqual(error as? OAuthError, .callbackMismatch)
        }
    }

    func testDenyingIsTheDeniedError() async {
        serveAlice()
        let auth = AuthManager()
        approve(auth) { state in "error=access_denied&state=\(state)" }

        do {
            try await auth.login(handle: "alice.test")
            XCTFail("Expected authorizationDenied")
        } catch XRPCError.authorizationDenied {
            // expected
        } catch {
            XCTFail("Expected authorizationDenied, got \(error)")
        }
    }

    /// Tokens for someone other than the account asked for are not kept.
    func testTokensForAnotherAccountAreRefused() async {
        serveAlice()
        tokens(sub: "did:plc:mallory")
        let auth = AuthManager()
        approve(auth)

        do {
            try await auth.login(handle: "alice.test")
            XCTFail("Expected wrongAccount")
        } catch {
            XCTAssertEqual(error as? OAuthError, .wrongAccount(expected: did, found: "did:plc:mallory"))
        }
        XCTAssertNil(TokenStorage.accessToken(for: "did:plc:mallory"))
        XCTAssertFalse(auth.isAuthenticated)
    }

    // MARK: - Sign up

    /// The sign-up PDS here is its own authorization server.
    private func serveSignUp(newAccountPDS: String) {
        let signUp = AuthManager.signUpPDS.absoluteString
        serveAuthorizationServer(signUp, for: signUp)
        network.on("\(signUp)/oauth/par", json: #"{"request_uri": "urn:req", "expires_in": 60}"#)
        network.on("\(signUp)/oauth/token", json: """
        {"access_token": "a", "token_type": "DPoP", "expires_in": 3600, "refresh_token": "r", "sub": "did:plc:newbie"}
        """)
        network.on("https://plc.directory/did:plc:newbie", json: didDocument("did:plc:newbie", handle: "newbie.selfhosted.social", pds: newAccountPDS))
        network.on("https://newbie.selfhosted.social/.well-known/atproto-did", Network.Answer(headers: [:], body: "did:plc:newbie"))
    }

    private func approveSignUp(_ auth: AuthManager) {
        let network = network!
        auth.presentAuthorization = { _ in
            let par = network.all.last { $0.url?.path.hasSuffix("/oauth/par") == true }
            let state = par.map(Network.form)?["state"] ?? ""
            return URL(string: "\(AuthManager.redirectURI)?code=c&state=\(state)")!
        }
    }

    func testSigningUpAsksForTheCreatePromptAndTakesTheNewAccount() async throws {
        serveSignUp(newAccountPDS: AuthManager.signUpPDS.absoluteString)
        let auth = AuthManager()
        approveSignUp(auth)

        try await auth.login(createAccount: true)

        let form = try Network.form(XCTUnwrap(network.requests(to: "\(AuthManager.signUpPDS.absoluteString)/oauth/par").last))
        XCTAssertEqual(form["prompt"], "create")
        XCTAssertNil(form["login_hint"])
        XCTAssertEqual(auth.userDID, "did:plc:newbie")
        XCTAssertEqual(auth.userHandle, "newbie.selfhosted.social")
    }

    /// An account whose PDS signs in elsewhere was not made here.
    func testASignUpNamingAnAccountHostedElsewhereIsRefused() async {
        serveSignUp(newAccountPDS: pds)
        serveAuthorizationServer(issuer, for: pds)
        let auth = AuthManager()
        approveSignUp(auth)

        do {
            try await auth.login(createAccount: true)
            XCTFail("Expected accountElsewhere")
        } catch {
            XCTAssertEqual(error as? OAuthError, .accountElsewhere(did: "did:plc:newbie"))
        }
        XCTAssertFalse(auth.isAuthenticated)
    }

    // MARK: - Sign out

    private func storeAlice() throws {
        _ = try DPoP.loadOrCreate(for: did)
        TokenStorage.storeTokens(
            did: did, accessToken: "a", refreshToken: "alice-refresh", handle: "alice.test",
            expiresAt: Date().addingTimeInterval(3600), scope: AuthManager.scope
        )
        TokenStorage.storeServer(.test, for: did)
        TokenStorage.upsertAccount(StoredAccount(did: did, handle: "alice.test", avatar: nil))
        TokenStorage.activeDID = did
    }

    func testSigningOutRevokesTheRefreshToken() async throws {
        try storeAlice()
        try network.on(XCTUnwrap(AccountServer.test.revocationEndpoint?.absoluteString), json: "")
        let auth = AuthManager()

        await auth.logout()

        let revoke = try XCTUnwrap(try network.requests(to: XCTUnwrap(AccountServer.test.revocationEndpoint?.absoluteString)).first)
        XCTAssertEqual(Network.form(revoke)["token"], "alice-refresh")
        XCTAssertEqual(Network.form(revoke)["client_id"], AuthManager.clientID)
        XCTAssertNotNil(revoke.value(forHTTPHeaderField: "DPoP"))
        XCTAssertFalse(TokenStorage.hasCredentials(for: did))
        XCTAssertFalse(auth.isAuthenticated)
    }

    func testAFailedRevocationStillSignsOut() async throws {
        try storeAlice()
        try network.on(XCTUnwrap(AccountServer.test.revocationEndpoint?.absoluteString), Network.Answer(status: 503, body: ""))
        let auth = AuthManager()

        await auth.logout()

        XCTAssertFalse(TokenStorage.hasCredentials(for: did))
        XCTAssertFalse(auth.isAuthenticated)
    }

    // MARK: - Sessions from before

    /// A session with no PDS or authorization server on record can't make a
    /// signed-in call. It is dropped once at launch, with the reason shown.
    func testASessionWithoutItsServerIsDroppedOnceAtLaunch() throws {
        _ = try DPoP.loadOrCreate(for: did)
        TokenStorage.storeTokens(
            did: did, accessToken: "a", refreshToken: "r", handle: "alice.test",
            expiresAt: Date().addingTimeInterval(3600), scope: AuthManager.scope
        )
        TokenStorage.upsertAccount(StoredAccount(did: did, handle: "alice.test", avatar: nil))
        TokenStorage.activeDID = did

        let auth = AuthManager()

        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertEqual(auth.reauthReason, AuthManager.reauthMessage)
        XCTAssertTrue(auth.accounts.isEmpty)
        XCTAssertFalse(TokenStorage.hasCredentials(for: did))

        XCTAssertNil(AuthManager().reauthReason, "the migration runs once")
    }

    func testASessionWithItsServerSurvivesLaunch() throws {
        try storeAlice()

        let auth = AuthManager()

        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertEqual(auth.userDID, did)
        XCTAssertNil(auth.reauthReason)
    }

    /// When the active account is the stale one, another usable account takes
    /// over rather than the login screen.
    func testAStaleActiveAccountGivesWayToAUsableOne() throws {
        try storeAlice()
        let stale = "did:plc:stale"
        TokenStorage.storeTokens(
            did: stale, accessToken: "a", refreshToken: "r", handle: "stale.test",
            expiresAt: Date().addingTimeInterval(3600), scope: AuthManager.scope
        )
        TokenStorage.upsertAccount(StoredAccount(did: stale, handle: "stale.test", avatar: nil))
        TokenStorage.activeDID = stale

        let auth = AuthManager()

        XCTAssertEqual(auth.userDID, did)
        XCTAssertEqual(auth.accounts.map(\.did), [did])
    }
}

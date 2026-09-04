@testable import Grain
import XCTest

/// Records requests made through `URLSession.shared`.
private final class SharedSessionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    var count: Int {
        lock.withLock { requests.count }
    }

    var paths: [String] {
        lock.withLock { requests.compactMap(\.url?.path) }
    }

    var last: URLRequest? {
        lock.withLock { requests.last }
    }

    func queryValue(_ name: String) -> String? {
        guard let url = last?.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        return items.first { $0.name == name }?.value
    }

    var lastBody: [String: Any]? {
        guard let request = last else { return nil }
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
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// The calls the app makes outside its injected `XRPCClient` — the geocoder,
/// the Bluesky handle resolver, and push token registration. They reach for
/// `URLSession.shared` directly, so nothing else in the suite exercises them.
///
/// The shared session is intercepted here, so no request leaves the machine.
@MainActor
final class NetworkSideEffectTests: XCTestCase {
    private var log: SharedSessionLog!
    private var account: TestAccount!

    override func setUp() async throws {
        try await super.setUp()
        log = SharedSessionLog()
        account = TestAccount()
        MockURLProtocol.interceptSharedSession()
    }

    override func tearDown() async throws {
        MockURLProtocol.stopInterceptingSharedSession()
        MockURLProtocol.handler = nil
        account.restore()
        try await super.tearDown()
    }

    private func respond(_ body: String, status: Int = 200) {
        let log = log!
        MockURLProtocol.handler = { request in
            log.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    // MARK: - Reverse geocoding

    private static let nominatimPlace = """
    {
      "place_id": 1,
      "lat": "38.7223",
      "lon": "-9.1393",
      "name": "Miradouro de Santa Catarina",
      "display_name": "Miradouro de Santa Catarina, Lisboa, Portugal",
      "address": {"city": "Lisboa", "country": "Portugal", "country_code": "pt", "road": "Rua Marechal Saldanha"}
    }
    """

    /// A photo's GPS is turned into a place name before it goes on a gallery.
    func testReverseGeocodingAPhotoLocation() async {
        respond(Self.nominatimPlace)

        let result = await LocationServices.reverseGeocode(latitude: 38.7223, longitude: -9.1393)

        XCTAssertEqual(log.last?.url?.host, "nominatim.openstreetmap.org")
        XCTAssertEqual(log.last?.url?.path, "/reverse")
        XCTAssertEqual(log.queryValue("lat"), "38.7223")
        XCTAssertEqual(log.queryValue("lon"), "-9.1393")
        XCTAssertEqual(log.queryValue("format"), "json")
        XCTAssertEqual(result?.name, "Miradouro de Santa Catarina")
    }

    /// Nominatim asks for a User-Agent and blocks anonymous traffic.
    func testGeocodingIdentifiesTheApp() async {
        respond(Self.nominatimPlace)

        _ = await LocationServices.reverseGeocode(latitude: 0, longitude: 0)

        XCTAssertEqual(log.last?.value(forHTTPHeaderField: "User-Agent"), "grain-app/1.0")
    }

    /// The location row is optional chrome; a geocoder that's down or rate
    /// limiting must leave the post-in-progress alone.
    func testAFailedGeocodeReturnsNothing() async {
        respond("nope", status: 500)
        let failed = await LocationServices.reverseGeocode(latitude: 0, longitude: 0)
        XCTAssertNil(failed)

        respond("not json at all")
        let garbage = await LocationServices.reverseGeocode(latitude: 0, longitude: 0)
        XCTAssertNil(garbage)
    }

    // MARK: - Location search

    func testSearchingForALocation() async {
        respond("[\(Self.nominatimPlace)]")

        let results = await LocationServices.searchLocation(query: "Miradouro")

        XCTAssertEqual(log.last?.url?.path, "/search")
        XCTAssertEqual(log.queryValue("q"), "Miradouro")
        XCTAssertEqual(log.queryValue("limit"), "5")
        XCTAssertEqual(results.map(\.name), ["Miradouro de Santa Catarina"])
    }

    /// Typing is debounced into this, so a half-typed query would otherwise
    /// send a request per keystroke.
    func testATooShortQueryNeverLeavesTheDevice() async {
        respond("[]")

        let results = await LocationServices.searchLocation(query: " a ")

        XCTAssertEqual(log.count, 0)
        XCTAssertTrue(results.isEmpty)
    }

    func testAFailedSearchReturnsNothing() async {
        respond("nope", status: 503)

        let results = await LocationServices.searchLocation(query: "Lisboa")

        XCTAssertTrue(results.isEmpty)
    }

    /// A result the parser can't make sense of is dropped rather than shown as
    /// a blank row.
    func testUnparseableSearchResultsAreDropped() async {
        respond(#"[{"no_place_id": true}, \#(Self.nominatimPlace)]"#)

        let results = await LocationServices.searchLocation(query: "Lisboa")

        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Bluesky handle resolution

    /// A mention in a cross-post has to become a DID; Bluesky renders an
    /// unresolved one as plain text.
    func testAMentionIsResolvedToADID() async {
        respond(#"{"did": "did:plc:resolved"}"#)

        let facets = await BlueskyPost.parseTextToFacets("Thanks @alice.bsky.social!")

        XCTAssertEqual(log.last?.url?.host, "public.api.bsky.app")
        XCTAssertEqual(log.queryValue("handle"), "alice.bsky.social")
        guard case let .mention(did) = facets.first?.features.first else {
            return XCTFail("Expected a mention facet, got \(facets)")
        }
        XCTAssertEqual(did, "did:plc:resolved")
    }

    /// A handle that doesn't resolve is left as plain text rather than posted
    /// as a link to nobody.
    func testAnUnresolvableMentionIsLeftAsPlainText() async {
        respond("not found", status: 404)

        let facets = await BlueskyPost.parseTextToFacets("Thanks @nobody.bsky.social!")

        XCTAssertTrue(facets.isEmpty)
    }

    func testAResolverThatAnswersWithGarbageIsIgnored() async {
        respond("<html>rate limited</html>")

        let facets = await BlueskyPost.parseTextToFacets("Thanks @alice.bsky.social!")

        XCTAssertTrue(facets.isEmpty)
    }

    // MARK: - Push token registration

    /// APNs hands back a token as raw bytes; the server wants it hex-encoded.
    func testTheAPNsTokenIsSentToTheServerAsHex() async {
        respond("{}")
        let manager = PushManager()
        // Held in a local: `PushManager.authManager` is weak, so an inline
        // `AuthManager()` would be gone before the token task reads it.
        let auth = AuthManager()
        manager.configure(authManager: auth)

        manager.didRegisterForRemoteNotifications(deviceToken: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        await waitForRequest()

        XCTAssertEqual(log.paths.last, "/xrpc/dev.hatk.push.registerToken")
        XCTAssertEqual(log.lastBody?["token"] as? String, "deadbeef")
        XCTAssertEqual(log.lastBody?["platform"] as? String, "apns")
    }

    /// Signing out has to withdraw the token, or the device keeps getting the
    /// previous account's notifications.
    func testSigningOutUnregistersTheToken() async {
        respond("{}")
        let manager = PushManager()
        let auth = AuthManager()
        manager.configure(authManager: auth)
        manager.didRegisterForRemoteNotifications(deviceToken: Data([0x01, 0x02]))
        await waitForRequest()

        // Deliberately not `try XCTUnwrap(await …)`: swiftformat's hoistAwait
        // rule rewrites that into an autoclosure, which can't be async.
        guard let context = await auth.authContext() else {
            return XCTFail("The signed-in account should have an auth context")
        }
        await manager.unregisterToken(auth: context)

        XCTAssertEqual(log.paths.last, "/xrpc/dev.hatk.push.unregisterToken")
        XCTAssertEqual(log.lastBody?["token"] as? String, "0102")
    }

    /// A registration the server rejects is swallowed — there is nothing the
    /// user can do, and it must not take the launch down with it.
    func testAFailedRegistrationIsSwallowed() async {
        respond("nope", status: 500)
        let manager = PushManager()
        let auth = AuthManager()
        manager.configure(authManager: auth)

        manager.didRegisterForRemoteNotifications(deviceToken: Data([0x01]))
        await waitForRequest()

        XCTAssertEqual(log.paths.last, "/xrpc/dev.hatk.push.registerToken")
    }

    /// The manager only holds its `AuthManager` weakly, so a token arriving
    /// after the session has gone must be dropped rather than trapping.
    func testATokenArrivingAfterTheSessionIsGoneIsDropped() async {
        respond("{}")
        let manager = PushManager()
        manager.configure(authManager: AuthManager())

        manager.didRegisterForRemoteNotifications(deviceToken: Data([0x01]))
        await waitForRequest(expecting: 0)

        XCTAssertEqual(log.count, 0)
    }

    /// Without an account there is nobody to register the token for.
    func testATokenIsNotRegisteredWithoutASession() async {
        respond("{}")
        let manager = PushManager()
        let auth = AuthManager()
        auth.userDID = nil
        manager.configure(authManager: auth)

        manager.didRegisterForRemoteNotifications(deviceToken: Data([0x01]))
        await waitForRequest(expecting: 0)

        XCTAssertEqual(log.count, 0)
    }

    /// `didRegisterForRemoteNotifications` hands off to a detached task, so the
    /// request lands a beat after the call returns.
    private func waitForRequest(expecting minimum: Int = 1, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while log.count < minimum, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if minimum == 0 {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}

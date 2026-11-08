@testable import Grain
import XCTest

/// The cache is read during every card's body evaluation to decide whether a
/// gallery is blurred, so it has to resolve labels before anything loads,
/// fetch grain-serve's definitions once, and survive a failure.
@MainActor
final class LabelDefinitionsCacheTests: GrainTestCase {
    private var client: XRPCClient!

    override func setUp() async throws {
        try await super.setUp()
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try await super.tearDown()
    }

    /// `social.grain.moderation.describeLabels`, as grain-serve answers it.
    private static let described = """
    {"did": "did:web:grain.social", "policies": {
      "labelValues": ["!takedown", "spoiler", "nudity"],
      "labelValueDefinitions": [
        {"identifier": "spoiler", "severity": "inform", "blurs": "content", "defaultSetting": "warn",
         "locales": [{"lang": "en", "name": "Spoiler", "description": "Plot spoiler"}]},
        {"identifier": "nudity", "severity": "inform", "blurs": "media", "defaultSetting": "hide",
         "locales": [{"lang": "en", "name": "Nudity", "description": "Content containing nudity."}]}
      ]
    }}
    """

    func testItStartsOnTheCopyTheAppCarries() {
        let cache = LabelDefinitionsCache()

        XCTAssertEqual(
            cache.definitions.map(\.identifier),
            ["copyright", "csae", "gore", "harassment", "misleading", "nudity", "other", "sexual", "spam"]
        )
    }

    func testLoadingReadsGrainServesDefinitions() async {
        let seen = Paths()
        MockURLProtocol.handler = { request in
            seen.append(request.url?.path ?? "")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(Self.described.utf8), response)
        }
        let cache = LabelDefinitionsCache()

        await cache.loadIfNeeded(client: client, auth: nil)

        XCTAssertEqual(seen.all, ["/xrpc/social.grain.moderation.describeLabels"])
        XCTAssertEqual(cache.definitions.map(\.identifier), ["spoiler", "nudity"])
        XCTAssertEqual(cache.definitions.first?.displayName, "Spoiler")
    }

    /// What was read stands on the next launch, before anything loads.
    func testTheDefinitionsReadAreKeptForTheNextLaunch() async {
        MockURLProtocol.respondWithJSON(Self.described)
        await LabelDefinitionsCache().loadIfNeeded(client: client, auth: nil)

        XCTAssertEqual(LabelDefinitionsCache().definitions.map(\.identifier), ["spoiler", "nudity"])
    }

    /// Every screen with labels calls this, so it fetches once.
    func testItOnlyFetchesOnce() async {
        let seen = Paths()
        MockURLProtocol.handler = { request in
            seen.append(request.url?.path ?? "")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(Self.described.utf8), response)
        }
        let cache = LabelDefinitionsCache()

        await cache.loadIfNeeded(client: client, auth: nil)
        await cache.loadIfNeeded(client: client, auth: nil)

        XCTAssertEqual(seen.all.count, 1)
    }

    /// Offline, the copy the app carries stands, and the next call asks again.
    func testAFailedLoadKeepsTheCopyAndIsRetried() async {
        MockURLProtocol.respondWithError(statusCode: 500)
        let cache = LabelDefinitionsCache()
        await cache.loadIfNeeded(client: client, auth: nil)
        XCTAssertEqual(cache.definitions, LabelDefinition.all)

        MockURLProtocol.respondWithJSON(Self.described)
        await cache.loadIfNeeded(client: client, auth: nil)
        XCTAssertEqual(cache.definitions.map(\.identifier), ["spoiler", "nudity"])
    }

    /// A definition beats the built-in fallback for a value both know.
    func testADefinitionOverridesTheFallbackTable() {
        let cache = LabelDefinitionsCache(definitions: [
            LabelDefinition(identifier: "nudity", blurs: "content", defaultSetting: "warn"),
        ])

        let resolved = resolveLabels([ATLabel(src: nil, uri: nil, val: "nudity", cts: nil)], definitions: cache.definitions)
        XCTAssertEqual(resolved.action, .warnContent, "Fallback would have given warnMedia")
    }

    /// Every label has the reason a report for it names, the one grain-serve
    /// files under that label.
    func testEveryLabelHasAReportReason() {
        for definition in LabelDefinition.all {
            XCTAssertNotNil(LabelDefinition.reportReasons[definition.identifier], definition.identifier)
        }
        XCTAssertEqual(LabelDefinition.reasonType(for: "harassment"), "com.atproto.moderation.defs#reasonRude")
        XCTAssertEqual(LabelDefinition.reasonType(for: "unheard-of"), "com.atproto.moderation.defs#reasonOther")
    }
}

/// The paths the mock was asked for, from outside the main actor.
private final class Paths: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    func append(_ path: String) {
        lock.withLock { paths.append(path) }
    }

    var all: [String] {
        lock.withLock { paths }
    }
}

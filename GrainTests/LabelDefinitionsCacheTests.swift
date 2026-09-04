@testable import Grain
import XCTest

/// The cache is read during every card's body evaluation to decide whether a
/// gallery is blurred, so it has to fetch once and survive a failure without
/// leaving the app unable to resolve labels at all.
@MainActor
final class LabelDefinitionsCacheTests: GrainTestCase {
    private var client: XRPCClient!
    private var cache: LabelDefinitionsCache!

    override func setUp() async throws {
        try await super.setUp()
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        cache = LabelDefinitionsCache()
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try await super.tearDown()
    }

    private static let definitions = """
    {"definitions": [
      {
        "identifier": "spoiler",
        "blurs": "content",
        "defaultSetting": "warn",
        "locales": [{"lang": "en", "name": "Spoiler", "description": "Plot spoiler"}]
      },
      {"identifier": "nudity", "blurs": "media", "defaultSetting": "hide"}
    ]}
    """

    func testItStartsEmpty() {
        XCTAssertTrue(cache.definitions.isEmpty)
    }

    func testLoadingFillsTheDefinitions() async {
        MockURLProtocol.respondWithJSON(Self.definitions)

        await cache.loadIfNeeded(client: client, auth: nil)

        XCTAssertEqual(cache.definitions.map(\.identifier), ["spoiler", "nudity"])
        XCTAssertEqual(cache.definitions.first?.id, "spoiler", "Definitions are identified by their label value")
    }

    /// The display name comes from the locale list, falling back to the raw
    /// label value so an unlocalised definition still reads as something.
    func testTheDisplayNameFallsBackToTheIdentifier() async {
        MockURLProtocol.respondWithJSON(Self.definitions)

        await cache.loadIfNeeded(client: client, auth: nil)

        XCTAssertEqual(cache.definitions.first?.displayName, "Spoiler")
        XCTAssertEqual(cache.definitions.last?.displayName, "nudity")
    }

    /// Every screen with labels calls this from `.task`, so it has to be
    /// idempotent rather than re-fetching per appearance.
    func testItOnlyFetchesOnce() async {
        var requests = 0
        MockURLProtocol.handler = { request in
            requests += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"definitions": [{"identifier": "spoiler"}]}"#.utf8), response)
        }

        await cache.loadIfNeeded(client: client, auth: nil)
        await cache.loadIfNeeded(client: client, auth: nil)
        await cache.loadIfNeeded(client: client, auth: nil)

        XCTAssertEqual(requests, 1)
    }

    /// A failure leaves the cache empty on purpose — `resolveLabels` still has
    /// its built-in fallbacks for the well-known values.
    func testAFailedLoadLeavesTheCacheEmpty() async {
        MockURLProtocol.respondWithError(statusCode: 500)

        await cache.loadIfNeeded(client: client, auth: nil)

        XCTAssertTrue(cache.definitions.isEmpty)
        XCTAssertEqual(
            resolveLabels([ATLabel(src: nil, uri: nil, val: "nudity", cts: nil)], definitions: cache.definitions).action,
            .warnMedia,
            "The fallback table should still cover well-known labels with no server definitions"
        )
    }

    /// The retry matters: a definitions fetch that failed on a cold launch has
    /// to be allowed to succeed later.
    func testAFailedLoadIsRetriedOnTheNextCall() async {
        MockURLProtocol.respondWithError(statusCode: 500)
        await cache.loadIfNeeded(client: client, auth: nil)

        MockURLProtocol.respondWithJSON(Self.definitions)
        await cache.loadIfNeeded(client: client, auth: nil)

        XCTAssertEqual(cache.definitions.map(\.identifier), ["spoiler", "nudity"])
    }

    /// A server definition has to beat the built-in fallback, which is the
    /// entire reason the cache exists.
    func testAServerDefinitionOverridesTheFallbackTable() async {
        MockURLProtocol.respondWithJSON(#"""
        {"definitions": [{"identifier": "nudity", "blurs": "content", "defaultSetting": "warn"}]}
        """#)

        await cache.loadIfNeeded(client: client, auth: nil)

        let resolved = resolveLabels(
            [ATLabel(src: nil, uri: nil, val: "nudity", cts: nil)],
            definitions: cache.definitions
        )
        XCTAssertEqual(resolved.action, .warnContent, "Fallback would have given warnMedia")
    }

    /// The lexicon makes `definitions` optional, so an empty response is not a
    /// decode failure.
    func testAResponseWithNoDefinitionsKeyIsTreatedAsEmpty() async {
        MockURLProtocol.respondWithJSON("{}")

        await cache.loadIfNeeded(client: client, auth: nil)

        XCTAssertTrue(cache.definitions.isEmpty)
    }
}

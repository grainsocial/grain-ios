@testable import Grain
import XCTest

/// The force-update gate: whether a build is blocked, from what the server says
/// and, when the server can't be reached or makes no sense, from what it last
/// said. Getting it wrong either strands a supported build or lets an
/// unsupported one through to errors.
@MainActor
final class AppUpdateGateTests: GrainTestCase {
    private let server = URL(string: "https://grain.test")!

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        try await super.tearDown()
    }

    private func document(minimumBuild: Int, storeUrl: String = "https://apps.apple.com/app/id1") -> String {
        """
        {
          "ios": { "minimumBuild": \(minimumBuild), "storeUrl": "\(storeUrl)" },
          "android": { "minimumVersionCode": 0, "storeUrl": "https://play.google.com/store/apps/details?id=social.grain" }
        }
        """
    }

    private func makeGate(build: Int?) -> AppUpdateGate {
        AppUpdateGate(currentBuild: build, serverURL: server, session: MockURLProtocol.mockSession())
    }

    private func failRequests() {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
    }

    // MARK: - Build against minimum

    func testABuildBelowTheMinimumIsBlocked() {
        XCTAssertTrue(AppVersionPolicy(minimumBuild: 60).blocks(build: 59))
    }

    func testABuildAtOrAboveTheMinimumIsNot() {
        XCTAssertFalse(AppVersionPolicy(minimumBuild: 59).blocks(build: 59))
        XCTAssertFalse(AppVersionPolicy(minimumBuild: 59).blocks(build: 60))
    }

    func testAnUnreadableBuildNumberIsNeverBlocked() {
        XCTAssertFalse(AppVersionPolicy(minimumBuild: 60).blocks(build: nil))
    }

    // MARK: - Parsing

    func testParsesTheIOSMinimumAndStoreURL() throws {
        let policy = try XCTUnwrap(AppVersionPolicy.parse(Data(document(minimumBuild: 61).utf8)))
        XCTAssertEqual(policy.minimumBuild, 61)
        XCTAssertEqual(policy.storeURL, URL(string: "https://apps.apple.com/app/id1"))
    }

    func testAMissingIOSKeyMeansNoMinimum() throws {
        let json = #"{ "android": { "minimumVersionCode": 99 } }"#
        let policy = try XCTUnwrap(AppVersionPolicy.parse(Data(json.utf8)))
        XCTAssertNil(policy.minimumBuild)
        XCTAssertFalse(policy.blocks(build: 1))
    }

    func testAMissingMinimumBuildMeansNoMinimum() throws {
        let json = #"{ "ios": { "storeUrl": "https://apps.apple.com/app/id1" } }"#
        let policy = try XCTUnwrap(AppVersionPolicy.parse(Data(json.utf8)))
        XCTAssertNil(policy.minimumBuild)
        XCTAssertFalse(policy.blocks(build: 1))
    }

    func testAMissingStoreURLFallsBackToTheAppStoreListing() throws {
        let json = #"{ "ios": { "minimumBuild": 60 } }"#
        let policy = try XCTUnwrap(AppVersionPolicy.parse(Data(json.utf8)))
        XCTAssertEqual(policy.storeURL, URL(string: "https://apps.apple.com/app/id6747730230"))
    }

    func testMalformedDocumentsAreRejected() {
        for body in ["", "not json", "[]", #"{ "ios": "60" }"#, #"{ "ios": { "minimumBuild": "60" } }"#] {
            XCTAssertNil(AppVersionPolicy.parse(Data(body.utf8)), "Should reject \(body.debugDescription)")
        }
    }

    // MARK: - Fetching and the cache

    func testNothingCachedAndNoFetchMeansNotBlocked() {
        XCTAssertFalse(makeGate(build: 59).isUpdateRequired)
    }

    func testAFetchedMinimumAboveTheBuildBlocksIt() async {
        MockURLProtocol.respondWithJSON(document(minimumBuild: 60, storeUrl: "https://apps.apple.com/app/id2"))
        let gate = makeGate(build: 59)

        await gate.check()

        XCTAssertTrue(gate.isUpdateRequired)
        XCTAssertEqual(gate.storeURL, URL(string: "https://apps.apple.com/app/id2"))
    }

    func testAFailedFetchWithNothingCachedDoesNotBlock() async {
        failRequests()
        let gate = makeGate(build: 59)

        await gate.check()

        XCTAssertFalse(gate.isUpdateRequired)
    }

    func testAMalformedResponseWithNothingCachedDoesNotBlock() async {
        MockURLProtocol.respondWithJSON("<html>oops</html>")
        let gate = makeGate(build: 59)

        await gate.check()

        XCTAssertFalse(gate.isUpdateRequired)
    }

    func testAnErrorStatusWithNothingCachedDoesNotBlock() async {
        MockURLProtocol.respondWithError(statusCode: 503)
        let gate = makeGate(build: 59)

        await gate.check()

        XCTAssertFalse(gate.isUpdateRequired)
    }

    /// The case the cache exists for: a blocked build opened offline.
    func testTheCachedMinimumBlocksAtLaunchBeforeAnyFetch() async {
        MockURLProtocol.respondWithJSON(document(minimumBuild: 60, storeUrl: "https://apps.apple.com/app/id3"))
        await makeGate(build: 59).check()

        let relaunched = makeGate(build: 59)

        XCTAssertTrue(relaunched.isUpdateRequired)
        XCTAssertEqual(relaunched.storeURL, URL(string: "https://apps.apple.com/app/id3"))
    }

    func testTheCachedMinimumStillBlocksWhenTheFetchFails() async {
        MockURLProtocol.respondWithJSON(document(minimumBuild: 60))
        await makeGate(build: 59).check()

        failRequests()
        let relaunched = makeGate(build: 59)
        await relaunched.check()

        XCTAssertTrue(relaunched.isUpdateRequired)
    }

    func testTheCachedMinimumStillBlocksWhenTheResponseIsMalformed() async {
        MockURLProtocol.respondWithJSON(document(minimumBuild: 60))
        await makeGate(build: 59).check()

        MockURLProtocol.respondWithJSON("{")
        let relaunched = makeGate(build: 59)
        await relaunched.check()

        XCTAssertTrue(relaunched.isUpdateRequired)
    }

    /// Lowering or removing the minimum has to reach a build that was blocked,
    /// or it stays locked out on the strength of an old answer.
    func testAFetchedLowerMinimumUnblocksAndReplacesTheCache() async {
        MockURLProtocol.respondWithJSON(document(minimumBuild: 60))
        await makeGate(build: 59).check()

        MockURLProtocol.respondWithJSON(#"{ "ios": {} }"#)
        let relaunched = makeGate(build: 59)
        XCTAssertTrue(relaunched.isUpdateRequired)
        await relaunched.check()
        XCTAssertFalse(relaunched.isUpdateRequired)

        XCTAssertFalse(makeGate(build: 59).isUpdateRequired, "The cleared minimum should be what is remembered")
    }

    func testRequestsAppVersionJSONOnTheConfiguredServerWithAShortTimeout() async throws {
        var seen: URLRequest?
        MockURLProtocol.handler = { request in
            seen = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{}"#.utf8), response)
        }

        await makeGate(build: 59).check()

        let request = try XCTUnwrap(seen)
        XCTAssertEqual(request.url, URL(string: "https://grain.test/app-version.json"))
        XCTAssertLessThanOrEqual(request.timeoutInterval, AppUpdateGate.timeout)
    }
}

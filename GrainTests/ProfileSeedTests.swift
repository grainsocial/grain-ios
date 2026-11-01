import CryptoKit
@testable import Grain
import XCTest

/// The grain profile the app makes from the account's Bluesky profile once
/// it signs in, as grain-serve makes one for the web.
final class ProfileSeedTests: GrainTestCase {
    private var log: SeedLog!

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private static let avatar = #"{"$type": "blob", "ref": {"$link": "bafk"}, "mimeType": "image/png", "size": 9}"#
    private static let notFound = #"{"error": "RecordNotFound", "message": "Could not locate record"}"#

    private let auth = AuthContext(
        accessToken: "token",
        dpop: DPoP(privateKey: P256.Signing.PrivateKey()),
        did: "did:plc:seed",
        pds: URL(string: "https://pds.test")!
    )

    /// Serve `grain` and `bluesky` as the account's profiles, nil for none,
    /// and answer each write.
    private func makeClient(grain: String?, bluesky: String?, writeStatus: Int = 200) -> XRPCClient {
        let log = SeedLog()
        self.log = log
        MockURLProtocol.handler = { request in
            log.record(request)
            let path = request.url?.path ?? ""
            let collection = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "collection" }?.value
            var status = 200
            var body = "{}"
            if path.hasSuffix("getRecord") {
                let found = collection == ProfileSeed.grain ? grain : bluesky
                if let found {
                    body = #"{"uri": "at://did:plc:seed/\#(collection ?? "")/self", "cid": "bafyold", "value": \#(found)}"#
                } else {
                    (status, body) = (400, Self.notFound)
                }
            } else if path.hasSuffix("createRecord") || path.hasSuffix("putRecord") {
                status = writeStatus
                body = #"{"uri": "at://did:plc:seed/social.grain.actor.profile/self", "cid": "bafynew"}"#
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
        return XRPCClient(baseURL: URL(string: "https://grain.test")!, session: MockURLProtocol.mockSession())
    }

    func testANamedGrainProfileIsLeftAsItIs() async throws {
        let client = makeClient(grain: #"{"displayName": "Already"}"#, bluesky: #"{"displayName": "Alice"}"#)

        let outcome = try await ProfileSeed.seed(client: client, auth: auth)

        XCTAssertEqual(outcome, .named)
        XCTAssertNil(log.write)
    }

    func testWithNoBlueskyProfileNothingIsWritten() async throws {
        let client = makeClient(grain: nil, bluesky: nil)

        let outcome = try await ProfileSeed.seed(client: client, auth: auth)

        XCTAssertEqual(outcome, .noBluesky)
        XCTAssertNil(log.write)
    }

    /// No grain profile: one is made at `self`, from the Bluesky one, the
    /// avatar's blob as it names it, then indexed through the proxy.
    func testWithNoGrainProfileOneIsMadeAtSelf() async throws {
        let client = makeClient(grain: nil, bluesky: #"{"displayName": "Alice", "description": "Photos", "avatar": \#(Self.avatar), "banner": \#(Self.avatar)}"#)

        let outcome = try await ProfileSeed.seed(client: client, auth: auth)

        XCTAssertEqual(outcome, .made)
        let write = try XCTUnwrap(log.write)
        XCTAssertTrue(write.path.hasSuffix("com.atproto.repo.createRecord"))
        XCTAssertEqual(write.body["rkey"] as? String, "self")
        XCTAssertEqual(write.body["collection"] as? String, "social.grain.actor.profile")
        let record = try XCTUnwrap(write.body["record"] as? [String: Any])
        XCTAssertEqual(record["$type"] as? String, "social.grain.actor.profile")
        XCTAssertEqual(record["displayName"] as? String, "Alice")
        XCTAssertEqual(record["description"] as? String, "Photos")
        XCTAssertEqual((record["avatar"] as? [String: Any])?["ref"] as? [String: String], ["$link": "bafk"])
        XCTAssertNil(record["banner"])
        XCTAssertNotNil(DateFormatting.parse(record["createdAt"] as? String ?? ""))
        XCTAssertEqual(log.indexProxy, "\(AuthManager.appviewDID)#grain_appview")
    }

    /// A grain profile with no name is put over, swapped on the CID read,
    /// keeping when it says it was made.
    func testAnUnnamedGrainProfileIsPutOverOnItsCID() async throws {
        let client = makeClient(
            grain: #"{"createdAt": "2025-01-01T00:00:00.000Z", "description": "old"}"#,
            bluesky: #"{"displayName": "Alice", "description": ""}"#
        )

        let outcome = try await ProfileSeed.seed(client: client, auth: auth)

        XCTAssertEqual(outcome, .put)
        let write = try XCTUnwrap(log.write)
        XCTAssertTrue(write.path.hasSuffix("com.atproto.repo.putRecord"))
        XCTAssertEqual(write.body["swapRecord"] as? String, "bafyold")
        XCTAssertEqual(write.body["rkey"] as? String, "self")
        let record = try XCTUnwrap(write.body["record"] as? [String: Any])
        XCTAssertEqual(record["createdAt"] as? String, "2025-01-01T00:00:00.000Z")
        XCTAssertEqual(record["displayName"] as? String, "Alice")
        XCTAssertNil(record["description"], "an empty description is left out")
        XCTAssertNotNil(log.indexProxy)
    }

    /// The background run swallows a failure, so a sign-in never fails by it.
    func testAFailedWriteNeverEscapesTheRun() async {
        let client = makeClient(grain: nil, bluesky: #"{"displayName": "Alice"}"#, writeStatus: 500)

        await ProfileSeed.run(client: client, auth: auth)

        XCTAssertNotNil(log.write)
    }

    func testOnlyRecordNotFoundCountsAsNoRecord() {
        XCTAssertTrue(ProfileSeed.isNotFound(Data(Self.notFound.utf8)))
        XCTAssertFalse(ProfileSeed.isNotFound(Data(#"{"error": "InternalServerError"}"#.utf8)))
        XCTAssertFalse(ProfileSeed.isNotFound(nil))
    }
}

/// The requests the mock saw, from outside the main actor.
private final class SeedLog: @unchecked Sendable {
    struct Write {
        let path: String
        let body: [String: Any]
    }

    private let lock = NSLock()
    private var writes: [Write] = []
    private var proxies: [String?] = []

    func record(_ request: URLRequest) {
        let path = request.url?.path ?? ""
        lock.withLock {
            if path.hasSuffix("createRecord") || path.hasSuffix("putRecord") {
                writes.append(Write(path: path, body: Self.json(request) ?? [:]))
            } else if path.hasSuffix("indexRecords") {
                proxies.append(request.value(forHTTPHeaderField: "atproto-proxy"))
            }
        }
    }

    var write: Write? {
        lock.withLock { writes.last }
    }

    var indexProxy: String? {
        lock.withLock { proxies.last ?? nil }
    }

    private static func json(_ request: URLRequest) -> [String: Any]? {
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
        return data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

import CryptoKit
@testable import Grain
import XCTest

/// Pins what a gallery delete removes from the account's repo.
///
/// Deleting the `social.grain.gallery` record on its own leaves the photos,
/// gallery items, exif records, and comments behind. The bug is invisible
/// from the client (the record does disappear), so it's worth asserting
/// every record that goes with the gallery is deleted with it.
final class GalleryServiceTests: GrainTestCase {
    private var recorder: Recorder!

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private static let gallery = "at://did:plc:test/social.grain.gallery/g1"

    /// What the account's repo holds, by collection, as `listRecords` pages.
    private static let repo: [String: String] = [
        "social.grain.gallery.item": #"""
        {"records": [
          {"uri": "at://did:plc:test/social.grain.gallery.item/i1", "value": {"gallery": "at://did:plc:test/social.grain.gallery/g1", "item": "at://did:plc:test/social.grain.photo/p1"}},
          {"uri": "at://did:plc:test/social.grain.gallery.item/i2", "value": {"gallery": "at://did:plc:test/social.grain.gallery/g1", "item": "at://did:plc:test/social.grain.photo/p2"}},
          {"uri": "at://did:plc:test/social.grain.gallery.item/i3", "value": {"gallery": "at://did:plc:test/social.grain.gallery/other", "item": "at://did:plc:test/social.grain.photo/p2"}}
        ]}
        """#,
        "social.grain.photo.exif": #"""
        {"records": [
          {"uri": "at://did:plc:test/social.grain.photo.exif/e1", "value": {"photo": "at://did:plc:test/social.grain.photo/p1"}},
          {"uri": "at://did:plc:test/social.grain.photo.exif/e2", "value": {"photo": "at://did:plc:test/social.grain.photo/p2"}}
        ]}
        """#,
        "social.grain.favorite": #"""
        {"records": [
          {"uri": "at://did:plc:test/social.grain.favorite/f1", "value": {"subject": "at://did:plc:test/social.grain.gallery/g1"}},
          {"uri": "at://did:plc:test/social.grain.favorite/f2", "value": {"subject": "at://did:plc:else/social.grain.gallery/x"}}
        ]}
        """#,
        "social.grain.comment": #"""
        {"records": [
          {"uri": "at://did:plc:test/social.grain.comment/c1", "value": {"subject": "at://did:plc:test/social.grain.gallery/g1", "text": "hi"}}
        ]}
        """#,
    ]

    private func makeClient(status: Int = 200) -> XRPCClient {
        let recorder = Recorder()
        self.recorder = recorder
        MockURLProtocol.handler = { request in
            recorder.record(path: request.url!.path, body: Self.body(of: request))
            let collection = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "collection" }?.value
            let body = request.url!.path.hasSuffix("listRecords")
                ? Self.repo[collection ?? ""] ?? #"{"records": []}"#
                : "{}"
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Data(body.utf8), response)
        }
        return XRPCClient(baseURL: URL(string: "https://example.test")!, session: MockURLProtocol.mockSession())
    }

    private func makeAuth() -> AuthContext {
        AuthContext(accessToken: "test-token", dpop: DPoP(privateKey: P256.Signing.PrivateKey()), did: "did:plc:test", pds: URL(string: "https://test.local")!)
    }

    /// The deletes the one commit carried, as `collection/rkey`.
    private func deleted() throws -> [String] {
        let index = try XCTUnwrap(recorder.paths.firstIndex { $0.hasSuffix("com.atproto.repo.applyWrites") })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: recorder.bodies[recorder.bodyIndex(ofPath: index)]) as? [String: Any])
        let writes = try XCTUnwrap(json["writes"] as? [[String: Any]])
        XCTAssertTrue(writes.allSatisfy { $0["$type"] as? String == "com.atproto.repo.applyWrites#delete" })
        return writes.map { "\($0["collection"] as? String ?? "")/\($0["rkey"] as? String ?? "")" }
    }

    // MARK: - Tests

    /// The exif of the photos it alone places, its items, those photos, the
    /// account's favorites and comments on it, then the gallery: children
    /// first, in one commit.
    func testDeleteRemovesTheGalleryAndWhatGoesWithItInOneCommit() async throws {
        let client = makeClient()

        try await GalleryService.delete(galleryUri: Self.gallery, client: client, auth: makeAuth())

        XCTAssertEqual(try deleted(), [
            "social.grain.photo.exif/e1",
            "social.grain.gallery.item/i1",
            "social.grain.gallery.item/i2",
            "social.grain.photo/p1",
            "social.grain.favorite/f1",
            "social.grain.comment/c1",
            "social.grain.gallery/g1",
        ])
        XCTAssertFalse(
            recorder.paths.contains { $0.hasSuffix("com.atproto.repo.deleteRecord") },
            "deleteRecord orphans the gallery's photos, items, exif, and comments"
        )
    }

    /// A photo another gallery also places stays, with its exif.
    func testAPhotoAnotherGalleryPlacesIsKept() async throws {
        let client = makeClient()

        try await GalleryService.delete(galleryUri: Self.gallery, client: client, auth: makeAuth())

        let going = try deleted()
        XCTAssertFalse(going.contains("social.grain.photo/p2"))
        XCTAssertFalse(going.contains("social.grain.photo.exif/e2"))
    }

    /// The deletes are then indexed, so the gallery leaves the feeds at once.
    func testTheDeletesAreIndexed() async throws {
        let client = makeClient()

        try await GalleryService.delete(galleryUri: Self.gallery, client: client, auth: makeAuth())

        XCTAssertTrue(recorder.paths.last?.hasSuffix("social.grain.sync.indexRecords") ?? false)
    }

    /// Callers use `try?` and drop the error, so the failure has to at least
    /// reach them rather than being swallowed inside the service.
    func testDeletePropagatesAServerFailure() async {
        let client = makeClient(status: 500)

        do {
            try await GalleryService.delete(galleryUri: Self.gallery, client: client, auth: makeAuth())
            XCTFail("expected the failure to propagate")
        } catch {
            // expected
        }
    }
}

/// Records what the mock server was asked for. The handler runs off the main
/// actor, so it needs its own lock.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPaths: [String] = []
    private var storedBodies: [Data] = []
    private var bodyIndices: [Int?] = []

    func record(path: String, body: Data?) {
        lock.lock()
        defer { lock.unlock() }
        storedPaths.append(path)
        if let body {
            bodyIndices.append(storedBodies.count)
            storedBodies.append(body)
        } else {
            bodyIndices.append(nil)
        }
    }

    /// Where in `bodies` the body of the request at `index` is.
    func bodyIndex(ofPath index: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return bodyIndices[index] ?? 0
    }

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedPaths
    }

    var bodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return storedBodies
    }
}

private extension GalleryServiceTests {
    /// `URLProtocol` moves the body into a stream before the handler sees it.
    static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}

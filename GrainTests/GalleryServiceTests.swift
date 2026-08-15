import CryptoKit
@testable import Grain
import XCTest

/// Pins the endpoint a gallery delete goes to.
///
/// Deleting the `social.grain.gallery` record on its own leaves the photos,
/// gallery items, exif records, and comments behind — which is what shipped
/// from six of the seven delete actions until 2026-08-14. The bug is invisible
/// from the client (the record does disappear), so it's worth asserting the
/// request lands on the endpoint that walks the whole graph.
final class GalleryServiceTests: XCTestCase {
    private var recorder: Recorder!

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeClient(status: Int = 200) -> XRPCClient {
        let recorder = Recorder()
        self.recorder = recorder
        MockURLProtocol.handler = { request in
            recorder.record(path: request.url!.path, body: Self.body(of: request))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Data("{}".utf8), response)
        }
        return XRPCClient(baseURL: URL(string: "https://example.test")!, session: MockURLProtocol.mockSession())
    }

    private func makeAuth() -> AuthContext {
        AuthContext(accessToken: "test-token", dpop: DPoP(privateKey: P256.Signing.PrivateKey()))
    }

    // MARK: - Tests

    func testDeleteCallsTheCascadingEndpointNotAPlainRecordDelete() async throws {
        let client = makeClient()

        try await GalleryService.delete(
            galleryUri: "at://did:plc:test/social.grain.gallery/3jzfcijpj2z2a",
            client: client,
            auth: makeAuth()
        )

        XCTAssertEqual(recorder.paths.count, 1)
        XCTAssertTrue(
            recorder.paths[0].hasSuffix("social.grain.unspecced.deleteGallery"),
            "expected the cascading endpoint, got \(recorder.paths[0])"
        )
        XCTAssertFalse(
            recorder.paths.contains { $0.hasSuffix("dev.hatk.deleteRecord") },
            "deleteRecord orphans the gallery's photos, items, exif, and comments"
        )
    }

    func testDeleteSendsTheRecordKeyFromTheUri() async throws {
        let client = makeClient()

        try await GalleryService.delete(
            galleryUri: "at://did:plc:test/social.grain.gallery/3jzfcijpj2z2a",
            client: client,
            auth: makeAuth()
        )

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: recorder.bodies[0]) as? [String: Any])
        XCTAssertEqual(json["rkey"] as? String, "3jzfcijpj2z2a")
    }

    /// Callers use `try?` and drop the error, so the failure has to at least
    /// reach them rather than being swallowed inside the service.
    func testDeletePropagatesAServerFailure() async {
        let client = makeClient(status: 500)

        do {
            try await GalleryService.delete(
                galleryUri: "at://did:plc:test/social.grain.gallery/3jzfcijpj2z2a",
                client: client,
                auth: makeAuth()
            )
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

    func record(path: String, body: Data?) {
        lock.lock()
        defer { lock.unlock() }
        storedPaths.append(path)
        if let body {
            storedBodies.append(body)
        }
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

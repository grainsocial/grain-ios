import Foundation

/// A URLProtocol subclass that intercepts all requests and returns preconfigured responses.
/// Use `MockURLProtocol.handler` to set up a response before each test.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    // MARK: - Convenience

    /// Create a URLSession configured to use mock responses.
    static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Set handler to return JSON data with 200 status for any request.
    static func respondWithJSON(_ json: String) {
        handler = { request in
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response)
        }
    }

    /// Set handler to return an error status code.
    static func respondWithError(statusCode: Int) {
        handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
    }
}

extension MockURLProtocol {
    /// Serve a different body per endpoint.
    ///
    /// Rendering a screen usually fans out across several endpoints at once,
    /// and a single canned body means every call but one fails to decode — so
    /// the screen settles on its error branch rather than the loaded one this
    /// is meant to exercise. Keys are matched as substrings of the request
    /// path, so `"getFeed"` matches `/xrpc/dev.hatk.getFeed`.
    ///
    /// Longest key first, so `getStoryAuthors` isn't answered by the route for
    /// `getStory` — dictionary order would otherwise decide it at random.
    static func respondByPath(_ routes: [String: String], fallback: String = "{}") {
        let ordered = routes.sorted { $0.key.count > $1.key.count }
        handler = { request in
            let path = request.url?.path ?? ""
            let body = ordered.first { path.contains($0.key) }?.value ?? fallback
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Data(body.utf8), response)
        }
    }
}

extension MockURLProtocol {
    /// Also intercept `URLSession.shared`.
    ///
    /// A few paths don't take an injected client — the avatar refresh after an
    /// account switch, Nominatim lookups, the Bluesky handle resolver — and
    /// without this they reach the real network from a test.
    static func interceptSharedSession() {
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    static func stopInterceptingSharedSession() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
    }
}

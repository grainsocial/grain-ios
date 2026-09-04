@testable import Grain
import SwiftUI
import XCTest

/// The navigation these cover used to be unreachable from a test.
///
/// Each destination lived in a `navigationDestination(item:)` closure that only
/// runs once SwiftUI presents it, so the only way in was a tap. As a value plus
/// a `Route -> View` function, both halves can be exercised directly.
@MainActor
final class RoutingTests: GrainTestCase {
    // MARK: - Router

    func testPushingAppendsToThePath() {
        let router = Router()
        router.push(.profile(did: "did:plc:a"))
        router.push(.hashtag("portra"))
        XCTAssertEqual(router.path, [.profile(did: "did:plc:a"), .hashtag("portra")])
    }

    func testPoppingRemovesOnlyTheTop() {
        let router = Router(path: [.profile(did: "did:plc:a"), .hashtag("portra")])
        router.pop()
        XCTAssertEqual(router.path, [.profile(did: "did:plc:a")])
    }

    func testPoppingAnEmptyPathIsANoOp() {
        let router = Router()
        router.pop()
        XCTAssertTrue(router.path.isEmpty)
    }

    func testPopToRootClearsEverything() {
        let router = Router(path: [.profile(did: "did:plc:a"), .gallery(uri: "at://g")])
        router.popToRoot()
        XCTAssertTrue(router.path.isEmpty)
    }

    /// A second deep link arriving while the first is on screen. This is the
    /// case that needed a pop plus a 0.35s wait when each destination had its
    /// own optional, because `navigationDestination(item:)` won't re-push when
    /// its value goes straight from one non-nil to another.
    func testReplacingSwapsTheStackInOneStep() {
        let router = Router(path: [.gallery(uri: "at://first")])
        router.replace(with: [.gallery(uri: "at://second")])
        XCTAssertEqual(router.path, [.gallery(uri: "at://second")])
    }

    // MARK: - Routes as values

    /// Routes carry identifiers only, so they survive being written down. That's
    /// what makes state restoration and logging possible later.
    func testEveryRouteRoundTripsThroughJSON() throws {
        let routes: [Route] = [
            .gallery(uri: "at://did:plc:a/social.grain.gallery/1"),
            .profile(did: "did:plc:a"),
            .hashtag("portra"),
            .location(h3Index: "8a2a1072b59ffff", name: "Lisbon"),
            .galleryFavorites(uri: "at://did:plc:a/social.grain.gallery/1"),
        ]
        let data = try JSONEncoder().encode(routes)
        XCTAssertEqual(try JSONDecoder().decode([Route].self, from: data), routes)
    }

    func testRoutesDistinguishTheirPayloads() {
        XCTAssertNotEqual(Route.profile(did: "did:plc:a"), .profile(did: "did:plc:b"))
        XCTAssertNotEqual(Route.gallery(uri: "at://g"), .galleryFavorites(uri: "at://g"))
    }

    // MARK: - Deep links and taps agree

    func testAProfileLinkBecomesAProfileRoute() throws {
        let link = try XCTUnwrap(try DeepLink.from(url: XCTUnwrap(URL(string: "grain://profile/did:plc:a"))))
        XCTAssertEqual(link.route, .profile(did: "did:plc:a"))
    }

    func testAGalleryLinkBecomesTheSameUriTheCardPushes() throws {
        let link = try XCTUnwrap(try DeepLink.from(url: XCTUnwrap(URL(string: "grain://profile/did:plc:a/gallery/xyz"))))
        XCTAssertEqual(link.route, .gallery(uri: "at://did:plc:a/social.grain.gallery/xyz"))
        // The card builds its route from the gallery's own uri; both must agree
        // or the same destination would push two different stack entries.
        XCTAssertEqual(link.route, .gallery(uri: link.galleryUri ?? ""))
    }

    /// Stories present over the stack rather than joining it, so they have no route.
    func testAStoryLinkHasNoRoute() throws {
        let link = try XCTUnwrap(try DeepLink.from(url: XCTUnwrap(URL(string: "grain://profile/did:plc:a/story/xyz"))))
        XCTAssertNil(link.route)
    }

    // MARK: - Route -> View

    /// Each of these bodies previously required a tap to reach.
    func testEveryRouteBuildsItsDestination() {
        let env = TestEnvironment()
        MockURLProtocol.respondByPath(Fixtures.routes, fallback: Fixtures.galleryResponse)
        defer { MockURLProtocol.handler = nil }

        for route in [
            Route.gallery(uri: "at://did:plc:test/social.grain.gallery/1"),
            .profile(did: "did:plc:test"),
            .hashtag("portra"),
            .location(h3Index: "8a2a1072b59ffff", name: "Lisbon"),
            .galleryFavorites(uri: "at://did:plc:test/social.grain.gallery/1"),
        ] {
            ViewRender.render(
                NavigationStack {
                    RouteDestination(route: route, client: env.client)
                }
                .withTestEnvironment(env),
                settle: 0.2
            )
        }
    }
}

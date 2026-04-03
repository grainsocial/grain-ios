import XCTest
@testable import Grain

final class FeedEndpointModelTests: XCTestCase {

    // MARK: - PinnedFeed.feedName

    func testFeedNameForCameraType() {
        let feed = PinnedFeed(id: "camera:Sony A7III", label: "Sony A7III", type: "camera", path: "/feeds/camera")
        XCTAssertEqual(feed.feedName, "camera")
    }

    func testFeedNameForLocationType() {
        let feed = PinnedFeed(id: "location:tokyo", label: "Tokyo", type: "location", path: "/feeds/location")
        XCTAssertEqual(feed.feedName, "location")
    }

    func testFeedNameForHashtagType() {
        let feed = PinnedFeed(id: "hashtag:streetphoto", label: "#streetphoto", type: "hashtag", path: "/feeds/hashtag")
        XCTAssertEqual(feed.feedName, "hashtag")
    }

    func testFeedNameDefaultsToId() {
        let feed = PinnedFeed(id: "following", label: "Following", type: "feed", path: "/feeds/following")
        XCTAssertEqual(feed.feedName, "following")
    }

    // MARK: - PinnedFeed.feedValue

    func testFeedValueExtractsAfterColon() {
        let feed = PinnedFeed(id: "camera:Sony A7III", label: "Sony A7III", type: "camera", path: "/")
        XCTAssertEqual(feed.feedValue, "Sony A7III")
    }

    func testFeedValueNilWithoutColon() {
        let feed = PinnedFeed(id: "recent", label: "Recent", type: "feed", path: "/")
        XCTAssertNil(feed.feedValue)
    }

    func testFeedValueHandlesMultipleColons() {
        let feed = PinnedFeed(id: "tag:key:value", label: "Test", type: "tag", path: "/")
        XCTAssertEqual(feed.feedValue, "key:value")
    }

    // MARK: - PinnedFeed.defaults

    func testDefaultsContainsTwoFeeds() {
        XCTAssertEqual(PinnedFeed.defaults.count, 2)
        XCTAssertEqual(PinnedFeed.defaults[0].id, "recent")
        XCTAssertEqual(PinnedFeed.defaults[1].id, "following")
    }
}

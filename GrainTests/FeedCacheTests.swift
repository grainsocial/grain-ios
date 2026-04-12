@testable import Grain
import XCTest

@MainActor
final class FeedCacheTests: XCTestCase {
    private func makeGallery(uri: String, cid: String = "bafytest") -> GrainGallery {
        GrainGallery(
            uri: uri,
            cid: cid,
            creator: GrainProfile(cid: "bafyprofile", did: "did:plc:test", handle: "tester.test"),
            indexedAt: "2026-04-11T00:00:00Z"
        )
    }

    override func tearDown() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("grain_feed_cache", isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
        super.tearDown()
    }

    func testRoundTripPersistsAndLoadsGalleries() {
        let key = "test_round_trip"
        let input = [
            makeGallery(uri: "at://a", cid: "cid-a"),
            makeGallery(uri: "at://b", cid: "cid-b"),
        ]
        FeedCache.shared.save(input, key: key)
        let loaded = FeedCache.shared.load(key: key)
        XCTAssertEqual(loaded.map(\.uri), ["at://a", "at://b"])
        XCTAssertEqual(loaded.map(\.cid), ["cid-a", "cid-b"])
    }

    func testLoadReturnsEmptyForMissingKey() {
        XCTAssertEqual(FeedCache.shared.load(key: "test_missing_key").count, 0)
    }

    func testSaveIgnoresEmptyArrayAndPreservesPriorData() {
        let key = "test_empty_save"
        let seed = [makeGallery(uri: "at://seed")]
        FeedCache.shared.save(seed, key: key)

        FeedCache.shared.save([], key: key)

        let loaded = FeedCache.shared.load(key: key)
        XCTAssertEqual(loaded.map(\.uri), ["at://seed"])
    }

    func testKeyWithSlashesColonsAndSpacesRoundTrips() {
        let key = "feed/home:pinned 1"
        let input = [makeGallery(uri: "at://tricky")]
        FeedCache.shared.save(input, key: key)
        XCTAssertEqual(FeedCache.shared.load(key: key).map(\.uri), ["at://tricky"])
    }
}

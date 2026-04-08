@testable import Grain
import Nuke
import XCTest

final class StoryImageCacheTests: XCTestCase {
    // MARK: - Helpers

    private func makeStory(fullsize: String) -> GrainStory {
        GrainStory(
            uri: "at://did:plc:test/social.grain.story/\(UUID().uuidString)",
            cid: "bafy-test",
            creator: GrainProfile(cid: "cid", did: "did:plc:test", handle: "test.bsky.social"),
            thumb: "https://cdn.example.com/thumb.jpg",
            fullsize: fullsize,
            aspectRatio: AspectRatio(width: 4, height: 3),
            createdAt: "2024-01-01T00:00:00Z"
        )
    }

    /// Builds an `ImagePipeline` backed entirely by an in-memory cache so tests
    /// never touch the network or the disk, and never pollute `ImagePipeline.shared`.
    private func makeIsolatedPipeline() -> ImagePipeline {
        var config = ImagePipeline.Configuration()
        config.dataLoader = DataLoader(configuration: {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.protocolClasses = []
            return cfg
        }())
        config.imageCache = ImageCache()
        config.dataCache = nil
        return ImagePipeline(configuration: config)
    }

    private func seedCache(pipeline: ImagePipeline, url: URL) {
        let image = UIImage(systemName: "photo") ?? UIImage()
        let container = ImageContainer(image: image)
        pipeline.cache.storeCachedImage(container, for: ImageRequest(url: url))
    }

    // MARK: - nil story

    func testNilStory_returnsFalse() {
        let pipeline = makeIsolatedPipeline()
        XCTAssertFalse(storyFullsizeCached(nil, in: pipeline))
    }

    // MARK: - invalid / empty fullsize URL

    func testEmptyFullsizeURL_returnsFalse() {
        let pipeline = makeIsolatedPipeline()
        let story = makeStory(fullsize: "")
        XCTAssertFalse(storyFullsizeCached(story, in: pipeline))
    }

    func testInvalidFullsizeURL_returnsFalse() {
        let pipeline = makeIsolatedPipeline()
        let story = makeStory(fullsize: "not a url !!!")
        XCTAssertFalse(storyFullsizeCached(story, in: pipeline))
    }

    // MARK: - valid URL, not cached

    func testValidURL_notInCache_returnsFalse() {
        let pipeline = makeIsolatedPipeline()
        let story = makeStory(fullsize: "https://cdn.example.com/stories/abc.jpg")
        XCTAssertFalse(storyFullsizeCached(story, in: pipeline))
    }

    // MARK: - valid URL, cached

    func testValidURL_inCache_returnsTrue() throws {
        let pipeline = makeIsolatedPipeline()
        let urlString = "https://cdn.example.com/stories/xyz.jpg"
        let story = makeStory(fullsize: urlString)
        try seedCache(pipeline: pipeline, url: XCTUnwrap(URL(string: urlString)))
        XCTAssertTrue(storyFullsizeCached(story, in: pipeline))
    }

    func testValidURL_cachedInDifferentPipeline_doesNotAffectIsolatedPipeline() throws {
        let pipeline1 = makeIsolatedPipeline()
        let pipeline2 = makeIsolatedPipeline()
        let urlString = "https://cdn.example.com/stories/shared.jpg"
        let story = makeStory(fullsize: urlString)
        try seedCache(pipeline: pipeline1, url: XCTUnwrap(URL(string: urlString)))
        // pipeline2 should not see pipeline1's cache
        XCTAssertFalse(storyFullsizeCached(story, in: pipeline2))
    }
}

@testable import Grain
import Nuke
import XCTest

final class ImagePrefetchPlanningTests: XCTestCase {
    // MARK: - Helpers

    private func photo(index: Int) -> (thumb: String, fullsize: String) {
        (thumb: "https://cdn.example.com/thumb/\(index).jpg", fullsize: "https://cdn.example.com/full/\(index).jpg")
    }

    private func photos(_ count: Int) -> [(thumb: String, fullsize: String)] {
        (0 ..< count).map { photo(index: $0) }
    }

    private func urls(from requests: [ImageRequest]) -> [String] {
        requests.compactMap { $0.url?.absoluteString }
    }

    // MARK: - Carousel: Empty / Edge Cases

    func testCarousel_emptyPhotos_returnsEmpty() {
        let result = ImagePrefetchPlanning.carouselPrefetchRequests(photos: [], currentPage: 0)
        XCTAssertTrue(result.all.isEmpty)
    }

    func testCarousel_outOfBoundsPage_returnsEmpty() {
        let result = ImagePrefetchPlanning.carouselPrefetchRequests(photos: photos(3), currentPage: 10)
        XCTAssertTrue(result.all.isEmpty)
    }

    func testCarousel_negativePage_returnsEmpty() {
        let result = ImagePrefetchPlanning.carouselPrefetchRequests(photos: photos(3), currentPage: -1)
        XCTAssertTrue(result.all.isEmpty)
    }

    // MARK: - Carousel: Page 0

    func testCarousel_singlePhoto_page0_prefetchesOnlyThatFullsize() {
        let result = ImagePrefetchPlanning.carouselPrefetchRequests(photos: photos(1), currentPage: 0)
        XCTAssertEqual(urls(from: result.high), ["https://cdn.example.com/full/0.jpg"])
        XCTAssertTrue(result.normal.isEmpty)
        XCTAssertTrue(result.low.isEmpty)
    }

    func testCarousel_twoPhotos_page0_prefetchesBothFullsize() {
        let result = ImagePrefetchPlanning.carouselPrefetchRequests(photos: photos(2), currentPage: 0)
        XCTAssertEqual(urls(from: result.high), [
            "https://cdn.example.com/full/0.jpg",
            "https://cdn.example.com/full/1.jpg",
        ])
    }

    func testCarousel_fivePhotos_page0_prefetchesOnlyFirstTwo() {
        let result = ImagePrefetchPlanning.carouselPrefetchRequests(photos: photos(5), currentPage: 0)
        XCTAssertEqual(urls(from: result.high).count, 2)
        XCTAssertTrue(result.normal.isEmpty)
    }

    // MARK: - Carousel: Page 1

    func testCarousel_threePhotos_page1_prefetchesThirdFullsizeAndAllThumbs() {
        let result = ImagePrefetchPlanning.carouselPrefetchRequests(photos: photos(3), currentPage: 1)
        XCTAssertEqual(urls(from: result.high), ["https://cdn.example.com/full/2.jpg"])
        XCTAssertEqual(urls(from: result.normal).count, 3) // all 3 thumbs
        XCTAssertTrue(urls(from: result.normal).allSatisfy { $0.contains("/thumb/") })
    }

    func testCarousel_twoPhotos_page1_noThirdFullsize_stillPrefetchesThumbs() {
        let result = ImagePrefetchPlanning.carouselPrefetchRequests(photos: photos(2), currentPage: 1)
        XCTAssertTrue(result.high.isEmpty)
        XCTAssertEqual(urls(from: result.normal).count, 2) // both thumbs
    }

    // MARK: - Carousel: Page 2+

    func testCarousel_tenPhotos_page5_prefetchesNextAtHighRestAtNormal() {
        let result = ImagePrefetchPlanning.carouselPrefetchRequests(photos: photos(10), currentPage: 5)
        XCTAssertEqual(urls(from: result.high), ["https://cdn.example.com/full/6.jpg"])
        XCTAssertEqual(urls(from: result.normal).count, 3) // 7, 8, 9
    }

    func testCarousel_lastPage_returnsEmpty() {
        let result = ImagePrefetchPlanning.carouselPrefetchRequests(photos: photos(3), currentPage: 2)
        XCTAssertTrue(result.high.isEmpty)
        XCTAssertTrue(result.normal.isEmpty)
    }

    // MARK: - Feed: Edge Cases

    func testFeed_emptyGalleries_returnsEmpty() {
        let result = ImagePrefetchPlanning.feedPrefetchRequests(galleries: [], currentIndex: 0)
        XCTAssertTrue(result.all.isEmpty)
    }

    func testFeed_atLastGallery_returnsEmpty() {
        let galleries: [(firstThumb: String?, firstFullsize: String?)] = [
            (firstThumb: "t0", firstFullsize: "f0"),
        ]
        let result = ImagePrefetchPlanning.feedPrefetchRequests(galleries: galleries, currentIndex: 0)
        XCTAssertTrue(result.all.isEmpty)
    }

    // MARK: - Feed: Look-ahead

    func testFeed_tenGalleries_atIndex3_prefetchesNext3() {
        let galleries: [(firstThumb: String?, firstFullsize: String?)] = (0 ..< 10).map { i in
            (firstThumb: "https://cdn.example.com/thumb/\(i).jpg",
             firstFullsize: "https://cdn.example.com/full/\(i).jpg")
        }
        let result = ImagePrefetchPlanning.feedPrefetchRequests(galleries: galleries, currentIndex: 3)

        // High: thumb 4, fullsize 4, thumb 5
        // Normal: fullsize 5
        // Low: fullsize 6, thumb 6
        let allUrls = urls(from: result.all)
        XCTAssertTrue(allUrls.contains("https://cdn.example.com/full/4.jpg"))
        XCTAssertTrue(allUrls.contains("https://cdn.example.com/full/5.jpg"))
        XCTAssertTrue(allUrls.contains("https://cdn.example.com/full/6.jpg"))
        XCTAssertTrue(allUrls.contains("https://cdn.example.com/thumb/4.jpg"))
    }

    func testFeed_galleryWithNoPhotos_skipsGracefully() {
        let galleries: [(firstThumb: String?, firstFullsize: String?)] = [
            (firstThumb: "t0", firstFullsize: "f0"),
            (firstThumb: nil, firstFullsize: nil), // gallery with no photos
            (firstThumb: "t2", firstFullsize: "f2"),
        ]
        let result = ImagePrefetchPlanning.feedPrefetchRequests(galleries: galleries, currentIndex: 0)
        // Should still get gallery at index 2
        let allUrls = urls(from: result.all)
        XCTAssertTrue(allUrls.contains("t2"))
        XCTAssertFalse(allUrls.contains("nil"))
    }

    // MARK: - Stories: Edge Cases

    func testStory_emptyCurrentStories_returnsEmpty() {
        let result = ImagePrefetchPlanning.storyPrefetchRequests(
            currentStories: [],
            currentStoryIndex: 0,
            nextAuthorStories: nil,
            secondNextAuthorStories: nil,
            thirdNextFirstStory: nil,
            fourthNextFirstStory: nil
        )
        XCTAssertTrue(result.all.isEmpty)
    }

    // MARK: - Stories: Priority Order

    func testStory_fiveStories_atIndex0_prefetchesCorrectPriorities() {
        let stories = photos(5)
        let nextAuthor = photos(3)

        let result = ImagePrefetchPlanning.storyPrefetchRequests(
            currentStories: stories,
            currentStoryIndex: 0,
            nextAuthorStories: nextAuthor,
            secondNextAuthorStories: nil,
            thirdNextFirstStory: nil,
            fourthNextFirstStory: nil
        )

        // High: stories 1, 2 of current + first of next author
        XCTAssertEqual(urls(from: result.high), [
            "https://cdn.example.com/full/1.jpg",
            "https://cdn.example.com/full/2.jpg",
            "https://cdn.example.com/full/0.jpg", // next author's first
        ])

        // Normal: stories 3, 4 of current (rest of stack)
        XCTAssertEqual(urls(from: result.normal), [
            "https://cdn.example.com/full/3.jpg",
            "https://cdn.example.com/full/4.jpg",
        ])
    }

    func testStory_lastStoryOfAuthor_onlyPrefetchesNextAuthor() {
        let stories = photos(1)
        let nextAuthor = photos(2)

        let result = ImagePrefetchPlanning.storyPrefetchRequests(
            currentStories: stories,
            currentStoryIndex: 0,
            nextAuthorStories: nextAuthor,
            secondNextAuthorStories: nil,
            thirdNextFirstStory: nil,
            fourthNextFirstStory: nil
        )

        // High: only next author's first (no more current stories to prefetch)
        XCTAssertEqual(urls(from: result.high), ["https://cdn.example.com/full/0.jpg"])
    }

    func testStory_noNextAuthorData_skipsThatTier() {
        let stories = photos(3)

        let result = ImagePrefetchPlanning.storyPrefetchRequests(
            currentStories: stories,
            currentStoryIndex: 0,
            nextAuthorStories: nil,
            secondNextAuthorStories: nil,
            thirdNextFirstStory: nil,
            fourthNextFirstStory: nil
        )

        // High: only current author stories 1, 2
        XCTAssertEqual(urls(from: result.high).count, 2)
        XCTAssertTrue(result.low.isEmpty)
    }

    func testStory_fullPriorityChain() {
        let current = photos(2)
        let nextAuthor = [(thumb: "https://next/t0", fullsize: "https://next/f0")]
        let secondNext = [(thumb: "https://second/t0", fullsize: "https://second/f0"),
                          (thumb: "https://second/t1", fullsize: "https://second/f1")]
        let third = (thumb: "https://third/t0", fullsize: "https://third/f0")
        let fourth = (thumb: "https://fourth/t0", fullsize: "https://fourth/f0")

        let result = ImagePrefetchPlanning.storyPrefetchRequests(
            currentStories: current,
            currentStoryIndex: 0,
            nextAuthorStories: nextAuthor,
            secondNextAuthorStories: secondNext,
            thirdNextFirstStory: third,
            fourthNextFirstStory: fourth
        )

        // High: current story 1 + next author first
        XCTAssertEqual(urls(from: result.high).count, 2)
        // Normal: second-next author stories 0, 1
        XCTAssertEqual(urls(from: result.normal).count, 2)
        // Low: third + fourth author firsts
        XCTAssertEqual(urls(from: result.low).count, 2)
    }
}

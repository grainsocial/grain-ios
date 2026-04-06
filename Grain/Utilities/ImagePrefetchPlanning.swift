import Foundation
import Nuke

struct PrioritizedRequests {
    let high: [ImageRequest]
    let normal: [ImageRequest]
    let low: [ImageRequest]

    var all: [ImageRequest] {
        high + normal + low
    }
}

enum ImagePrefetchPlanning {
    // MARK: - Carousel

    /// Tiered prefetch URLs for a gallery photo carousel.
    ///
    /// - Page 0 (on appear): fullsize #0, #1 at high
    /// - Page 1: fullsize #2 at high, all thumbs at normal
    /// - Page 2+: next fullsize at high, remaining fullsize at normal
    static func carouselPrefetchRequests(
        photos: [(thumb: String, fullsize: String)],
        currentPage: Int
    ) -> PrioritizedRequests {
        guard !photos.isEmpty, currentPage >= 0, currentPage < photos.count else {
            return PrioritizedRequests(high: [], normal: [], low: [])
        }

        var high: [ImageRequest] = []
        var normal: [ImageRequest] = []
        let low: [ImageRequest] = []

        if currentPage == 0 {
            // Prefetch first 2 fullsize
            for i in 0 ..< min(2, photos.count) {
                if let url = URL(string: photos[i].fullsize) {
                    high.append(ImageRequest(url: url, priority: .high))
                }
            }
        } else if currentPage == 1 {
            // Fullsize #2 at high
            if photos.count > 2, let url = URL(string: photos[2].fullsize) {
                high.append(ImageRequest(url: url, priority: .high))
            }
            // All thumbs at normal
            for photo in photos {
                if let url = URL(string: photo.thumb) {
                    normal.append(ImageRequest(url: url, priority: .normal))
                }
            }
        } else {
            // Page 2+: next fullsize at high, rest at normal
            for i in (currentPage + 1) ..< photos.count {
                if let url = URL(string: photos[i].fullsize) {
                    let priority: ImageRequest.Priority = i == currentPage + 1 ? .high : .normal
                    if priority == .high {
                        high.append(ImageRequest(url: url, priority: .high))
                    } else {
                        normal.append(ImageRequest(url: url, priority: .normal))
                    }
                }
            }
        }

        return PrioritizedRequests(high: high, normal: normal, low: low)
    }

    // MARK: - Feed

    /// Prefetch first image (thumb + fullsize) of upcoming galleries in the feed.
    ///
    /// - i+1: thumb at high, fullsize at high
    /// - i+2: thumb at high, fullsize at normal
    /// - i+3: thumb at high, fullsize at low
    static func feedPrefetchRequests(
        galleries: [(firstThumb: String?, firstFullsize: String?)],
        currentIndex: Int
    ) -> PrioritizedRequests {
        guard currentIndex >= 0, currentIndex < galleries.count else {
            return PrioritizedRequests(high: [], normal: [], low: [])
        }

        var high: [ImageRequest] = []
        var normal: [ImageRequest] = []
        var low: [ImageRequest] = []

        for offset in 1 ... 3 {
            let idx = currentIndex + offset
            guard idx < galleries.count else { break }
            let gallery = galleries[idx]

            // Thumbs are tiny — always high priority
            if let thumb = gallery.firstThumb, let url = URL(string: thumb) {
                high.append(ImageRequest(url: url, priority: .high))
            }

            if let fullsize = gallery.firstFullsize, let url = URL(string: fullsize) {
                switch offset {
                case 1:
                    high.append(ImageRequest(url: url, priority: .high))
                case 2:
                    normal.append(ImageRequest(url: url, priority: .normal))
                default:
                    low.append(ImageRequest(url: url, priority: .low))
                }
            }
        }

        return PrioritizedRequests(high: high, normal: normal, low: low)
    }

    // MARK: - Stories

    /// Prefetch story images with priority queue:
    /// 1. Next 2 stories of current author — high
    /// 2. First story of next author — high
    /// 3. Rest of current author's stack — normal
    /// 4. Next 2 stories of author-after-next — normal
    /// 5. First story of next 2 authors beyond — low
    static func storyPrefetchRequests(
        currentStories: [(thumb: String, fullsize: String)],
        currentStoryIndex: Int,
        nextAuthorStories: [(thumb: String, fullsize: String)]?,
        secondNextAuthorStories: [(thumb: String, fullsize: String)]?,
        thirdNextFirstStory: (thumb: String, fullsize: String)?,
        fourthNextFirstStory: (thumb: String, fullsize: String)?
    ) -> PrioritizedRequests {
        var high: [ImageRequest] = []
        var normal: [ImageRequest] = []
        var low: [ImageRequest] = []

        // 1. Next 2 stories of current author — high
        for i in (currentStoryIndex + 1) ..< min(currentStoryIndex + 3, currentStories.count) {
            if let url = URL(string: currentStories[i].fullsize) {
                high.append(ImageRequest(url: url, priority: .high))
            }
        }

        // 2. First story of next author — high
        if let first = nextAuthorStories?.first, let url = URL(string: first.fullsize) {
            high.append(ImageRequest(url: url, priority: .high))
        }

        // 3. Rest of current author's stack — normal
        let restStart = currentStoryIndex + 3
        if restStart < currentStories.count {
            for i in restStart ..< currentStories.count {
                if let url = URL(string: currentStories[i].fullsize) {
                    normal.append(ImageRequest(url: url, priority: .normal))
                }
            }
        }

        // 4. Next 2 stories of author-after-next — normal
        if let stories = secondNextAuthorStories {
            for i in 0 ..< min(2, stories.count) {
                if let url = URL(string: stories[i].fullsize) {
                    normal.append(ImageRequest(url: url, priority: .normal))
                }
            }
        }

        // 5. First story of next 2 authors beyond — low
        if let story = thirdNextFirstStory, let url = URL(string: story.fullsize) {
            low.append(ImageRequest(url: url, priority: .low))
        }
        if let story = fourthNextFirstStory, let url = URL(string: story.fullsize) {
            low.append(ImageRequest(url: url, priority: .low))
        }

        return PrioritizedRequests(high: high, normal: normal, low: low)
    }
}

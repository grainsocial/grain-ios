import Foundation

@Observable
@MainActor
final class FeedViewModel {
    var galleries: [GrainGallery] = []
    var isLoading = false
    var error: Error?
    /// Set to `true` after the first network fetch completes (success or failure).
    /// Used by FeedTabContent to always run a fresh fetch on first appear, even when
    /// galleries are pre-populated from the disk cache.
    var hasFetchedInitial = false

    private var cursor: String?
    private var hasMore = true
    private var loadTask: Task<Void, Never>?
    private let client: XRPCClient
    private let feedName: String
    private let actor: String?
    private let camera: String?
    private let location: String?
    private let tag: String?
    private let cacheKey: String?

    init(
        client: XRPCClient,
        feedName: String,
        actor: String? = nil,
        camera: String? = nil,
        location: String? = nil,
        tag: String? = nil,
        cacheKey: String? = nil
    ) {
        self.client = client
        self.feedName = feedName
        self.actor = actor
        self.camera = camera
        self.location = location
        self.tag = tag
        self.cacheKey = cacheKey
        if let cacheKey {
            galleries = FeedCache.shared.load(key: cacheKey)
        }
    }

    convenience init(client: XRPCClient, pinnedFeed: PinnedFeed, userDID: String? = nil) {
        self.init(
            client: client,
            feedName: pinnedFeed.feedName,
            actor: (pinnedFeed.id == "following" || pinnedFeed.id == "foryou") ? userDID : nil,
            camera: pinnedFeed.type == "camera" ? pinnedFeed.feedValue : nil,
            location: pinnedFeed.type == "location" ? pinnedFeed.feedValue : nil,
            tag: pinnedFeed.type == "hashtag" ? pinnedFeed.feedValue : nil,
            cacheKey: pinnedFeed.id
        )
    }

    func loadInitial(auth: AuthContext? = nil) async {
        loadTask?.cancel()
        isLoading = true
        error = nil
        cursor = nil
        hasMore = true

        let task = Task {
            do {
                let response = try await client.getFeed(
                    feed: feedName,
                    actor: actor,
                    camera: camera,
                    location: location,
                    tag: tag,
                    auth: auth
                )
                guard !Task.isCancelled else { return }
                galleries = response.items ?? []
                cursor = response.cursor
                hasMore = response.cursor != nil
                if let key = cacheKey {
                    let toCache = galleries
                    Task.detached(priority: .utility) {
                        FeedCache.shared.save(toCache, key: key)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
            }
            isLoading = false
            hasFetchedInitial = true
        }
        loadTask = task
        await task.value
    }

    func loadMore(auth: AuthContext? = nil) async {
        guard !isLoading, hasMore, let cursor else { return }
        isLoading = true

        do {
            let response = try await client.getFeed(
                feed: feedName,
                cursor: cursor,
                actor: actor,
                camera: camera,
                location: location,
                auth: auth
            )
            galleries.append(contentsOf: response.items ?? [])
            self.cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            self.error = error
        }
        isLoading = false
    }
}

import Foundation

@Observable
@MainActor
final class FeedViewModel {
    var galleries: [GrainGallery] = []
    var isLoading = false
    var error: Error?

    private var cursor: String?
    private var hasMore = true
    private let client: XRPCClient
    private let feedName: String
    private let actor: String?
    private let camera: String?
    private let location: String?
    private let tag: String?

    init(
        client: XRPCClient,
        feedName: String,
        actor: String? = nil,
        camera: String? = nil,
        location: String? = nil,
        tag: String? = nil
    ) {
        self.client = client
        self.feedName = feedName
        self.actor = actor
        self.camera = camera
        self.location = location
        self.tag = tag
    }

    convenience init(client: XRPCClient, pinnedFeed: PinnedFeed, userDID: String? = nil) {
        self.init(
            client: client,
            feedName: pinnedFeed.feedName,
            actor: pinnedFeed.id == "following" ? userDID : nil,
            camera: pinnedFeed.type == "camera" ? pinnedFeed.feedValue : nil,
            location: pinnedFeed.type == "location" ? pinnedFeed.feedValue : nil,
            tag: pinnedFeed.type == "hashtag" ? pinnedFeed.feedValue : nil
        )
    }

    func loadInitial(auth: AuthContext? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        cursor = nil
        hasMore = true

        do {
            let response = try await client.getFeed(
                feed: feedName,
                actor: actor,
                camera: camera,
                location: location,
                tag: tag,
                auth: auth
            )
            galleries = response.items ?? []
            cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            self.error = error
        }
        isLoading = false
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

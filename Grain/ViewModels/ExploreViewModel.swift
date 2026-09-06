import Foundation

/// What the search tab shows before anything is typed: the recent feed as a
/// grid, headed by chips for the most-used cameras and places.
///
/// The chips are kept apart from the galleries because they arrive on their
/// own requests and fail on their own: a camera index that is down should
/// not take the recent galleries with it, and the other way round.
@Observable
@MainActor
final class ExploreViewModel {
    var cameras: [CameraItem] = []
    var locations: [LocationItem] = []
    var galleries: [GrainGallery] = []
    var isLoading = true
    var isLoadingMore = false

    private let client: XRPCClient
    private var cursor: String?
    private var loaded = false

    init(client: XRPCClient) {
        self.client = client
    }

    /// The first load, once. The tab is composed each time it is shown, and
    /// a second look should not blank what was already there.
    func loadIfNeeded(auth: AuthContext? = nil) async {
        guard !loaded else { return }
        loaded = true
        await load(auth: auth)
    }

    func refresh(auth: AuthContext? = nil) async {
        await load(auth: auth)
    }

    private func load(auth: AuthContext?) async {
        // Three requests, none waiting on another. Each keeps what it had on
        // failure: a chip row that empties because one refresh timed out
        // would read as the cameras having gone.
        async let camerasReq = client.getCameras(auth: auth)
        async let locationsReq = client.getLocations(auth: auth)
        async let feedReq = client.getFeed(feed: "recent", auth: auth)

        if let response = try? await camerasReq {
            cameras = response.cameras ?? []
        }
        if let response = try? await locationsReq {
            locations = response.locations ?? []
        }
        if let response = try? await feedReq {
            galleries = response.items ?? []
            cursor = response.cursor
        }
        isLoading = false
    }

    func loadMore(auth: AuthContext? = nil) async {
        guard let cursor, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        do {
            let response = try await client.getFeed(feed: "recent", cursor: cursor, auth: auth)
            galleries.append(contentsOf: response.items ?? [])
            self.cursor = response.cursor
        } catch {}
        isLoadingMore = false
    }
}

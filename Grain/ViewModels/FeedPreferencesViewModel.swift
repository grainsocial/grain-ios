import Foundation

@Observable
@MainActor
final class FeedPreferencesViewModel {
    var pinnedFeeds: [PinnedFeed] = PinnedFeed.defaults
    var selectedFeedId: String = "recent"
    var includeExif: Bool = true
    private var hasLoaded = false

    private let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
    }

    var selectedFeedLabel: String {
        pinnedFeeds.first(where: { $0.id == selectedFeedId })?.label ?? "Feed"
    }

    func loadIfNeeded(auth: AuthContext?) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh(auth: auth)
    }

    func refresh(auth: AuthContext?) async {
        do {
            let response = try await client.getPreferences(auth: auth)
            if let feeds = response.preferences.pinnedFeeds, !feeds.isEmpty {
                pinnedFeeds = feeds
                if !feeds.contains(where: { $0.id == selectedFeedId }) {
                    selectedFeedId = feeds.first?.id ?? "recent"
                }
            }
            if let exif = response.preferences.includeExif {
                includeExif = exif
            }
        } catch {
            // Fall back to defaults, already set
        }
    }

    func isPinned(_ id: String) -> Bool {
        pinnedFeeds.contains(where: { $0.id == id })
    }

    func pinFeed(_ feed: PinnedFeed, auth: AuthContext?) async {
        guard !isPinned(feed.id) else { return }
        let updated = pinnedFeeds + [feed]
        pinnedFeeds = updated
        do {
            try await client.putPinnedFeeds(updated, auth: auth)
        } catch {
            pinnedFeeds.removeAll { $0.id == feed.id }
        }
    }

    func setIncludeExif(_ value: Bool, auth: AuthContext?) async {
        let previous = includeExif
        includeExif = value
        do {
            try await client.putIncludeExif(value, auth: auth)
        } catch {
            includeExif = previous
        }
    }

    func unpinFeed(_ id: String, auth: AuthContext?) async {
        let original = pinnedFeeds
        pinnedFeeds.removeAll { $0.id == id }
        if selectedFeedId == id {
            selectedFeedId = pinnedFeeds.first?.id ?? "recent"
        }
        do {
            try await client.putPinnedFeeds(pinnedFeeds, auth: auth)
        } catch {
            pinnedFeeds = original
            selectedFeedId = id
        }
    }
}

import Foundation

@Observable
@MainActor
final class FeedPreferencesViewModel {
    var pinnedFeeds: [PinnedFeed] = PinnedFeed.defaults
    var selectedFeedId: String = "recent"
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
        } catch {
            // Fall back to defaults, already set
        }
    }
}

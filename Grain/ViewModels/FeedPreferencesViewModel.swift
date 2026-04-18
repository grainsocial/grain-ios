import Foundation
import os

private let prefsSignposter = OSSignposter(subsystem: "social.grain.grain", category: "FeedPrefs")

@Observable
@MainActor
final class FeedPreferencesViewModel {
    var pinnedFeeds: [PinnedFeed] = PinnedFeed.defaults
    var selectedFeedId: String = "recent"
    var includeExif: Bool = true
    private var hasLoaded = false
    private var refreshTask: Task<Void, Never>?

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

    /// Coalesces concurrent refresh calls so launch-time `.task` +
    /// `.onAppear` callers share one network round-trip instead of two.
    func refresh(auth: AuthContext?) async {
        if let existing = refreshTask {
            await existing.value
            return
        }
        let task = Task { @MainActor [weak self] in
            await self?.performRefresh(auth: auth)
            self?.refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh(auth: AuthContext?) async {
        let totalSpid = prefsSignposter.makeSignpostID()
        let totalState = prefsSignposter.beginInterval("Prefs.refresh", id: totalSpid)
        defer { prefsSignposter.endInterval("Prefs.refresh", totalState) }

        do {
            let netSpid = prefsSignposter.makeSignpostID()
            let netState = prefsSignposter.beginInterval("Prefs.network", id: netSpid)
            let response = try await client.getPreferences(auth: auth)
            prefsSignposter.endInterval("Prefs.network", netState)

            let publishSpid = prefsSignposter.makeSignpostID()
            let publishState = prefsSignposter.beginInterval("Prefs.publish", id: publishSpid)
            if let feeds = response.preferences.pinnedFeeds, !feeds.isEmpty {
                pinnedFeeds = feeds
                if !feeds.contains(where: { $0.id == selectedFeedId }) {
                    selectedFeedId = feeds.first?.id ?? "recent"
                }
            }
            if let exif = response.preferences.includeExif {
                includeExif = exif
            }
            prefsSignposter.endInterval("Prefs.publish", publishState)
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

    func reorderFeeds(_ feeds: [PinnedFeed], auth: AuthContext?) async {
        let original = pinnedFeeds
        pinnedFeeds = feeds
        do {
            try await client.putPinnedFeeds(feeds, auth: auth)
        } catch {
            pinnedFeeds = original
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

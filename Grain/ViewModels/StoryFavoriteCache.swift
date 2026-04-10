import Foundation

/// Session-scoped cache of story favorites. Bridges the gap until the grain
/// appview returns `viewer.fav` on story responses — once it does, this
/// becomes redundant and can be removed.
@Observable
@MainActor
final class StoryFavoriteCache {
    /// storyUri → favorite record URI. Presence means liked.
    var favorites: [String: String] = [:]

    func isLiked(_ storyUri: String) -> Bool {
        favorites[storyUri] != nil
    }

    func favUri(for storyUri: String) -> String? {
        favorites[storyUri]
    }

    func like(_ storyUri: String, favUri: String) {
        favorites[storyUri] = favUri
    }

    func unlike(_ storyUri: String) {
        favorites.removeValue(forKey: storyUri)
    }
}

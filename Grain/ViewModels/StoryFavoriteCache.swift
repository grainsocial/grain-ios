import Foundation

/// Persistent cache of story favorites, keyed by story URI. Bridges the gap
/// until the grain appview returns `viewer.fav` on story responses — once it
/// does, this becomes redundant and can be removed.
@Observable
@MainActor
final class StoryFavoriteCache {
    /// storyUri → favorite record URI. Presence means liked.
    private(set) var favorites: [String: String] = [:]

    private static let key = "storyFavorites"

    init() {
        load()
    }

    func isLiked(_ storyUri: String) -> Bool {
        favorites[storyUri] != nil
    }

    func favUri(for storyUri: String) -> String? {
        favorites[storyUri]
    }

    func like(_ storyUri: String, favUri: String) {
        favorites[storyUri] = favUri
        save()
    }

    func unlike(_ storyUri: String) {
        favorites.removeValue(forKey: storyUri)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] else { return }
        favorites = data
    }

    private func save() {
        UserDefaults.standard.set(favorites, forKey: Self.key)
    }
}

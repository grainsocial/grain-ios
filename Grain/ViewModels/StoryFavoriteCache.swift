import Foundation

/// Session-scoped cache of story favorites. Ensures that favoriting a story
/// sticks across navigation and story re-fetches, even when the server does
/// not yet return viewer state for stories.
@Observable
@MainActor
final class StoryFavoriteCache {
    /// Maps story URI → favorite record URI.
    private(set) var favoritesByUri: [String: String] = [:]

    func favUri(for storyUri: String) -> String? {
        favoritesByUri[storyUri]
    }

    func setFavorite(storyUri: String, favUri: String?) {
        if let favUri {
            favoritesByUri[storyUri] = favUri
        } else {
            favoritesByUri.removeValue(forKey: storyUri)
        }
    }

    /// Overlays cached favorites onto a story array so the UI reflects session state.
    func apply(to stories: inout [GrainStory]) {
        for i in stories.indices {
            if let favUri = favoritesByUri[stories[i].uri] {
                stories[i].viewer = StoryViewerState(fav: favUri)
            }
        }
    }
}

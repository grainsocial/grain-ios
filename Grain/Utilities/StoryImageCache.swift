import Foundation
import Nuke

/// Returns `true` if the fullsize image for `story` is already in `pipeline`'s memory cache.
///
/// Extracted from `StoryViewer` so it can be tested without spinning up a SwiftUI view
/// and without touching `ImagePipeline.shared`.
func storyFullsizeCached(_ story: GrainStory?, in pipeline: ImagePipeline = .shared) -> Bool {
    guard let url = story.flatMap({ URL(string: $0.fullsize) }) else { return false }
    return pipeline.cache.cachedImage(for: ImageRequest(url: url)) != nil
}

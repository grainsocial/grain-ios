import Foundation

@Observable
@MainActor
final class StoryStripViewModel {
    var authors: [GrainStoryAuthor] = []
    var isLoading = false
    /// Bumped to trigger re-render without changing author order.
    var version: Int = 0

    private let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
    }

    func load(auth: AuthContext? = nil, storyStatusCache: StoryStatusCache? = nil) async {
        isLoading = true
        do {
            let response = try await client.getStoryAuthors(auth: auth)
            authors = response.authors
            storyStatusCache?.update(from: response.authors)
        } catch {
            // Silently fail — strip just won't show
        }
        isLoading = false
    }

    /// Signal that viewed state changed so views re-evaluate sort order.
    func invalidate() {
        version += 1
    }
}

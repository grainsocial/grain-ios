import Foundation

@Observable
@MainActor
final class StoryStripViewModel {
    var authors: [GrainStoryAuthor] = []
    var isLoading = false

    private let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
    }

    func load(auth: AuthContext? = nil) async {
        isLoading = true
        do {
            let response = try await client.getStoryAuthors(auth: auth)
            authors = response.authors
        } catch {
            // Silently fail — strip just won't show
        }
        isLoading = false
    }
}

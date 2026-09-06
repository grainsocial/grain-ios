import Foundation

@Observable
@MainActor
final class SearchViewModel {
    var galleryResults: [GrainGallery] = []
    var profileResults: [ProfileSearchResult] = []
    var locations: [LocationItem] = []
    var cameras: [CameraItem] = []
    var isSearching = false
    /// True once a search has answered for the current text, so an empty
    /// list can say "nothing matched" rather than nothing at all.
    var hasSearched = false
    var searchText = ""
    var selectedTab: SearchTab = .galleries

    private let client: XRPCClient
    /// Bumped by every search and every clear. A search that comes back to
    /// find it moved on was overtaken by a later keystroke, and its answer
    /// would be to a question nobody is asking any more.
    private var generation = 0

    enum SearchTab: String, CaseIterable {
        case galleries = "Galleries"
        case profiles = "Profiles"
    }

    init(client: XRPCClient) {
        self.client = client
    }

    func loadDiscovery(auth: AuthContext? = nil) async {
        do {
            let locationsResponse = try await client.getLocations(auth: auth)
            let camerasResponse = try await client.getCameras(auth: auth)
            locations = locationsResponse.locations ?? []
            cameras = camerasResponse.cameras ?? []
        } catch {}
    }

    func search(auth: AuthContext? = nil) async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        generation += 1
        let mine = generation
        isSearching = true

        do {
            switch selectedTab {
            case .galleries:
                let response = try await client.searchGalleries(query: query, auth: auth)
                guard mine == generation else { return }
                galleryResults = response.items ?? []
            case .profiles:
                let response = try await client.searchProfiles(query: query, auth: auth)
                guard mine == generation else { return }
                profileResults = response.items ?? []
            }
        } catch {}
        guard mine == generation else { return }
        isSearching = false
        hasSearched = true
    }

    /// The field emptied: nothing to show, and nothing in flight counts.
    func clearResults() {
        generation += 1
        galleryResults = []
        profileResults = []
        isSearching = false
        hasSearched = false
    }
}

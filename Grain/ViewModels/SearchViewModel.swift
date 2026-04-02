import Foundation

@Observable
@MainActor
final class SearchViewModel {
    var galleryResults: [GrainGallery] = []
    var profileResults: [ProfileSearchResult] = []
    var locations: [LocationItem] = []
    var cameras: [CameraItem] = []
    var isSearching = false
    var searchText = ""
    var selectedTab: SearchTab = .galleries

    private let client: XRPCClient

    enum SearchTab: String, CaseIterable {
        case galleries = "Galleries"
        case profiles = "Profiles"
    }

    init(client: XRPCClient) {
        self.client = client
    }

    func loadDiscovery(auth: AuthContext? = nil) async {
        do {
            let l = try await client.getLocations(auth: auth)
            let c = try await client.getCameras(auth: auth)
            locations = l.locations ?? []
            cameras = c.cameras ?? []
        } catch {}
    }

    func search(auth: AuthContext? = nil) async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true

        do {
            switch selectedTab {
            case .galleries:
                let response = try await client.searchGalleries(query: query, auth: auth)
                galleryResults = response.items ?? []
            case .profiles:
                let response = try await client.searchProfiles(query: query, auth: auth)
                profileResults = response.items ?? []
            }
        } catch {}
        isSearching = false
    }
}

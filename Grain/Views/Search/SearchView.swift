import SwiftUI

struct SearchView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @State private var viewModel: SearchViewModel
    @State private var searchText = ""
    @State private var searchNavigationUri: String?
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?
    @State private var zoomState = ImageZoomState()
    @State private var cardStoryAuthor: GrainStoryAuthor?
    let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
        _viewModel = State(initialValue: SearchViewModel(client: client))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.searchText.isEmpty {
                    ContentUnavailableView("Search", systemImage: "magnifyingglass", description: Text("Search for galleries and profiles"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            switch viewModel.selectedTab {
                            case .galleries:
                                ForEach($viewModel.galleryResults) { $gallery in
                                    GalleryCardView(gallery: $gallery, client: client, onNavigate: {
                                        searchNavigationUri = gallery.uri
                                    }, onProfileTap: { did in
                                        selectedProfileDid = did
                                    }, onHashtagTap: { tag in
                                        selectedHashtag = tag
                                    }, onStoryTap: { author in
                                        cardStoryAuthor = author
                                    })
                                }
                            case .profiles:
                                ForEach(viewModel.profileResults) { profile in
                                    Button {
                                        selectedProfileDid = profile.did
                                    } label: {
                                        HStack {
                                            StoryRingView(hasStory: storyStatusCache.hasStory(for: profile.did), size: 40) {
                                                AvatarView(url: profile.avatar, size: 40)
                                            }
                                            VStack(alignment: .leading) {
                                                Text(profile.displayName ?? profile.handle ?? "")
                                                    .font(.subheadline.bold())
                                                if let handle = profile.handle {
                                                    Text("@\(handle)")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top)
                    }
                    .environment(zoomState)
                    .modifier(ImageZoomOverlay(zoomState: zoomState))
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search galleries & profiles")
            .searchScopes($viewModel.selectedTab, activation: .onSearchPresentation) {
                ForEach(SearchViewModel.SearchTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .onSubmit(of: .search) {
                Task { await viewModel.search(auth: auth.authContext()) }
            }
            .onChange(of: searchText) {
                viewModel.searchText = searchText
            }
            .onChange(of: viewModel.selectedTab) {
                if !viewModel.searchText.isEmpty {
                    Task { await viewModel.search(auth: auth.authContext()) }
                }
            }
            .navigationDestination(item: $searchNavigationUri) { uri in
                GalleryDetailView(client: client, galleryUri: uri)
            }
            .navigationDestination(item: $selectedProfileDid) { did in
                ProfileView(client: client, did: did)
            }
            .navigationDestination(item: $selectedHashtag) { tag in
                HashtagFeedView(client: client, tag: tag)
            }
            .fullScreenCover(item: $cardStoryAuthor) { author in
                StoryViewer(
                    authors: [author],
                    client: client,
                    onProfileTap: { did in
                        cardStoryAuthor = nil
                        selectedProfileDid = did
                    },
                    onDismiss: { cardStoryAuthor = nil }
                )
                .environment(auth)
            }
        }
    }
}

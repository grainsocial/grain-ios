import SwiftUI

struct FeedView: View {
    @Environment(AuthManager.self) private var auth
    @State private var pinnedFeeds: [PinnedFeed] = PinnedFeed.defaults
    @State private var selectedFeedId: String = "recent"
    @State private var hasLoadedPreferences = false

    let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
    }

    private var selectedFeedLabel: String {
        pinnedFeeds.first(where: { $0.id == selectedFeedId })?.label ?? "Feed"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ForEach(pinnedFeeds) { feed in
                    if feed.id == selectedFeedId {
                        FeedTabContent(client: client, pinnedFeed: feed, userDID: auth.userDID)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(pinnedFeeds) { feed in
                            Button {
                                selectedFeedId = feed.id
                            } label: {
                                if feed.id == selectedFeedId {
                                    Label(feed.label, systemImage: "checkmark")
                                } else {
                                    Text(feed.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("grain")
                                .font(.custom("Syne", size: 20).weight(.heavy))
                            if pinnedFeeds.count > 1 {
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.bold))
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
            .task {
                await loadPreferences()
            }
        }
    }

    private func loadPreferences() async {
        guard !hasLoadedPreferences else { return }
        hasLoadedPreferences = true

        do {
            let response = try await client.getPreferences(auth: auth.authContext())
            if let feeds = response.preferences.pinnedFeeds, !feeds.isEmpty {
                pinnedFeeds = feeds
                selectedFeedId = feeds.first?.id ?? "recent"
            }
        } catch {
            // Fall back to defaults, already set
        }
    }
}

private struct FeedTabContent: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: FeedViewModel
    @State private var selectedUri: String?
    @State private var selectedProfileDid: String?
    let client: XRPCClient

    init(client: XRPCClient, pinnedFeed: PinnedFeed, userDID: String? = nil) {
        self.client = client
        _viewModel = State(initialValue: FeedViewModel(client: client, pinnedFeed: pinnedFeed, userDID: userDID))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach($viewModel.galleries) { $gallery in
                    GalleryCardView(gallery: $gallery, client: client, onNavigate: {
                        selectedUri = gallery.uri
                    }, onProfileTap: { did in
                        selectedProfileDid = did
                    })
                    .onAppear {
                        if gallery.id == viewModel.galleries.last?.id {
                            Task { await viewModel.loadMore(auth: auth.authContext()) }
                        }
                    }

                    Divider()
                }

                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                }
            }
        }
        .refreshable {
            await viewModel.loadInitial(auth: auth.authContext())
        }
        .navigationDestination(item: $selectedUri) { uri in
            GalleryDetailView(client: client, galleryUri: uri)
        }
        .navigationDestination(item: $selectedProfileDid) { did in
            ProfileView(client: client, did: did)
        }
        .task {
            if viewModel.galleries.isEmpty {
                await viewModel.loadInitial(auth: auth.authContext())
            }
        }
    }
}

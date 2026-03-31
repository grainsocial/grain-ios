import SwiftUI

struct FeedView: View {
    @Environment(AuthManager.self) private var auth
    @State private var pinnedFeeds: [PinnedFeed] = PinnedFeed.defaults
    @State private var selectedFeedId: String = "recent"
    @State private var hasLoadedPreferences = false
    @State private var showNavBar = true

    let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ForEach(pinnedFeeds) { feed in
                    if feed.id == selectedFeedId {
                        FeedTabContent(client: client, pinnedFeed: feed, userDID: auth.userDID, showNavBar: $showNavBar)
                    }
                }
            }
            .navigationTitle("grain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .toolbarVisibility(showNavBar ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("grain")
                        .font(.custom("Syne", size: 20).weight(.heavy))
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if pinnedFeeds.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pinnedFeeds) { feed in
                                Button {
                                    selectedFeedId = feed.id
                                } label: {
                                    Text(feed.label)
                                        .font(.subheadline.weight(selectedFeedId == feed.id ? .bold : .regular))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(
                                            selectedFeedId == feed.id
                                                ? AnyShapeStyle(.tint)
                                                : AnyShapeStyle(.quaternary),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(selectedFeedId == feed.id ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .background(.bar)
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
    @Binding var showNavBar: Bool
    let client: XRPCClient

    init(client: XRPCClient, pinnedFeed: PinnedFeed, userDID: String? = nil, showNavBar: Binding<Bool>) {
        self.client = client
        _viewModel = State(initialValue: FeedViewModel(client: client, pinnedFeed: pinnedFeed, userDID: userDID))
        _showNavBar = showNavBar
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach($viewModel.galleries) { $gallery in
                    GalleryCardView(gallery: $gallery, client: client) {
                        selectedUri = gallery.uri
                    }
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
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, newOffset in
            let shouldShow = newOffset < 10
            if shouldShow != showNavBar {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showNavBar = shouldShow
                }
            }
        }
        .refreshable {
            await viewModel.loadInitial(auth: auth.authContext())
        }
        .navigationDestination(item: $selectedUri) { uri in
            GalleryDetailView(client: client, galleryUri: uri)
        }
        .task {
            if viewModel.galleries.isEmpty {
                await viewModel.loadInitial(auth: auth.authContext())
            }
        }
    }
}

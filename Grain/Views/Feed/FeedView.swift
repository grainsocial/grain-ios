import SwiftUI

struct FeedView: View {
    @Environment(AuthManager.self) private var auth
    @State private var pinnedFeeds: [PinnedFeed] = PinnedFeed.defaults
    @State private var selectedFeedId: String = "recent"
    @State private var hasLoadedPreferences = false
    @State private var storyViewModel: StoryStripViewModel
    @State private var showStoryViewer = false
    @State private var storyViewerStartIndex = 0
    @State private var showStoryCreate = false

    let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
        _storyViewModel = State(initialValue: StoryStripViewModel(client: client))
    }

    private var selectedFeedLabel: String {
        pinnedFeeds.first(where: { $0.id == selectedFeedId })?.label ?? "Feed"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ForEach(pinnedFeeds) { feed in
                    if feed.id == selectedFeedId {
                        FeedTabContent(
                            client: client,
                            pinnedFeed: feed,
                            userDID: auth.userDID,
                            storyAuthors: storyViewModel.authors,
                            userAvatar: auth.userAvatar,
                            onStoryAuthorTap: { _, index in
                                storyViewerStartIndex = index
                                showStoryViewer = true
                            },
                            onStoryCreateTap: { showStoryCreate = true },
                            onRefresh: {
                                await storyViewModel.load(auth: auth.authContext())
                            }
                        )
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
                        .foregroundColor(.primary)
                    }
                    .tint(.primary)
                }
            }
            .task {
                await loadPreferences()
                await storyViewModel.load(auth: auth.authContext())
            }
            .customFullScreenCover(isPresented: $showStoryViewer) {
                StoryViewer(
                    authors: storyViewModel.authors,
                    startIndex: storyViewerStartIndex,
                    client: client,
                    onDismiss: { showStoryViewer = false }
                )
            }
            .sheet(isPresented: $showStoryCreate) {
                StoryCreateView(client: client) {
                    Task { await storyViewModel.load(auth: auth.authContext()) }
                }
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
    @State private var selectedHashtag: String?
    let client: XRPCClient
    let storyAuthors: [GrainStoryAuthor]
    let userAvatar: String?
    let onStoryAuthorTap: (GrainStoryAuthor, Int) -> Void
    let onStoryCreateTap: () -> Void
    let onRefresh: (@Sendable () async -> Void)?

    init(client: XRPCClient, pinnedFeed: PinnedFeed, userDID: String? = nil, storyAuthors: [GrainStoryAuthor] = [], userAvatar: String? = nil, onStoryAuthorTap: @escaping (GrainStoryAuthor, Int) -> Void = { _, _ in }, onStoryCreateTap: @escaping () -> Void = {}, onRefresh: (@Sendable () async -> Void)? = nil) {
        self.client = client
        self.storyAuthors = storyAuthors
        self.userAvatar = userAvatar
        self.onStoryAuthorTap = onStoryAuthorTap
        self.onStoryCreateTap = onStoryCreateTap
        self.onRefresh = onRefresh
        _viewModel = State(initialValue: FeedViewModel(client: client, pinnedFeed: pinnedFeed, userDID: userDID))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !storyAuthors.isEmpty {
                    StoryStripView(
                        authors: storyAuthors,
                        userAvatar: userAvatar,
                        onAuthorTap: onStoryAuthorTap,
                        onCreateTap: onStoryCreateTap
                    )
                    Divider()
                }

                ForEach($viewModel.galleries) { $gallery in
                    GalleryCardView(gallery: $gallery, client: client, onNavigate: {
                        selectedUri = gallery.uri
                    }, onProfileTap: { did in
                        selectedProfileDid = did
                    }, onHashtagTap: { tag in
                        selectedHashtag = tag
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
            async let feedRefresh: () = viewModel.loadInitial(auth: auth.authContext())
            async let storyRefresh: ()? = onRefresh?()
            _ = await (feedRefresh, storyRefresh)
        }
        .navigationDestination(item: $selectedUri) { uri in
            GalleryDetailView(client: client, galleryUri: uri)
        }
        .navigationDestination(item: $selectedProfileDid) { did in
            ProfileView(client: client, did: did)
        }
        .navigationDestination(item: $selectedHashtag) { tag in
            HashtagFeedView(client: client, tag: tag)
        }
        .task {
            if viewModel.galleries.isEmpty {
                await viewModel.loadInitial(auth: auth.authContext())
            }
        }
    }
}

import SwiftUI

struct FeedView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @State private var prefsViewModel: FeedPreferencesViewModel
    @State private var storyViewModel: StoryStripViewModel
    @State private var showStoryViewer = false
    @State private var storyViewerStartIndex = 0
    @State private var showStoryCreate = false
    @State private var deepLinkProfileDid: String?
    @State private var deepLinkGalleryUri: String?
    @State private var deepLinkStoryAuthor: GrainStoryAuthor?

    let client: XRPCClient
    @Binding var pendingDeepLink: DeepLink?
    @Binding var showCreate: Bool

    init(client: XRPCClient, pendingDeepLink: Binding<DeepLink?> = .constant(nil), showCreate: Binding<Bool> = .constant(false)) {
        self.client = client
        _pendingDeepLink = pendingDeepLink
        _showCreate = showCreate
        _prefsViewModel = State(initialValue: FeedPreferencesViewModel(client: client))
        _storyViewModel = State(initialValue: StoryStripViewModel(client: client))
    }

    var body: some View {
        NavigationStack {
            ForEach(prefsViewModel.pinnedFeeds) { feed in
                if feed.id == prefsViewModel.selectedFeedId {
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
                        onRefresh: { [storyStatusCache] in
                            await storyViewModel.load(auth: auth.authContext(), storyStatusCache: storyStatusCache)
                        },
                        prefsViewModel: prefsViewModel
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    leadingToolbarContent
                }
                ToolbarItem(placement: .topBarTrailing) {
                    trailingToolbarContent
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .task {
                await prefsViewModel.loadIfNeeded(auth: auth.authContext())
                await storyViewModel.load(auth: auth.authContext(), storyStatusCache: storyStatusCache)
            }
            .onAppear {
                Task { await prefsViewModel.refresh(auth: auth.authContext()) }
            }
            .customFullScreenCover(isPresented: $showStoryViewer) {
                StoryViewer(
                    authors: storyViewModel.authors,
                    startIndex: storyViewerStartIndex,
                    client: client,
                    onProfileTap: { did in
                        showStoryViewer = false
                        deepLinkProfileDid = did
                    },
                    onDismiss: { showStoryViewer = false }
                )
            }
            .sheet(isPresented: $showStoryCreate) {
                StoryCreateView(client: client) {
                    Task { await storyViewModel.load(auth: auth.authContext()) }
                }
            }
            .navigationDestination(item: $deepLinkProfileDid) { did in
                ProfileView(client: client, did: did)
            }
            .navigationDestination(item: $deepLinkGalleryUri) { uri in
                GalleryDetailView(client: client, galleryUri: uri)
            }
            .fullScreenCover(item: $deepLinkStoryAuthor) { author in
                StoryViewer(
                    authors: [author],
                    client: client,
                    onProfileTap: { did in
                        deepLinkStoryAuthor = nil
                        deepLinkProfileDid = did
                    },
                    onDismiss: { deepLinkStoryAuthor = nil }
                )
                .environment(auth)
            }
            .task {
                consumeDeepLink()
            }
            .onChange(of: pendingDeepLink) {
                consumeDeepLink()
            }
        }
    }

    @ViewBuilder
    private var leadingToolbarContent: some View {
        Menu {
            ForEach(prefsViewModel.pinnedFeeds) { feed in
                Button {
                    prefsViewModel.selectedFeedId = feed.id
                } label: {
                    if feed.id == prefsViewModel.selectedFeedId {
                        Label(feed.label, systemImage: "checkmark")
                    } else {
                        Text(feed.label)
                    }
                }
            }

            if !PinnedFeed.defaults.contains(where: { $0.id == prefsViewModel.selectedFeedId }) {
                Divider()
                Button(role: .destructive) {
                    Task {
                        await prefsViewModel.unpinFeed(prefsViewModel.selectedFeedId, auth: auth.authContext())
                    }
                } label: {
                    Label("Unpin", systemImage: "pin.slash")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(prefsViewModel.selectedFeedLabel)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if prefsViewModel.pinnedFeeds.count > 1 {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .fixedSize()
                }
            }
            .frame(maxWidth: 200, alignment: .leading)
            .foregroundColor(.primary)
        }
        .tint(.primary)
    }

    @ViewBuilder
    private var trailingToolbarContent: some View {
        Button {
            showCreate = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }

    private func consumeDeepLink() {
        guard let link = pendingDeepLink else { return }
        pendingDeepLink = nil
        switch link {
        case .profile(let did):
            deepLinkProfileDid = did
        case .gallery:
            deepLinkGalleryUri = link.galleryUri
        case .story(let did, _):
            Task { await openStoryDeepLink(did: did) }
        }
    }

    private func openStoryDeepLink(did: String) async {
        do {
            let response = try await client.getStories(actor: did, auth: auth.authContext())
            let count = response.stories.count
            if count > 0, let creator = response.stories.first?.creator {
                deepLinkStoryAuthor = GrainStoryAuthor(
                    profile: creator,
                    storyCount: count,
                    latestAt: response.stories.first?.createdAt ?? ""
                )
            } else {
                // Story expired — fall back to profile
                deepLinkProfileDid = did
            }
        } catch {
            // Fall back to profile on error
            deepLinkProfileDid = did
        }
    }

}

private struct FeedTabContent: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: FeedViewModel
    @State private var selectedUri: String?
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?
    @State private var selectedLocation: LocationDestination?
    @State private var deletedGalleryUri: String?
    @State private var zoomState = ImageZoomState()
    @State private var cardStoryAuthor: GrainStoryAuthor?
    let client: XRPCClient
    let storyAuthors: [GrainStoryAuthor]
    let userAvatar: String?
    let onStoryAuthorTap: (GrainStoryAuthor, Int) -> Void
    let onStoryCreateTap: () -> Void
    let onRefresh: (@Sendable () async -> Void)?
    let prefsViewModel: FeedPreferencesViewModel

    init(client: XRPCClient, pinnedFeed: PinnedFeed, userDID: String? = nil, storyAuthors: [GrainStoryAuthor] = [], userAvatar: String? = nil, onStoryAuthorTap: @escaping (GrainStoryAuthor, Int) -> Void = { _, _ in }, onStoryCreateTap: @escaping () -> Void = {}, onRefresh: (@Sendable () async -> Void)? = nil, prefsViewModel: FeedPreferencesViewModel) {
        self.client = client
        self.storyAuthors = storyAuthors
        self.userAvatar = userAvatar
        self.onStoryAuthorTap = onStoryAuthorTap
        self.onStoryCreateTap = onStoryCreateTap
        self.onRefresh = onRefresh
        self.prefsViewModel = prefsViewModel
        _viewModel = State(initialValue: FeedViewModel(client: client, pinnedFeed: pinnedFeed, userDID: userDID))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                StoryStripView(
                    authors: storyAuthors,
                    userAvatar: userAvatar,
                    onAuthorTap: onStoryAuthorTap,
                    onAuthorLongPress: { did in selectedProfileDid = did },
                    onCreateTap: onStoryCreateTap
                )

                ForEach($viewModel.galleries) { $gallery in
                    GalleryCardView(gallery: $gallery, client: client, onNavigate: {
                        selectedUri = gallery.uri
                    }, onProfileTap: { did in
                        selectedProfileDid = did
                    }, onHashtagTap: { tag in
                        selectedHashtag = tag
                    }, onLocationTap: { h3, name in
                        selectedLocation = LocationDestination(h3Index: h3, name: name)
                    }, onStoryTap: { author in
                        cardStoryAuthor = author
                    })
                    .onAppear {
                        if gallery.id == viewModel.galleries.last?.id {
                            Task { await viewModel.loadMore(auth: auth.authContext()) }
                        }
                    }
                }

                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                }
            }
        }
        .environment(zoomState)
        .modifier(ImageZoomOverlay(zoomState: zoomState))
        .refreshable {
            let auth = auth.authContext()
            async let feed: () = viewModel.loadInitial(auth: auth)
            async let stories: ()? = onRefresh?()
            async let prefs: () = prefsViewModel.refresh(auth: auth)
            _ = await (feed, stories, prefs)
        }
        .navigationDestination(item: $selectedUri) { uri in
            GalleryDetailView(client: client, galleryUri: uri, deletedGalleryUri: $deletedGalleryUri)
        }
        .navigationDestination(item: $selectedProfileDid) { did in
            ProfileView(client: client, did: did)
        }
        .navigationDestination(item: $selectedHashtag) { tag in
            HashtagFeedView(client: client, tag: tag)
        }
        .navigationDestination(item: $selectedLocation) { loc in
            LocationFeedView(client: client, h3Index: loc.h3Index, locationName: loc.name)
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
        .task {
            if viewModel.galleries.isEmpty {
                await viewModel.loadInitial(auth: auth.authContext())
            }
        }
        .onChange(of: deletedGalleryUri) { _, uri in
            if let uri {
                viewModel.galleries.removeAll { $0.uri == uri }
                deletedGalleryUri = nil
            }
        }
    }
}

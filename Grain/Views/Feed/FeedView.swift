import Nuke
import SwiftUI

struct FeedView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @Environment(ViewedStoryStorage.self) private var viewedStories
    @State private var prefsViewModel: FeedPreferencesViewModel
    @State private var storyViewModel: StoryStripViewModel
    @State private var storyViewerDid: String?
    @State private var showStoryCreate = false
    @State private var deepLinkProfileDid: String?
    @State private var deepLinkGalleryUri: String?
    @State private var deepLinkStoryAuthor: GrainStoryAuthor?
    @State private var showFeedsManagement = false

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
        let storySortVersion = storyViewModel.version
        NavigationStack {
            ForEach(prefsViewModel.pinnedFeeds) { feed in
                if feed.id == prefsViewModel.selectedFeedId {
                    FeedTabContent(
                        client: client,
                        pinnedFeed: feed,
                        userDID: auth.userDID,
                        storyAuthors: storyViewModel.authors,
                        storySortVersion: storySortVersion,
                        userAvatar: auth.userAvatar,
                        onStoryAuthorTap: { author, _ in
                            storyViewerDid = author.profile.did
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
            .navigationDestination(isPresented: $showFeedsManagement) {
                FeedsManagementView(prefsViewModel: prefsViewModel, client: client)
            }
            .task {
                guard !isPreview else { return }
                await prefsViewModel.loadIfNeeded(auth: auth.authContext())
                await storyViewModel.load(auth: auth.authContext(), storyStatusCache: storyStatusCache)
            }
            .onAppear {
                Task { await prefsViewModel.refresh(auth: auth.authContext()) }
            }
            .onChange(of: storyViewerDid) {
                if storyViewerDid == nil {
                    storyViewModel.invalidate()
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { storyViewerDid != nil },
                set: { if !$0 { storyViewerDid = nil } }
            )) {
                if let did = storyViewerDid {
                    StoryViewer(
                        authors: storyViewModel.authors,
                        startAuthorDid: did,
                        client: client,
                        onProfileTap: { profileDid in
                            storyViewerDid = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                deepLinkProfileDid = profileDid
                            }
                        },
                        onDismiss: {
                            storyViewerDid = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showStoryCreate) {
                StoryCreateView(client: client) {
                    Task { await storyViewModel.load(auth: auth.authContext(), storyStatusCache: storyStatusCache) }
                }
            }
            .navigationDestination(item: $deepLinkProfileDid) { did in
                ProfileView(client: client, did: did)
            }
            .navigationDestination(item: $deepLinkGalleryUri) { uri in
                GalleryDetailView(client: client, galleryUri: uri)
            }
            .sheet(isPresented: $showCreate) {
                NavigationStack {
                    CreateGalleryView(client: client) {
                        showCreate = false
                    }
                }
            }
            .fullScreenCover(item: $deepLinkStoryAuthor) { author in
                StoryViewer(
                    authors: [author],
                    client: client,
                    onProfileTap: { did in
                        deepLinkStoryAuthor = nil
                        deepLinkProfileDid = did
                    },
                    onDismiss: {
                        deepLinkStoryAuthor = nil
                        storyViewModel.invalidate()
                    }
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

            Divider()
            Button {
                showFeedsManagement = true
            } label: {
                Label("My Feeds", systemImage: "list.bullet")
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
        case let .profile(did):
            deepLinkProfileDid = did
        case .gallery:
            deepLinkGalleryUri = link.galleryUri
        case let .story(did, _):
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
                    latestAt: response.stories.last?.createdAt ?? ""
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: FeedViewModel
    @State private var selectedUri: String?
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?
    @State private var selectedLocation: LocationDestination?
    @State private var deletedGalleryUri: String?
    @State private var zoomState = ImageZoomState()
    @State private var cardStoryAuthor: GrainStoryAuthor?
    @AppStorage("privacy.showSuggestedUsers") private var showSuggestedUsers = true
    @State private var suggestedFollows: [SuggestedItem] = []
    @State private var suggestedLoaded = false
    @State private var lastLoadTime: Date = .now
    @State private var feedPrefetcher = ImagePrefetcher()
    let client: XRPCClient
    let storyAuthors: [GrainStoryAuthor]
    var storySortVersion: Int = 0
    let userAvatar: String?
    let onStoryAuthorTap: (GrainStoryAuthor, Int) -> Void
    let onStoryCreateTap: () -> Void
    let onRefresh: (@Sendable () async -> Void)?
    let prefsViewModel: FeedPreferencesViewModel

    init(
        client: XRPCClient,
        pinnedFeed: PinnedFeed,
        userDID: String? = nil,
        storyAuthors: [GrainStoryAuthor] = [],
        storySortVersion: Int = 0,
        userAvatar: String? = nil,
        onStoryAuthorTap: @escaping (GrainStoryAuthor, Int) -> Void = { _, _ in },
        onStoryCreateTap: @escaping () -> Void = {},
        onRefresh: (@Sendable () async -> Void)? = nil,
        prefsViewModel: FeedPreferencesViewModel
    ) {
        self.client = client
        self.storyAuthors = storyAuthors
        self.storySortVersion = storySortVersion
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
                    userDid: auth.userDID,
                    userAvatar: userAvatar,
                    sortVersion: storySortVersion,
                    onAuthorTap: onStoryAuthorTap,
                    onAuthorLongPress: { did in selectedProfileDid = did },
                    onCreateTap: onStoryCreateTap
                )

                ForEach(Array($viewModel.galleries.enumerated()), id: \.element.id) { index, $gallery in
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
                        // Trigger loadMore when 5 items from the end
                        let remaining = viewModel.galleries.count - index
                        if remaining <= 5 {
                            Task { await viewModel.loadMore(auth: auth.authContext()) }
                        }
                        // Prefetch first image of next 3 galleries
                        let input = viewModel.galleries.map { g in
                            (firstThumb: g.items?.first?.thumb, firstFullsize: g.items?.first?.fullsize)
                        }
                        let plan = ImagePrefetchPlanning.feedPrefetchRequests(galleries: input, currentIndex: index)
                        feedPrefetcher.startPrefetching(with: plan.all)
                    }

                    if index == 4, showSuggestedUsers {
                        SuggestedFollowsView(client: client, suggestions: $suggestedFollows, onProfileTap: { did in
                            selectedProfileDid = did
                        })
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
            let auth = await auth.authContext()
            async let feed: () = viewModel.loadInitial(auth: auth)
            async let stories: ()? = onRefresh?()
            async let prefs: () = prefsViewModel.refresh(auth: auth)
            _ = await (feed, stories, prefs)
            lastLoadTime = .now
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
            guard !isPreview else {
                #if DEBUG
                    viewModel.galleries = PreviewData.galleries
                #endif
                return
            }
            if viewModel.galleries.isEmpty {
                await viewModel.loadInitial(auth: auth.authContext())
                lastLoadTime = .now
            }
            if showSuggestedUsers, !suggestedLoaded, let did = auth.userDID {
                do {
                    let response = try await client.getSuggestedFollows(actor: did, auth: auth.authContext())
                    suggestedFollows = response.items ?? []
                } catch {}
                suggestedLoaded = true
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active, Date.now.timeIntervalSince(lastLoadTime) > 300 {
                Task {
                    await viewModel.loadInitial(auth: auth.authContext())
                    lastLoadTime = .now
                }
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

#Preview {
    FeedView(client: .preview)
        .previewEnvironments()
}

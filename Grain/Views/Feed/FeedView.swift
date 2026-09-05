import Nuke
import os
import SwiftUI

private let launchSignposter = OSSignposter(subsystem: "social.grain.grain", category: "AppLaunch")

struct FeedView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @Environment(ViewedStoryStorage.self) private var viewedStories
    @State private var prefsViewModel: FeedPreferencesViewModel
    @State private var storyViewModel: StoryStripViewModel
    @State private var storyViewerDid: String?
    @Binding var showStoryCreate: Bool
    @Environment(Router.self) private var router
    /// Set by the gallery detail screen when it deletes what it was showing.
    @State private var deletedGalleryUri: String?
    @State private var deepLinkStoryAuthor: GrainStoryAuthor?
    @State private var deepLinkStory: GrainStory?
    @State private var showFeedsManagement = false
    @State private var feedRefreshID = UUID()

    let client: XRPCClient
    @Binding var pendingDeepLink: DeepLink?
    @Binding var showCreate: Bool

    init(
        client: XRPCClient,
        pendingDeepLink: Binding<DeepLink?> = .constant(nil),
        showCreate: Binding<Bool> = .constant(false),
        showStoryCreate: Binding<Bool> = .constant(false)
    ) {
        self.client = client
        _pendingDeepLink = pendingDeepLink
        _showCreate = showCreate
        _showStoryCreate = showStoryCreate
        _prefsViewModel = State(initialValue: FeedPreferencesViewModel(client: client))
        _storyViewModel = State(initialValue: StoryStripViewModel(client: client))
    }

    var body: some View {
        @Bindable var router = router
        let storySortVersion = storyViewModel.version
        NavigationStack(path: $router.path) {
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
                            await storyViewModel.load(auth: auth.authContext(), storyStatusCache: storyStatusCache, viewedStories: viewedStories)
                        },
                        prefsViewModel: prefsViewModel,
                        deletedGalleryUri: $deletedGalleryUri
                    )
                    .id(feedRefreshID)
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
                let prefsSpid = launchSignposter.makeSignpostID()
                let prefsState = launchSignposter.beginInterval("FeedPrefsLoad", id: prefsSpid)
                await prefsViewModel.loadIfNeeded(auth: auth.authContext())
                launchSignposter.endInterval("FeedPrefsLoad", prefsState)
                launchSignposter.emitEvent("FeedPrefsReady")
                await storyViewModel.load(auth: auth.authContext(), storyStatusCache: storyStatusCache, viewedStories: viewedStories)
            }
            .onAppear {
                Task { await prefsViewModel.refresh(auth: auth.authContext()) }
            }
            .onChange(of: storyViewerDid) {
                if storyViewerDid == nil {
                    storyViewModel.invalidate()
                    Task { await storyViewModel.load(auth: auth.authContext(), storyStatusCache: storyStatusCache, viewedStories: viewedStories) }
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { storyViewerDid != nil },
                set: {
                    if !$0 {
                        storyViewerDid = nil
                    }
                }
            )) {
                if let did = storyViewerDid {
                    StoryViewer(
                        authors: storyViewModel.authors,
                        startAuthorDid: did,
                        client: client,
                        onProfileTap: { profileDid in
                            storyViewerDid = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                router.push(.profile(did: profileDid))
                            }
                        },
                        onDismiss: {
                            storyViewerDid = nil
                        }
                    )
                }
            }
            .fullScreenCover(isPresented: $showStoryCreate) {
                StoryCreateView(client: client) {
                    Task { await storyViewModel.load(auth: auth.authContext(), storyStatusCache: storyStatusCache, viewedStories: viewedStories) }
                }
            }
            .navigationDestination(for: Route.self) { route in
                RouteDestination(route: route, client: client, deletedGalleryUri: $deletedGalleryUri)
            }
            // Applied outside `navigationDestination` so pushed screens see the
            // router too, not just the content sitting at the root of the stack.
            .environment(router)
            .sheet(isPresented: $showCreate) {
                NavigationStack {
                    CreateGalleryView(client: client) {
                        showCreate = false
                        feedRefreshID = UUID()
                    }
                }
                .tint(Color.accentColor)
            }
            .fullScreenCover(item: $deepLinkStoryAuthor) { author in
                StoryViewer(
                    authors: [author],
                    client: client,
                    onProfileTap: { did in
                        deepLinkStoryAuthor = nil
                        router.push(.profile(did: did))
                    },
                    onDismiss: {
                        deepLinkStoryAuthor = nil
                        storyViewModel.invalidate()
                    }
                )
                .environment(auth)
            }
            .fullScreenCover(item: $deepLinkStory) { story in
                StoryViewer(
                    authors: [GrainStoryAuthor(
                        profile: story.creator,
                        storyCount: 1,
                        latestAt: story.createdAt
                    )],
                    initialStories: [story],
                    client: client,
                    onProfileTap: { did in
                        deepLinkStory = nil
                        router.push(.profile(did: did))
                    },
                    onDismiss: { deepLinkStory = nil }
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
                Label("My feeds", systemImage: "list.bullet")
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
        .accessibilityLabel("Create gallery")
    }

    private func consumeDeepLink() {
        guard let link = pendingDeepLink else { return }
        pendingDeepLink = nil

        // A deep-linked destination may already be on screen — the user opened a
        // gallery link, backgrounded the app, then opened a second one. Assigning
        // the path replaces whatever is showing in one step. This used to need a
        // pop followed by a 0.35s wait, because `navigationDestination(item:)`
        // won't re-push when its value swaps straight from one non-nil to another.
        deepLinkStoryAuthor = nil
        deepLinkStory = nil
        present(link)
    }

    private func present(_ link: DeepLink) {
        if let route = link.route {
            router.replace(with: [route])
            return
        }
        // Stories present over the stack rather than joining it.
        if case let .story(did, rkey) = link {
            Task { await openStoryDeepLink(did: did, rkey: rkey) }
        }
    }

    private func openStoryDeepLink(did: String, rkey: String) async {
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
                // Story expired — fetch the specific story
                let storyUri = "at://\(did)/social.grain.story/\(rkey)"
                if let story = try await client.getStory(uri: storyUri, auth: auth.authContext()).story {
                    deepLinkStory = story
                } else {
                    router.push(.profile(did: did))
                }
            }
        } catch {
            router.push(.profile(did: did))
        }
    }
}

/// Pulled out of `FeedTabContent` so that `isLoading` is read here instead of in
/// the body holding the `LazyVStack`. Reading it up there made every page fetch
/// toggle it twice and re-evaluate every instantiated card body — measured at
/// 6.4 body evaluations per card appearance during a scroll. `@Observable`
/// scopes the dependency to whichever body actually touches the property.
struct FeedLoadingFooter: View {
    let viewModel: FeedViewModel

    var body: some View {
        if viewModel.isLoading {
            ProgressView()
                .padding()
        }
    }
}

struct FeedTabContent: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: FeedViewModel
    @Environment(Router.self) private var router
    @Binding var deletedGalleryUri: String?
    @State private var zoomState = ImageZoomState()
    @State private var modals = GalleryCardModals()
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
        prefsViewModel: FeedPreferencesViewModel,
        deletedGalleryUri: Binding<String?> = .constant(nil)
    ) {
        self.client = client
        self.storyAuthors = storyAuthors
        self.storySortVersion = storySortVersion
        self.userAvatar = userAvatar
        self.onStoryAuthorTap = onStoryAuthorTap
        self.onStoryCreateTap = onStoryCreateTap
        self.onRefresh = onRefresh
        self.prefsViewModel = prefsViewModel
        _deletedGalleryUri = deletedGalleryUri
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
                    onAuthorLongPress: { did in router.push(.profile(did: did)) },
                    onCreateTap: onStoryCreateTap
                )

                ForEach(Array($viewModel.galleries.enumerated()), id: \.element.id) { index, $gallery in
                    let isOwner = gallery.creator.did == auth.userDID
                    let reportAction: (() -> Void)? = !isOwner ? {
                        modals.report = gallery
                    } : nil
                    let deleteAction: (() -> Void)? = isOwner ? {
                        modals.confirmDelete(gallery.uri)
                    } : nil
                    GalleryCardView(gallery: $gallery, client: client, onCommentTap: {
                        modals.commentUri = gallery.uri
                    }, onStoryTap: { author in
                        modals.storyAuthor = author
                    }, onReport: reportAction, onDelete: deleteAction)
                        .onAppear {
                            // Trigger loadMore when 5 items from the end
                            let remaining = viewModel.galleries.count - index
                            if remaining <= 5 {
                                Task { await viewModel.loadMore(auth: auth.authContext()) }
                            }
                            // Prefetch first image of next 3 galleries
                            let input = viewModel.galleries.map { gallery in
                                (firstThumb: gallery.items?.first?.thumb, firstFullsize: gallery.items?.first?.fullsize)
                            }
                            let plan = ImagePrefetchPlanning.feedPrefetchRequests(galleries: input, currentIndex: index)
                            feedPrefetcher.startPrefetching(with: plan.all)
                        }

                    if index == 4, showSuggestedUsers {
                        SuggestedFollowsView(client: client, suggestions: $suggestedFollows, onProfileTap: { did in
                            router.push(.profile(did: did))
                        })
                    }
                }

                FeedLoadingFooter(viewModel: viewModel)
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
        .galleryCardModals(
            client: client,
            modals: modals,
            onCommentCountChanged: { uri, count in
                if let idx = viewModel.galleries.firstIndex(where: { $0.uri == uri }) {
                    viewModel.galleries[idx].commentCount = count
                }
            },
            onDeleted: { uri in viewModel.galleries.removeAll { $0.uri == uri } }
        )
        .task {
            guard !isPreview else {
                #if DEBUG
                    viewModel.galleries = PreviewData.galleries
                #endif
                return
            }
            if !viewModel.hasFetchedInitial {
                let initialSpid = launchSignposter.makeSignpostID()
                let initialState = launchSignposter.beginInterval("FeedInitialLoad", id: initialSpid)
                launchSignposter.emitEvent("FeedInitialLoadStart")
                await viewModel.loadInitial(auth: auth.authContext())
                launchSignposter.endInterval("FeedInitialLoad", initialState)
                launchSignposter.emitEvent("FeedFirstContent")
                LaunchMetrics.endTFPOnce()
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
    FeedView(client: XRPCClient(baseURL: AuthManager.serverURL))
        .environment(AuthManager())
        .environment(StoryStatusCache())
        .environment(ViewedStoryStorage())
        .environment(LabelDefinitionsCache())
}

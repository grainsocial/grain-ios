import SwiftUI

struct SearchView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @Environment(ViewedStoryStorage.self) private var viewedStories
    @State private var viewModel: SearchViewModel
    @State private var searchText = ""
    @Environment(Router.self) private var router
    @State private var zoomState = ImageZoomState()
    @State private var modals = GalleryCardModals()
    @State private var recentSearches: RecentSearchStorage
    @State private var searchIsPresented = false
    /// The search behind the keystrokes. Cancelled and restarted on each one,
    /// so only the text that stood still for a beat reaches the network.
    @State private var searchTask: Task<Void, Never>?
    let client: XRPCClient

    private static let debounce: Duration = .milliseconds(300)

    /// `viewModel` is injectable the same way `NotificationsView`'s is, so the
    /// results state can be built without going through the search field.
    init(client: XRPCClient, viewModel: SearchViewModel? = nil) {
        self.client = client
        _viewModel = State(initialValue: viewModel ?? SearchViewModel(client: client))
        _recentSearches = State(initialValue: RecentSearchStorage())
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            Group {
                if viewModel.searchText.isEmpty {
                    // Recents belong to the field, so they show while it is
                    // active and give way to explore once it lets go — the
                    // same tab is a place to browse when you have nothing to
                    // type, and a place to type when you do.
                    if searchIsPresented, !recentSearches.profiles.isEmpty || !recentSearches.textSearches.isEmpty {
                        recentSearchesView
                    } else {
                        ExploreView(client: client)
                    }
                } else if viewModel.isSearching, resultsAreEmpty {
                    // In progress with nothing yet: the shape of what is
                    // coming, rather than a blank or the last query's answer.
                    ScrollView {
                        DelayedSkeleton {
                            if viewModel.selectedTab == .galleries {
                                SkeletonGalleryCards()
                            } else {
                                SkeletonProfileRows()
                            }
                        }
                        .padding(.top)
                    }
                } else if viewModel.hasSearched, resultsAreEmpty {
                    ContentUnavailableView.search(text: viewModel.searchText)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            switch viewModel.selectedTab {
                            case .galleries:
                                ForEach($viewModel.galleryResults) { $gallery in
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
                                }
                            case .profiles:
                                ForEach(viewModel.profileResults) { profile in
                                    Button {
                                        recentSearches.addProfile(did: profile.did, displayName: profile.displayName, handle: profile.handle, avatar: profile.avatar)
                                        router.push(.profile(did: profile.did))
                                    } label: {
                                        HStack {
                                            StoryRingView(
                                                hasStory: storyStatusCache.hasStory(for: profile.did),
                                                viewed: profile.did != auth.userDID && viewedStories.hasViewedAll(did: profile.did, storyStatusCache: storyStatusCache),
                                                size: 40
                                            ) {
                                                AvatarView(url: profile.avatar, size: 40)
                                            }
                                            .profileContextMenu(
                                                handle: profile.handle,
                                                hasStory: storyStatusCache.hasStory(for: profile.did),
                                                onViewProfile: {
                                                    recentSearches.addProfile(did: profile.did, displayName: profile.displayName, handle: profile.handle, avatar: profile.avatar)
                                                    router.push(.profile(did: profile.did))
                                                },
                                                onViewStory: {
                                                    if let author = storyStatusCache.author(for: profile.did) {
                                                        modals.storyAuthor = author
                                                    }
                                                }
                                            )
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
            .navigationTitle("Explore")
            // Inline, with the field always in the bar: the large title and a
            // field that hid on scroll collapsed and re-expanded as the grid
            // crossed the threshold, and the header jittered at the top.
            // Matches the Android tab, where the field is a fixed bar.
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                RouteDestination(route: route, client: client)
            }
            // Applied outside `navigationDestination` so pushed screens see the
            // router too, not just the content sitting at the root of the stack.
            .environment(router)
            .searchable(
                text: $searchText,
                isPresented: $searchIsPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search galleries and profiles"
            )
            // Scopes only once there is text: an empty field is for recents
            // and explore, and two tabs over those asked a question nobody
            // had typed yet.
            .searchScopes($viewModel.selectedTab, activation: .onTextEntry) {
                ForEach(SearchViewModel.SearchTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .onSubmit(of: .search) {
                recentSearches.addTextSearch(searchText)
                searchTask?.cancel()
                Task { await viewModel.search(auth: auth.authContext()) }
            }
            .onChange(of: searchText) {
                viewModel.searchText = searchText
                searchTask?.cancel()
                guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    viewModel.clearResults()
                    return
                }
                // As you type, once the text holds still — the way the
                // Android tab does it. Submit still runs it at once.
                searchTask = Task {
                    try? await Task.sleep(for: Self.debounce)
                    guard !Task.isCancelled else { return }
                    await viewModel.search(auth: auth.authContext())
                }
            }
            .onChange(of: viewModel.selectedTab) {
                if !viewModel.searchText.isEmpty {
                    Task { await viewModel.search(auth: auth.authContext()) }
                }
            }
            .galleryCardModals(
                client: client,
                modals: modals,
                onCommentCountChanged: { uri, count in
                    if let idx = viewModel.galleryResults.firstIndex(where: { $0.uri == uri }) {
                        viewModel.galleryResults[idx].commentCount = count
                    }
                },
                onDeleted: { uri in viewModel.galleryResults.removeAll { $0.uri == uri } }
            )
        }
    }

    private var resultsAreEmpty: Bool {
        switch viewModel.selectedTab {
        case .galleries: viewModel.galleryResults.isEmpty
        case .profiles: viewModel.profileResults.isEmpty
        }
    }

    private var recentSearchesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !recentSearches.profiles.isEmpty {
                    Text("Recent searches")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(recentSearches.profiles) { profile in
                                VStack(spacing: 6) {
                                    AvatarView(url: profile.avatar, size: 76)
                                        .padding(4)
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                recentSearches.removeProfile(profile.did)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 18))
                                                    .foregroundStyle(.white, Color.accentColor)
                                            }
                                            .accessibilityLabel("Remove \(profile.displayName ?? profile.handle ?? "") from recent")
                                        }

                                    Text(profile.displayName ?? profile.handle ?? "")
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(width: 72)
                                }
                                .onTapGesture {
                                    router.push(.profile(did: profile.did))
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if !recentSearches.textSearches.isEmpty {
                    ForEach(recentSearches.textSearches) { recent in
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                                .accessibilityHidden(true)
                            Text(recent.query)
                                .font(.subheadline)
                            Spacer()
                            Button {
                                recentSearches.removeTextSearch(recent.query)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.primary)
                            }
                            .accessibilityLabel("Remove search")
                        }
                        .padding(.horizontal)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            searchText = recent.query
                            viewModel.searchText = recent.query
                            searchIsPresented = true
                            Task { await viewModel.search(auth: auth.authContext()) }
                        }
                    }
                }
            }
            .padding(.top)
        }
    }
}

#Preview {
    SearchView(client: .preview)
        .previewEnvironments()
        .frame(maxHeight: .infinity, alignment: .top)
}

/// The shape of a gallery card, twice over, while a search is answering.
private struct SkeletonGalleryCards: View {
    var body: some View {
        VStack(spacing: 24) {
            ForEach(0 ..< 2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        SkeletonCircle(size: 36)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBar(width: 120, height: 12)
                            SkeletonBar(width: 80, height: 10)
                        }
                    }
                    .padding(.horizontal)
                    Rectangle()
                        .fill(Color(.tertiarySystemFill))
                        .shimmering()
                        .aspectRatio(4 / 3, contentMode: .fit)
                    SkeletonBar(width: 200, height: 12)
                        .padding(.horizontal)
                }
            }
        }
    }
}

/// The shape of a profile row, a few times over.
private struct SkeletonProfileRows: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0 ..< 5, id: \.self) { _ in
                HStack(spacing: 12) {
                    SkeletonCircle(size: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBar(width: 140, height: 12)
                        SkeletonBar(width: 90, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
    }
}

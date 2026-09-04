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
    let client: XRPCClient

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
                    if recentSearches.profiles.isEmpty, recentSearches.textSearches.isEmpty {
                        ContentUnavailableView("Search", systemImage: "magnifyingglass", description: Text("Search for galleries and profiles"))
                    } else {
                        recentSearchesView
                    }
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
            .navigationTitle("Search")
            .searchable(text: $searchText, isPresented: $searchIsPresented, prompt: "Search galleries & profiles")
            .searchScopes($viewModel.selectedTab, activation: .onSearchPresentation) {
                ForEach(SearchViewModel.SearchTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .onSubmit(of: .search) {
                recentSearches.addTextSearch(searchText)
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

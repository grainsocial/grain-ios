import SwiftUI

struct SearchView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @Environment(ViewedStoryStorage.self) private var viewedStories
    @State private var viewModel: SearchViewModel
    @State private var searchText = ""
    @State private var searchNavigationUri: String?
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?
    @State private var selectedLocation: LocationDestination?
    @State private var zoomState = ImageZoomState()
    @State private var cardStoryAuthor: GrainStoryAuthor?
    @State private var commentSheetUri: String?
    @State private var reportGallery: GrainGallery?
    @State private var deleteGalleryUri: String?
    @State private var showDeleteConfirmation = false
    @State private var recentSearches: RecentSearchStorage
    @State private var searchIsPresented = false
    let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
        _viewModel = State(initialValue: SearchViewModel(client: client))
        _recentSearches = State(initialValue: RecentSearchStorage())
    }

    var body: some View {
        NavigationStack {
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
                                        reportGallery = gallery
                                    } : nil
                                    let deleteAction: (() -> Void)? = isOwner ? {
                                        showDeleteConfirmation = true
                                        deleteGalleryUri = gallery.uri
                                    } : nil
                                    GalleryCardView(gallery: $gallery, client: client, onNavigate: {
                                        searchNavigationUri = gallery.uri
                                    }, onCommentTap: {
                                        commentSheetUri = gallery.uri
                                    }, onProfileTap: { did in
                                        selectedProfileDid = did
                                    }, onHashtagTap: { tag in
                                        selectedHashtag = tag
                                    }, onLocationTap: { h3, name in
                                        selectedLocation = LocationDestination(h3Index: h3, name: name)
                                    }, onStoryTap: { author in
                                        cardStoryAuthor = author
                                    }, onReport: reportAction, onDelete: deleteAction)
                                }
                            case .profiles:
                                ForEach(viewModel.profileResults) { profile in
                                    Button {
                                        recentSearches.addProfile(did: profile.did, displayName: profile.displayName, handle: profile.handle, avatar: profile.avatar)
                                        selectedProfileDid = profile.did
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
                                                    selectedProfileDid = profile.did
                                                },
                                                onViewStory: {
                                                    if let author = storyStatusCache.author(for: profile.did) {
                                                        cardStoryAuthor = author
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
            .navigationDestination(item: $searchNavigationUri) { uri in
                GalleryDetailView(client: client, galleryUri: uri)
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
            .sheet(isPresented: Binding(
                get: { commentSheetUri != nil },
                set: { if !$0 { commentSheetUri = nil } }
            )) {
                if let uri = commentSheetUri {
                    CommentSheetView(
                        client: client,
                        galleryUri: uri,
                        onDismiss: { commentSheetUri = nil },
                        onProfileTap: { did in
                            commentSheetUri = nil
                            selectedProfileDid = did
                        },
                        onHashtagTap: { tag in
                            commentSheetUri = nil
                            selectedHashtag = tag
                        },
                        onStoryTap: { author in
                            commentSheetUri = nil
                            cardStoryAuthor = author
                        },
                        onCommentCountChanged: { count in
                            if let idx = viewModel.galleryResults.firstIndex(where: { $0.uri == uri }) {
                                viewModel.galleryResults[idx].commentCount = count
                            }
                        }
                    )
                }
            }
            .sheet(item: $reportGallery) { gallery in
                ReportView(client: client, subjectUri: gallery.uri, subjectCid: gallery.cid)
            }
            .alert("Delete Gallery?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let uri = deleteGalleryUri {
                        Task {
                            guard let authContext = await auth.authContext() else { return }
                            let rkey = uri.split(separator: "/").last.map(String.init) ?? ""
                            try? await client.deleteRecord(collection: "social.grain.gallery", rkey: rkey, auth: authContext)
                            viewModel.galleryResults.removeAll { $0.uri == uri }
                        }
                        deleteGalleryUri = nil
                    }
                }
                Button("Cancel", role: .cancel) { deleteGalleryUri = nil }
            } message: {
                Text("This will permanently delete this gallery and all its photos.")
            }
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
                                                    .foregroundStyle(.white, Color("AccentColor"))
                                            }
                                            .accessibilityLabel("Remove \(profile.displayName ?? profile.handle ?? "") from recent")
                                        }

                                    Text(profile.displayName ?? profile.handle ?? "")
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(width: 72)
                                }
                                .onTapGesture {
                                    selectedProfileDid = profile.did
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

import Nuke
import NukeUI
import SwiftUI

enum ProfileViewMode: String, CaseIterable {
    case grid, favorites, stories
}

struct ProfileView: View {
    @Namespace private var viewModeNS
    @Namespace private var galleryZoomNS
    @Environment(AuthManager.self) private var auth
    @Environment(ViewedStoryStorage.self) private var viewedStories
    @Environment(LabelDefinitionsCache.self) private var labelDefsCache
    @State private var showStoryViewer = false
    @State private var showStoryCreate = false
    @State private var showAvatarOverlay = false
    @State private var viewModel: ProfileDetailViewModel
    @State private var selectedGallery: ProfileGallerySelection?
    @Environment(Router.self) private var router
    @State private var deletedGalleryUri: String?
    @State private var viewMode: ProfileViewMode = .grid
    /// Everything a swipe between tabs writes per frame lives here, not in
    /// this view's `@State`, so a swipe never re-evaluates this body.
    @State private var pager = ProfilePagerState()
    @Environment(\.displayScale) private var displayScale
    @State private var zoomState = ImageZoomState()
    @State private var cardStoryAuthor: GrainStoryAuthor?
    let client: XRPCClient
    @State private var selectedArchivedStory: GrainStory?
    let actor: String
    var isRoot = false
    @State private var showCopiedToast = false
    @State private var showEditProfile = false

    /// Resolved DID from the loaded profile, or the original actor identifier
    private var did: String {
        viewModel.profile?.did ?? actor
    }

    /// `viewMode` opens the profile on a given tab rather than always on the
    /// grid, which is also how the favorites and stories tabs become reachable
    /// without a tap.
    init(client: XRPCClient, did: String, isRoot: Bool = false, viewMode: ProfileViewMode = .grid) {
        self.client = client
        _viewModel = State(initialValue: ProfileDetailViewModel(client: client))
        _viewMode = State(initialValue: viewMode)
        actor = did
        self.isRoot = isRoot
    }

    var body: some View {
        @Bindable var router = router
        return ZStack {
            if isRoot {
                NavigationStack(path: $router.path) {
                    profileContent
                }
            } else {
                profileContent
            }

            if showAvatarOverlay, let avatar = viewModel.profile?.avatar {
                AvatarOverlay(url: avatar, onDismiss: dismissAvatarOverlay)
                    .ignoresSafeArea()
                    .zIndex(999)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Header & content

extension ProfileView {
    @ViewBuilder
    private func avatarButton(profile: GrainProfileDetailed) -> some View {
        let hasStory = !viewModel.stories.isEmpty
        StoryRingView(
            hasStory: hasStory,
            viewed: did != auth.userDID && viewedStories.hasViewedAll(authorDid: did, latestAt: viewModel.stories.last?.createdAt ?? ""),
            size: 80
        ) {
            AvatarView(url: profile.avatar, size: 80)
                .liquidGlassCircle()
        }
        .overlay(alignment: .bottomTrailing) {
            if did == auth.userDID {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, Color.accentColor)
                    .background(Circle().fill(Color(.systemBackground)).padding(-1))
                    .offset(x: 4, y: 4)
                    .accessibilityHidden(true)
            }
        }
        .padding(4)
        .contentShape(Circle())
        .onTapGesture {
            if did == auth.userDID {
                if hasStory {
                    showStoryViewer = true
                } else {
                    showStoryCreate = true
                }
            } else {
                if hasStory {
                    showStoryViewer = true
                } else if profile.avatar != nil {
                    openAvatarOverlay()
                }
            }
        }
        .profileContextMenu(
            handle: profile.handle,
            hasStory: hasStory,
            onViewStory: hasStory ? { showStoryViewer = true } : nil,
            onAddStory: did == auth.userDID ? { showStoryCreate = true } : nil,
            onViewPhoto: profile.avatar != nil ? { openAvatarOverlay() } : nil,
            showSharingActions: false
        ) {
            StoryRingView(hasStory: hasStory, viewed: false, size: 120) {
                AvatarView(url: profile.avatar, size: 120)
            }
            .padding(6)
        }
    }

    private func handleRow(profile: GrainProfileDetailed) -> some View {
        HStack(spacing: 6) {
            if !viewModel.isBlockHidden, profile.viewer?.followedBy != nil {
                Text("Follows you")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text("@\(profile.handle)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contextMenu {
                    if profile.avatar != nil {
                        Button { openAvatarOverlay() } label: {
                            Label("View profile photo", systemImage: "person.crop.circle")
                        }
                        Divider()
                    }
                    Button { copyText("@\(profile.handle)") } label: {
                        Label("Copy handle", systemImage: "doc.on.doc")
                    }
                    Button { copyText(did) } label: {
                        Label("Copy DID", systemImage: "number")
                    }
                }
        }
    }

    private var profileContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                if let profile = viewModel.profile {
                    VStack(spacing: 12) {
                        // Avatar + stats row
                        HStack(alignment: .center, spacing: 16) {
                            avatarButton(profile: profile)

                            if !viewModel.isBlockHidden {
                                HStack(spacing: 0) {
                                    StatView(count: profile.galleryCount ?? 0, label: "Galleries")
                                        .frame(maxWidth: .infinity)
                                    NavigationLink {
                                        FollowListView(client: client, did: did, mode: .followers)
                                    } label: {
                                        StatView(count: profile.followersCount ?? 0, label: "Followers")
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity)
                                    NavigationLink {
                                        FollowListView(client: client, did: did, mode: .following)
                                    } label: {
                                        StatView(count: profile.followsCount ?? 0, label: "Following")
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        // Name + handle + bio
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName ?? profile.handle)
                                .font(.subheadline.bold())

                            handleRow(profile: profile)

                            if viewModel.isBlockHidden {
                                // Block alert
                                HStack(spacing: 6) {
                                    Image(systemName: "nosign")
                                        .font(.caption)
                                    if profile.viewer?.blocking != nil {
                                        Text("Account blocked")
                                    } else {
                                        Text("This user has blocked you")
                                    }
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.top, 4)
                            } else {
                                if let description = profile.description, !description.isEmpty {
                                    RichTextView(
                                        text: description,
                                        font: .subheadline,
                                        onMentionTap: { did in router.push(.profile(did: did)) },
                                        onHashtagTap: { tag in router.push(.hashtag(tag)) }
                                    )
                                    .padding(.top, 2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                        if !viewModel.isBlockHidden {
                            // Known followers
                            if !viewModel.knownFollowers.isEmpty, did != auth.userDID {
                                NavigationLink {
                                    FollowListView(client: client, did: did, mode: .knownFollowers)
                                } label: {
                                    knownFollowersRow
                                }
                                .buttonStyle(.plain)
                            }

                            // Follow + Germ DM buttons
                            if did != auth.userDID {
                                HStack(spacing: 8) {
                                    followButton(profile: profile)

                                    if let germUrl = germDMUrl(profile: profile) {
                                        Link(destination: germUrl) {
                                            HStack(spacing: 4) {
                                                Image("germ-logo")
                                                    .resizable()
                                                    .frame(width: 14, height: 14)
                                                Text("Germ DM")
                                                    .font(.subheadline.weight(.semibold))
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .buttonBorderShape(.roundedRectangle(radius: 10))
                                .padding(.horizontal)
                            } else {
                                HStack(spacing: 8) {
                                    Button {
                                        showEditProfile = true
                                    } label: {
                                        Text("Edit profile")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)

                                    if let germUrl = germDMUrl(profile: profile) {
                                        Link(destination: germUrl) {
                                            HStack(spacing: 4) {
                                                Image("germ-logo")
                                                    .resizable()
                                                    .frame(width: 14, height: 14)
                                                Text("Germ DM")
                                                    .font(.subheadline.weight(.semibold))
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .buttonBorderShape(.roundedRectangle(radius: 10))
                                .padding(.horizontal)
                            }
                        }

                        // Tabs + grid
                        if !viewModel.isBlockHidden {
                            if did == auth.userDID {
                                ownProfileTabSection
                                    .id("profileTabSection")
                                    // A Bool rather than the live offset: it
                                    // only flips when the edge is crossed, so
                                    // scrolling doesn't touch state per frame.
                                    .onGeometryChange(for: Bool.self) { proxy in
                                        proxy.frame(in: .scrollView).minY < 0
                                    } action: { newValue in
                                        pager.scrolledPastTop = newValue
                                    }
                            } else {
                                galleriesGrid
                            }
                        }
                    } // end if !isBlockHidden (tabs + grid)
                } else if viewModel.error != nil {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "Profile not found",
                            systemImage: "person.slash",
                            description: Text("This user doesn't have a Grain profile yet.")
                        )
                        if let url = URL(string: "https://bsky.app/profile/\(actor)") {
                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.right")
                                    Text("View on Bluesky")
                                }
                                .font(.subheadline.weight(.medium))
                            }
                        }
                    }
                    .padding(.top, 40)
                } else {
                    DelayedSkeleton {
                        ProfileSkeletonView(showsTabBar: did == auth.userDID)
                    }
                }
            }
            // The grids find the viewport through this name; they sit inside
            // the horizontal pager, so `.scrollView` would give them that one.
            .coordinateSpace(.named("profileScroll"))
            .environment(zoomState)
            .modifier(ImageZoomOverlay(zoomState: zoomState))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if did == auth.userDID {
                    if let handle = viewModel.profile?.handle,
                       let profileURL = URL(string: "https://grain.social/profile/\(handle)")
                    {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: profileURL) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .tint(.primary)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView(client: client)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .tint(.primary)
                    }
                } else if let profile = viewModel.profile {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if let profileURL = URL(string: "https://grain.social/profile/\(profile.handle)") {
                                ShareLink(item: profileURL) {
                                    Label("Share profile", systemImage: "square.and.arrow.up")
                                }
                                Button {
                                    UIPasteboard.general.string = profile.handle
                                } label: {
                                    Label("Copy username", systemImage: "at")
                                }
                                Divider()
                            }
                            if !viewModel.isBlockHidden {
                                Button {
                                    Task { await viewModel.toggleMute(auth: auth.authContext()) }
                                } label: {
                                    Label(
                                        profile.viewer?.muted == true ? "Unmute" : "Mute",
                                        systemImage: profile.viewer?.muted == true ? "speaker.wave.2" : "speaker.slash"
                                    )
                                }
                            }
                            Section {
                                Button(role: profile.viewer?.blocking != nil ? nil : .destructive) {
                                    Task { await viewModel.toggleBlock(auth: auth.authContext()) }
                                } label: {
                                    Label(
                                        profile.viewer?.blocking != nil ? "Unblock" : "Block",
                                        systemImage: profile.viewer?.blocking != nil ? "circle" : "nosign"
                                    )
                                }
                            }
                            .tint(profile.viewer?.blocking != nil ? .primary : .red)
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                RouteDestination(route: route, client: client)
            }
            .navigationDestination(item: $selectedGallery) { selection in
                ProfileGalleryFeedView(
                    viewModel: viewModel,
                    client: client,
                    did: did,
                    initialUri: selection.uri,
                    source: selection.source
                )
                // Force a fresh identity per selection so @State (scrollAnchor,
                // didExpand) resets — without this, SwiftUI reuses the prior
                // push's state and lands on the old scroll position.
                .id(selection.uri)
                .navigationTransition(.zoom(sourceID: selection.uri, in: galleryZoomNS))
            }
            .fullScreenCover(isPresented: $showStoryViewer) {
                if let profile = viewModel.profile {
                    StoryViewer(
                        authors: [GrainStoryAuthor(
                            profile: GrainProfile(cid: "", did: did, handle: profile.handle, displayName: profile.displayName, avatar: profile.avatar),
                            storyCount: viewModel.stories.count,
                            latestAt: viewModel.stories.last?.createdAt ?? ""
                        )],
                        client: client,
                        onProfileTap: { did in
                            showStoryViewer = false
                            router.push(.profile(did: did))
                        },
                        onDismiss: { showStoryViewer = false }
                    )
                    .environment(auth)
                }
            }
            .fullScreenCover(item: $cardStoryAuthor) { author in
                StoryViewer(
                    authors: [author],
                    client: client,
                    onProfileTap: { did in
                        cardStoryAuthor = nil
                        router.push(.profile(did: did))
                    },
                    onDismiss: { cardStoryAuthor = nil }
                )
                .environment(auth)
            }
            .fullScreenCover(item: $selectedArchivedStory) { story in
                if let profile = viewModel.profile,
                   viewModel.archivedStories.contains(where: { $0.id == story.id })
                {
                    StoryViewer(
                        authors: [GrainStoryAuthor(
                            profile: GrainProfile(cid: "", did: did, handle: profile.handle, displayName: profile.displayName, avatar: profile.avatar),
                            storyCount: 1,
                            latestAt: story.createdAt
                        )],
                        initialStories: [story],
                        client: client,
                        onProfileTap: { did in
                            selectedArchivedStory = nil
                            router.push(.profile(did: did))
                        },
                        onDismiss: { selectedArchivedStory = nil }
                    )
                    .environment(auth)
                }
            }
            .fullScreenCover(isPresented: $showStoryCreate) {
                StoryCreateView(client: client, onCreated: {
                    Task { await viewModel.load(did: did) }
                })
                .environment(auth)
            }
            .sheet(isPresented: $showEditProfile) {
                NavigationStack {
                    EditProfileView(client: client, onSaved: {
                        showEditProfile = false
                        Task { await viewModel.load(did: did) }
                    })
                }
                .environment(auth)
            }
            .background(Color(.systemBackground))
            .refreshable {
                await viewModel.load(did: actor, viewer: auth.userDID, auth: auth.authContext())
                if viewMode == .favorites {
                    await viewModel.loadFavorites(did: actor, auth: auth.authContext())
                } else if viewMode == .stories {
                    await viewModel.loadStoryArchive(did: actor, auth: auth.authContext())
                }
            }
            // The profile's live stories carry the server's viewed flags, which
            // is how the ring here knows about a story watched on the web.
            .onChange(of: viewModel.stories.map(\.uri), initial: true) {
                viewedStories.absorb(stories: viewModel.stories)
            }
            .task {
                guard !isPreview else {
                    #if DEBUG
                        viewModel.profile = PreviewData.profile
                        viewModel.galleries = PreviewData.galleries
                    #endif
                    return
                }
                if viewModel.profile == nil {
                    await viewModel.load(did: actor, viewer: auth.userDID, auth: auth.authContext())
                }
                // The archive and favorites otherwise only load on a tab change
                // or a pull-to-refresh, so a profile opened straight onto one of
                // those tabs would sit on "No stories yet" indefinitely. Mirrors
                // what `refreshable` above already does.
                if viewMode == .stories {
                    await viewModel.loadStoryArchive(did: actor, auth: auth.authContext())
                } else if viewMode == .favorites {
                    await viewModel.loadFavorites(did: actor, auth: auth.authContext())
                }
            }
            .onChange(of: deletedGalleryUri) { _, uri in
                if let uri {
                    viewModel.galleries.removeAll { $0.uri == uri }
                    deletedGalleryUri = nil
                }
            }
            .alert("Sign in again to block", isPresented: $viewModel.showReauthAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please sign out and back in to enable blocking. This is a one-time step after the update.")
            }
            .overlay(alignment: .center) {
                if showCopiedToast {
                    CopiedCheckmarkToast()
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showCopiedToast)
            .sensoryFeedback(.impact(weight: .medium), trigger: showCopiedToast)
            // Whether by tap or by swipe: fetch what the tab shows, and if
            // the tab bar has gone off the top, bring it back into view.
            .onChange(of: viewMode) { _, mode in
                if mode == .stories {
                    Task { await viewModel.loadStoryArchive(did: did, auth: auth.authContext()) }
                } else if mode == .favorites {
                    Task { await viewModel.loadFavorites(did: did, auth: auth.authContext()) }
                }
                if pager.scrolledPastTop {
                    withAnimation(.smooth(duration: 0.35)) {
                        scrollProxy.scrollTo("profileTabSection", anchor: .top)
                    }
                }
            }
        } // close ScrollViewReader
    }
}

// MARK: - Layout sections

extension ProfileView {
    private func copyText(_ text: String) {
        UIPasteboard.general.string = text
        showCopiedToast = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showCopiedToast = false
        }
    }

    @ViewBuilder
    private var knownFollowersRow: some View {
        let followers = viewModel.knownFollowers
        let displayCount = max(followers.count, 0)
        let names = followers.prefix(2).compactMap { follower -> String? in
            if let name = follower.displayName, !name.isEmpty {
                return name
            }
            return follower.handle
        }
        let othersCount = displayCount - names.count

        HStack(spacing: 6) {
            FacepileView(people: followers)

            // "Followed by X, Y and Z others" text
            Group {
                if names.count == 1, othersCount == 0 {
                    Text("Followed by **\(names[0])**")
                } else if names.count == 2, othersCount == 0 {
                    Text("Followed by **\(names[0])** and **\(names[1])**")
                } else if names.count == 1, othersCount > 0 {
                    Text("Followed by **\(names[0])** and \(othersCount) \(othersCount == 1 ? "other" : "others") you follow")
                } else if names.count >= 2, othersCount > 0 {
                    Text("Followed by **\(names[0])**, **\(names[1])** and \(othersCount) \(othersCount == 1 ? "other" : "others") you follow")
                } else {
                    Text("Followed by \(displayCount) you follow")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private func setViewMode(_ mode: ProfileViewMode) {
        guard mode != viewMode else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            viewMode = mode
        }
    }

    /// Pixels a cell of `size` covers on this screen, for sizing its thumbnail.
    private func pixelSize(for size: CGSize) -> CGSize {
        CGSize(width: size.width * displayScale, height: size.height * displayScale)
    }

    private var ownProfileTabSection: some View {
        // Optional because `scrollPosition(id:)` wants one; a nil never
        // reaches `viewMode`.
        let scrollBinding = Binding<ProfileViewMode?>(
            get: { viewMode },
            set: { newMode in
                guard let newMode, newMode != viewMode else { return }
                viewMode = newMode
            }
        )

        return VStack(spacing: 0) {
            ProfileTabBar(pager: pager, selected: viewMode, onSelect: setViewMode)

            // Native horizontally-paged grids. SwiftUI handles the physics, snapping,
            // and axis disambiguation with the outer vertical ScrollView.
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    page(galleriesGrid, mode: .grid)
                    page(favoritesGrid, mode: .favorites)
                    page(storyArchiveGrid, mode: .stories)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: scrollBinding)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.x
            } action: { _, newValue in
                pager.offsetX = newValue
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if newWidth > 0 {
                    pager.pageWidth = newWidth
                }
            }
            .modifier(ProfilePagerHeight(pager: pager, selected: viewMode))
            .clipped()
        }
    }

    private func page(_ content: some View, mode: ProfileViewMode) -> some View {
        content
            .containerRelativeFrame(.horizontal)
            .contentShape(Rectangle())
            .clipped()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newHeight in
                pager.pageHeights[mode] = newHeight
            }
            .id(mode)
    }

    @ViewBuilder
    private var galleriesGrid: some View {
        if viewModel.galleries.isEmpty, viewModel.isLoading {
            // Header lands before the feed does, so the grid carries its own
            // placeholder for the gap.
            DelayedSkeleton { SkeletonGrid() }
        } else if viewModel.galleries.isEmpty {
            Text("No galleries yet")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else {
            WindowedGrid(items: viewModel.galleries, scrollSpace: "profileScroll") { gallery, cellSize in
                Button {
                    selectedGallery = nil
                    DispatchQueue.main.async {
                        selectedGallery = ProfileGallerySelection(uri: gallery.uri, source: .galleries)
                    }
                } label: {
                    Color.clear
                        .overlay {
                            if let photo = gallery.items?.first {
                                ProfileGridThumbnail(urlString: photo.thumb, pixelSize: pixelSize(for: cellSize))
                            }
                        }
                        .clipped()
                        .contentShape(Rectangle())
                        .overlay {
                            let lr = resolveLabels(gallery.labels, definitions: labelDefsCache.definitions)
                            if lr.action >= .warnMedia {
                                Rectangle().fill(Color(.secondarySystemBackground))
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.caption2)
                                    Text(lr.name)
                                        .font(.system(size: 9))
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if (gallery.items?.count ?? 0) > 1 {
                                Image(systemName: "square.on.square.fill")
                                    .font(.system(size: 14))
                                    .rotationEffect(.degrees(180))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                    .padding(6)
                                    .accessibilityHidden(true)
                            }
                        }
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: gallery.uri, in: galleryZoomNS)
                .onAppear {
                    if gallery.id == viewModel.galleries.last?.id {
                        Task { await viewModel.loadMoreGalleries(did: did, auth: auth.authContext()) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var storyArchiveGrid: some View {
        if viewModel.archivedStories.isEmpty, !viewModel.isLoading {
            Text("No stories yet")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else {
            WindowedGrid(items: viewModel.archivedStories, scrollSpace: "profileScroll") { story, cellSize in
                Button {
                    if let index = viewModel.archivedStories.firstIndex(where: { $0.id == story.id }) {
                        selectedArchivedStory = viewModel.archivedStories[index]
                    }
                } label: {
                    Color.clear
                        .overlay {
                            LazyImage(url: URL(string: story.thumb)) { state in
                                if let image = state.image {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Rectangle().fill(.quaternary)
                                }
                            }
                            .processors([ImageProcessors.Resize(size: pixelSize(for: cellSize), unit: .pixels, contentMode: .aspectFill)])
                        }
                        .clipped()
                        .overlay(alignment: .bottomLeading) {
                            Text(storyDateLabel(story.createdAt))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                                .padding(6)
                        }
                }
                .buttonStyle(.plain)
                .onAppear {
                    if story.id == viewModel.archivedStories.last?.id {
                        Task { await viewModel.loadMoreArchive(did: did, auth: auth.authContext()) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var favoritesGrid: some View {
        if viewModel.favoriteGalleries.isEmpty, !viewModel.favoritesLoaded {
            DelayedSkeleton { SkeletonGrid(rows: 2) }
        } else if viewModel.favoriteGalleries.isEmpty, let err = viewModel.favoritesError {
            VStack(spacing: 8) {
                Text("Couldn't load favorites")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(String(describing: err))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Retry") {
                    viewModel.favoritesLoaded = false
                    Task { await viewModel.loadFavorites(did: did, auth: auth.authContext()) }
                }
                .font(.subheadline)
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else if viewModel.favoriteGalleries.isEmpty {
            Text("No favorites yet")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else {
            let visible = viewModel.visibleFavorites
            WindowedGrid(items: visible, scrollSpace: "profileScroll") { gallery, cellSize in
                Button {
                    selectedGallery = nil
                    DispatchQueue.main.async {
                        selectedGallery = ProfileGallerySelection(uri: gallery.uri, source: .favorites)
                    }
                } label: {
                    Color.clear
                        .overlay {
                            if let photo = gallery.items?.first {
                                ProfileGridThumbnail(urlString: photo.thumb, pixelSize: pixelSize(for: cellSize))
                            } else {
                                Rectangle().fill(.quaternary)
                            }
                        }
                        .clipped()
                        .overlay(alignment: .topTrailing) {
                            if (gallery.items?.count ?? 0) > 1 {
                                Image(systemName: "square.on.square.fill")
                                    .font(.system(size: 14))
                                    .rotationEffect(.degrees(180))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                    .padding(6)
                                    .accessibilityHidden(true)
                            }
                        }
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: gallery.uri, in: galleryZoomNS)
                .onAppear {
                    if gallery.id == visible.last?.id {
                        Task { await viewModel.loadMoreFavorites(did: did, auth: auth.authContext()) }
                    }
                }
            }
            // HEAD-probe every loaded favorite thumb so dangling CDN refs get
            // marked before render. Keyed on count plus the last uri so new
            // batches from loadMore trigger a re-probe without joining every
            // uri into a string on each body evaluation; probeFavoriteThumbs
            // itself skips uris already checked this session.
            .task(id: FavoritesProbeKey(galleries: viewModel.favoriteGalleries)) {
                await probeFavoriteThumbs()
            }
        }
    }

    private func probeFavoriteThumbs() async {
        let targets: [(uri: String, thumb: String)] = viewModel.favoriteGalleries.compactMap { gallery in
            guard !viewModel.brokenFavoriteUris.contains(gallery.uri),
                  !viewModel.probedFavoriteUris.contains(gallery.uri),
                  let thumb = gallery.items?.first?.thumb,
                  !thumb.isEmpty
            else { return nil }
            return (gallery.uri, thumb)
        }
        guard !targets.isEmpty else { return }

        var broken: [String] = []
        var probed: [String] = []
        await withTaskGroup(of: FavoriteThumbProbe.self) { group in
            for target in targets {
                let uri = target.uri
                let thumb = target.thumb
                group.addTask {
                    guard let url = URL(string: thumb) else {
                        return FavoriteThumbProbe(uri: uri, result: .broken)
                    }
                    var req = URLRequest(url: url)
                    req.httpMethod = "HEAD"
                    req.timeoutInterval = 10
                    do {
                        let (_, response) = try await NetworkEnvironment.session.data(for: req)
                        guard let http = response as? HTTPURLResponse else {
                            return FavoriteThumbProbe(uri: uri, result: .unknown)
                        }
                        if http.statusCode == 404 || http.statusCode == 410 {
                            return FavoriteThumbProbe(uri: uri, result: .broken)
                        }
                        return FavoriteThumbProbe(uri: uri, result: .ok)
                    } catch {
                        return FavoriteThumbProbe(uri: uri, result: .unknown)
                    }
                }
            }
            for await probe in group {
                switch probe.result {
                case .broken:
                    broken.append(probe.uri)
                    probed.append(probe.uri)
                case .ok:
                    probed.append(probe.uri)
                case .unknown:
                    break
                }
            }
        }
        for uri in broken {
            viewModel.brokenFavoriteUris.insert(uri)
        }
        for uri in probed {
            viewModel.probedFavoriteUris.insert(uri)
        }
    }

    private func storyDateLabel(_ iso: String) -> String {
        // Was building three formatters per call — once per story archive cell,
        // on every body evaluation. `DateFormatting` shares its formatters.
        DateFormatting.monthDayLabel(iso)
    }

    @ViewBuilder
    private func followButton(profile: GrainProfileDetailed) -> some View {
        if profile.viewer?.following != nil {
            Button {
                Task { await viewModel.toggleFollow(auth: auth.authContext()) }
            } label: {
                Text("Following")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            Button {
                Task { await viewModel.toggleFollow(auth: auth.authContext()) }
            } label: {
                Text(profile.viewer?.followedBy != nil ? "Follow back" : "Follow")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func germDMUrl(profile: GrainProfileDetailed) -> URL? {
        guard let messageMe = profile.messageMe,
              let viewerDid = auth.userDID else { return nil }
        let isOwn = did == viewerDid
        if !isOwn {
            switch messageMe.showButtonTo {
            case "everyone": break
            case "usersIFollow":
                guard profile.viewer?.followedBy != nil else { return nil }
            default: return nil
            }
        }
        return URL(string: "\(messageMe.messageMeUrl)/web#\(did)+\(viewerDid)")
    }

    private func openAvatarOverlay() {
        withAnimation(.easeOut(duration: 0.2)) {
            showAvatarOverlay = true
        }
    }

    private func dismissAvatarOverlay() {
        withAnimation(.easeOut(duration: 0.25)) {
            showAvatarOverlay = false
        }
    }
}

struct AvatarOverlay: View {
    let url: String
    let onDismiss: () -> Void

    @State private var zoomState = ImageZoomState()
    @State private var circularImage: UIImage?
    @State private var dragOffset: CGFloat = 0
    @GestureState private var dragDelta: CGFloat = 0

    private var liveDrag: CGFloat {
        dragOffset + dragDelta
    }

    /// Fades both the background dim and the image itself as the user swipes
    /// the overlay away. At 250pt of drag, everything is fully transparent.
    private var dragProgress: Double {
        guard !zoomState.showOverlay else { return 0 }
        return min(1, Double(abs(liveDrag)) / 250)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.92 * (1 - dragProgress))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            GeometryReader { geo in
                let side = geo.size.width - 64
                Group {
                    if let image = circularImage {
                        ZoomableImage(
                            localImage: image,
                            aspectRatio: 1.0,
                            onSingleTap: {
                                // Ignore taps while actively pinch-zoomed — ZoomableImage
                                // emits a single tap on release too, and we don't want
                                // that to dismiss.
                                if !zoomState.showOverlay {
                                    onDismiss()
                                }
                            }
                        )
                        .frame(width: side, height: side)
                    } else {
                        ProgressView()
                            .tint(.white)
                            .frame(width: side, height: side)
                    }
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .offset(y: liveDrag)
                .opacity(1 - dragProgress)
            }
            .ignoresSafeArea()
        }
        .environment(zoomState)
        .modifier(ImageZoomOverlay(zoomState: zoomState))
        .simultaneousGesture(
            DragGesture()
                .updating($dragDelta) { val, state, _ in
                    // Don't let a 1-finger drag move the image while the user is
                    // pinch-zooming — ZoomableImage's 2-finger pan handles that.
                    if !zoomState.showOverlay {
                        state = val.translation.height
                    }
                }
                .onEnded { val in
                    guard !zoomState.showOverlay else { return }
                    let shouldDismiss = abs(val.translation.height) > 80
                        || abs(val.predictedEndTranslation.height) > 150
                    if shouldDismiss {
                        // Commit the drag translation to @State so the image stays
                        // at its dragged opacity while the removal transition runs —
                        // otherwise @GestureState dragDelta resets to 0 in the same
                        // frame and the image pops back to full opacity for a beat
                        // before fading out.
                        dragOffset = val.translation.height
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .task {
            guard let imageURL = URL(string: url) else { return }
            let request = ImageRequest(url: imageURL, processors: [ImageProcessors.Circle()])
            circularImage = try? await ImagePipeline.shared.image(for: request)
        }
    }
}

struct StatView: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private enum FavoriteThumbProbeResult {
    case ok
    case broken
    case unknown
}

private struct FavoriteThumbProbe {
    let uri: String
    let result: FavoriteThumbProbeResult
}

/// Cheap identity for the loaded favorites list, for the probe task's `id:`.
private struct FavoritesProbeKey: Hashable {
    let count: Int
    let lastUri: String?

    init(galleries: [GrainGallery]) {
        count = galleries.count
        lastUri = galleries.last?.uri
    }
}

// MARK: - Profile Grid Thumbnail (sync cache read to avoid flash)

struct ProfileGridThumbnail: View {
    let urlString: String
    private let request: ImageRequest?
    /// Seeded from the memory cache when the cell is built, so a cached
    /// thumbnail is on screen in its first frame. Held here afterwards: the
    /// body used to re-query the cache on every evaluation, and once the feed
    /// and another profile had filled the cache the eviction turned cells grey
    /// mid-scroll and refetched them.
    @State private var image: UIImage?

    /// `pixelSize` is the cell's size in pixels. Given, the thumbnail is
    /// decoded at that size rather than the CDN's, so the cache holds a
    /// cell-sized image per gallery instead of a screen-wide one.
    init(urlString: String, pixelSize: CGSize? = nil) {
        self.urlString = urlString
        request = Self.request(for: urlString, pixelSize: pixelSize)
        _image = State(initialValue: Self.cachedImage(for: request))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
                    .onAppear { loadIfNeeded() }
            }
        }
        .onChange(of: urlString) {
            image = Self.cachedImage(for: request)
            loadIfNeeded()
        }
    }

    private static func request(for urlString: String, pixelSize: CGSize?) -> ImageRequest? {
        guard let url = URL(string: urlString) else { return nil }
        guard let pixelSize, pixelSize.width > 0, pixelSize.height > 0 else {
            return ImageRequest(url: url)
        }
        return ImageRequest(url: url, processors: [
            ImageProcessors.Resize(size: pixelSize, unit: .pixels, contentMode: .aspectFill),
        ])
    }

    private static func cachedImage(for request: ImageRequest?) -> UIImage? {
        guard let request else { return nil }
        return ImagePipeline.shared.cache.cachedImage(for: request)?.image
    }

    private func loadIfNeeded() {
        guard image == nil, let request else { return }
        Task {
            if let loaded = try? await ImagePipeline.shared.image(for: request) {
                image = loaded
            }
        }
    }
}

struct CopiedCheckmarkToast: View {
    @State private var checkScale = 0.3

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .scaleEffect(checkScale)
                .onAppear {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        checkScale = 1.0
                    }
                }
            Text("Copied")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .transition(.scale.combined(with: .opacity))
    }
}

#Preview {
    ProfileView(client: .preview, did: "did:plc:preview")
        .previewEnvironments()
}

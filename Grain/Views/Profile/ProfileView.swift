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
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?
    @State private var deletedGalleryUri: String?
    @State private var viewMode: ProfileViewMode = .grid
    @State private var tabPageWidth: CGFloat = 0
    @State private var tabScrollOffsetX: CGFloat = 0
    @State private var tabHeights: [ProfileViewMode: CGFloat] = [:]
    @State private var tabSectionViewportMinY: CGFloat = .infinity
    @State private var zoomState = ImageZoomState()
    @State private var cardStoryAuthor: GrainStoryAuthor?
    let client: XRPCClient
    @State private var selectedArchivedStory: GrainStory?
    let actor: String
    var isRoot = false
    @State private var showCopiedToast = false

    /// Resolved DID from the loaded profile, or the original actor identifier
    private var did: String {
        viewModel.profile?.did ?? actor
    }

    init(client: XRPCClient, did: String, isRoot: Bool = false) {
        self.client = client
        _viewModel = State(initialValue: ProfileDetailViewModel(client: client))
        actor = did
        self.isRoot = isRoot
    }

    var body: some View {
        ZStack {
            if isRoot {
                NavigationStack {
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
                    .foregroundStyle(.white, Color("AccentColor"))
                    .offset(x: 4, y: 4)
                    .accessibilityHidden(true)
            }
        }
        .padding(4)
        .contentShape(Circle())
        .onTapGesture {
            if did == auth.userDID {
                if hasStory { showStoryViewer = true } else { showStoryCreate = true }
            } else {
                if hasStory { showStoryViewer = true }
                else if profile.avatar != nil { openAvatarOverlay() }
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
                            Label("View Profile Photo", systemImage: "person.crop.circle")
                        }
                        Divider()
                    }
                    Button { copyText("@\(profile.handle)") } label: {
                        Label("Copy Handle", systemImage: "doc.on.doc")
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
                                        onMentionTap: { did in selectedProfileDid = did },
                                        onHashtagTap: { tag in selectedHashtag = tag }
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
                                        .tint(.primary)
                                    }
                                }
                                .padding(.horizontal)
                            } else {
                                HStack(spacing: 8) {
                                    NavigationLink {
                                        EditProfileView(client: client, onSaved: {
                                            Task { await viewModel.load(did: did) }
                                        })
                                    } label: {
                                        Text("Edit Profile")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.primary)

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
                                        .tint(.primary)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        // Tabs + grid
                        if !viewModel.isBlockHidden {
                            if did == auth.userDID {
                                ownProfileTabSection
                                    .id("profileTabSection")
                                    .onGeometryChange(for: CGFloat.self) { proxy in
                                        proxy.frame(in: .scrollView).minY
                                    } action: { newValue in
                                        tabSectionViewportMinY = newValue
                                    }
                            } else {
                                galleriesGrid
                            }
                        }
                    } // end if !isBlockHidden (tabs + grid)
                } else if viewModel.error != nil {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "Profile Not Found",
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
                    ProgressView()
                        .padding(.top, 100)
                }
            }
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
                                    Label("Share Profile", systemImage: "square.and.arrow.up")
                                }
                                Button {
                                    UIPasteboard.general.string = profile.handle
                                } label: {
                                    Label("Copy Username", systemImage: "at")
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
            .navigationDestination(item: $selectedProfileDid) { did in
                ProfileView(client: client, did: did)
            }
            .navigationDestination(item: $selectedHashtag) { tag in
                HashtagFeedView(client: client, tag: tag)
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
                            selectedProfileDid = did
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
                        selectedProfileDid = did
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
                            selectedProfileDid = did
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
            .background(Color(.systemBackground))
            .refreshable {
                await viewModel.load(did: actor, viewer: auth.userDID, auth: auth.authContext())
                if viewMode == .favorites {
                    await viewModel.loadFavorites(did: actor, auth: auth.authContext())
                } else if viewMode == .stories {
                    await viewModel.loadStoryArchive(did: actor, auth: auth.authContext())
                }
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
                if showCopiedToast { CopiedCheckmarkToast() }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showCopiedToast)
            .sensoryFeedback(.impact(weight: .medium), trigger: showCopiedToast)
            .coordinateSpace(.named("profileScroll"))
            .onChange(of: viewMode) { _, _ in
                if tabSectionViewportMinY < 0 {
                    withAnimation(.smooth(duration: 0.35)) {
                        scrollProxy.scrollTo("profileTabSection", anchor: .top)
                    }
                }
            }
        } // close ScrollViewReader
    }

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
        let avatars = Array(followers.prefix(3))
        let names = followers.prefix(2).compactMap { f -> String? in
            if let name = f.displayName, !name.isEmpty { return name }
            return f.handle
        }
        let othersCount = displayCount - names.count

        HStack(spacing: 6) {
            // Overlapping avatars
            HStack(spacing: -8) {
                ForEach(Array(avatars.enumerated()), id: \.element.did) { index, follower in
                    AvatarView(url: follower.avatar, size: 24)
                        .background(Circle().fill(Color(.systemBackground)))
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .zIndex(Double(3 - index))
                }
            }

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

    private func tabButton(icon: String, mode: ProfileViewMode) -> some View {
        let modes: [ProfileViewMode] = [.grid, .favorites, .stories]
        let activeIdx: Int = {
            if tabPageWidth > 0 {
                let raw = Int((tabScrollOffsetX / tabPageWidth).rounded())
                return max(0, min(modes.count - 1, raw))
            }
            return modes.firstIndex(of: viewMode) ?? 0
        }()
        let isActive = modes.firstIndex(of: mode) == activeIdx
        let symbolName = isActive ? icon + ".fill" : icon
        return Button {
            setViewMode(mode)
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 22))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.rawValue.capitalized)")
    }

    private func setViewMode(_ mode: ProfileViewMode) {
        guard mode != viewMode else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            viewMode = mode
        }
        if mode == .stories {
            Task { await viewModel.loadStoryArchive(did: did, auth: auth.authContext()) }
        } else if mode == .favorites {
            Task { await viewModel.loadFavorites(did: did, auth: auth.authContext()) }
        }
    }

    private var ownProfileTabSection: some View {
        let modes: [ProfileViewMode] = [.grid, .favorites, .stories]
        let currentIdx = modes.firstIndex(of: viewMode) ?? 0

        let scrollBinding = Binding<ProfileViewMode?>(
            get: { viewMode },
            set: { newMode in
                guard let newMode, newMode != viewMode else { return }
                viewMode = newMode
                if newMode == .stories {
                    Task { await viewModel.loadStoryArchive(did: did, auth: auth.authContext()) }
                } else if newMode == .favorites {
                    Task { await viewModel.loadFavorites(did: did, auth: auth.authContext()) }
                }
            }
        )

        return VStack(spacing: 0) {
            // Tab bar with a single indicator driven by live scroll offset.
            HStack(spacing: 0) {
                tabButton(icon: "square.grid.3x3", mode: .grid)
                tabButton(icon: "heart", mode: .favorites)
                tabButton(icon: "clock", mode: .stories)
            }
            .overlay(alignment: .bottomLeading) {
                GeometryReader { tabBarGeo in
                    let tabWidth = tabBarGeo.size.width / CGFloat(modes.count)
                    let indicatorWidth: CGFloat = 32
                    let fraction: CGFloat = tabPageWidth > 0
                        ? tabScrollOffsetX / tabPageWidth
                        : CGFloat(currentIdx)
                    let clamped = max(0, min(fraction, CGFloat(modes.count - 1)))
                    let xOffset = clamped * tabWidth + (tabWidth - indicatorWidth) / 2
                    Rectangle()
                        .fill(Color("AccentColor"))
                        .frame(width: indicatorWidth, height: 2.5)
                        .offset(x: xOffset, y: -6)
                }
                .frame(height: 2.5)
                .allowsHitTesting(false)
            }

            // Native horizontally-paged grids. SwiftUI handles the physics, snapping,
            // and axis disambiguation with the outer vertical ScrollView.
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    galleriesGrid
                        .containerRelativeFrame(.horizontal)
                        .contentShape(Rectangle())
                        .clipped()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                            tabHeights[.grid] = h
                        }
                        .id(ProfileViewMode.grid)
                    favoritesGrid
                        .containerRelativeFrame(.horizontal)
                        .contentShape(Rectangle())
                        .clipped()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                            tabHeights[.favorites] = h
                        }
                        .id(ProfileViewMode.favorites)
                    storyArchiveGrid
                        .containerRelativeFrame(.horizontal)
                        .contentShape(Rectangle())
                        .clipped()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                            tabHeights[.stories] = h
                        }
                        .id(ProfileViewMode.stories)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: scrollBinding)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.x
            } action: { _, newValue in
                tabScrollOffsetX = newValue
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if newWidth > 0 { tabPageWidth = newWidth }
            }
            .frame(height: interpolatedTabHeight(modes: modes), alignment: .top)
            .clipped()
        }
    }

    private func interpolatedTabHeight(modes: [ProfileViewMode]) -> CGFloat {
        let fallback: CGFloat = 200
        let heights = modes.map { tabHeights[$0] ?? fallback }
        guard tabPageWidth > 0 else {
            let idx = modes.firstIndex(of: viewMode) ?? 0
            return max(heights[idx], fallback)
        }
        let raw = tabScrollOffsetX / tabPageWidth
        let clamped = max(0, min(raw, CGFloat(modes.count - 1)))
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, modes.count - 1)
        let t = clamped - CGFloat(lower)
        return max(heights[lower] * (1 - t) + heights[upper] * t, fallback)
    }

    @ViewBuilder
    private var galleriesGrid: some View {
        if viewModel.galleries.isEmpty, !viewModel.isLoading {
            Text("No galleries yet")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
            ], spacing: 2) {
                ForEach(viewModel.galleries) { gallery in
                    Button {
                        selectedGallery = nil
                        DispatchQueue.main.async {
                            selectedGallery = ProfileGallerySelection(uri: gallery.uri, source: .galleries)
                        }
                    } label: {
                        Color.clear
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .overlay {
                                if let photo = gallery.items?.first {
                                    ProfileGridThumbnail(urlString: photo.thumb)
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
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
            ], spacing: 2) {
                ForEach(viewModel.archivedStories) { story in
                    Button {
                        if let index = viewModel.archivedStories.firstIndex(where: { $0.id == story.id }) {
                            selectedArchivedStory = viewModel.archivedStories[index]
                        }
                    } label: {
                        Color.clear
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
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
    }

    @ViewBuilder
    private var favoritesGrid: some View {
        if viewModel.favoriteGalleries.isEmpty, !viewModel.favoritesLoaded {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
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
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
            ], spacing: 2) {
                ForEach(visible) { gallery in
                    Button {
                        selectedGallery = nil
                        DispatchQueue.main.async {
                            selectedGallery = ProfileGallerySelection(uri: gallery.uri, source: .favorites)
                        }
                    } label: {
                        Color.clear
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .overlay {
                                if let photo = gallery.items?.first {
                                    ProfileGridThumbnail(urlString: photo.thumb)
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
            }
            // HEAD-probe every loaded favorite thumb so dangling CDN refs get
            // marked before render. Keyed on the full uri list so new batches
            // from loadMore trigger a re-probe; probeFavoriteThumbs itself
            // skips uris already checked this session.
            .task(id: viewModel.favoriteGalleries.map(\.uri).joined(separator: "|")) {
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
                        let (_, response) = try await URLSession.shared.data(for: req)
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let display = DateFormatter()
        display.dateFormat = "MMM d"
        return display.string(from: date)
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
            .tint(.primary)
        } else {
            Button {
                Task { await viewModel.toggleFollow(auth: auth.authContext()) }
            } label: {
                Text("Follow")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("AccentColor"))
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
                                if !zoomState.showOverlay { onDismiss() }
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
                    if !zoomState.showOverlay { state = val.translation.height }
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

// MARK: - Profile Grid Thumbnail (sync cache read to avoid flash)

private struct ProfileGridThumbnail: View {
    let urlString: String
    @State private var asyncImage: UIImage?

    private var imageURL: URL? {
        URL(string: urlString)
    }

    private var resolvedImage: UIImage? {
        if let imageURL,
           let cached = ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: imageURL))?.image
        {
            return cached
        }
        return asyncImage
    }

    var body: some View {
        if let image = resolvedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(.quaternary)
                .onAppear { loadIfNeeded() }
        }
    }

    private func loadIfNeeded() {
        guard let imageURL, asyncImage == nil else { return }
        let request = ImageRequest(url: imageURL)
        if ImagePipeline.shared.cache.cachedImage(for: request) != nil { return }
        Task {
            if let image = try? await ImagePipeline.shared.image(for: request) {
                asyncImage = image
            }
        }
    }
}

private struct CopiedCheckmarkToast: View {
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

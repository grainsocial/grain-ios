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
    @State private var selectedGalleryUri: String?
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?
    @State private var deletedGalleryUri: String?
    @State private var viewMode: ProfileViewMode = .grid
    @State private var zoomState = ImageZoomState()
    @State private var cardStoryAuthor: GrainStoryAuthor?
    @State private var avatarPressed = false
    let client: XRPCClient
    @State private var selectedArchivedStory: GrainStory?
    let actor: String
    var isRoot = false

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
        if isRoot {
            NavigationStack {
                profileContent
            }
        } else {
            profileContent
        }
    }

    private var profileContent: some View {
        ScrollView {
            if let profile = viewModel.profile {
                VStack(spacing: 12) {
                    // Avatar + stats row
                    HStack(alignment: .center, spacing: 16) {
                        StoryRingView(hasStory: !viewModel.stories.isEmpty, viewed: did != auth.userDID && viewedStories.hasViewedAll(authorDid: did, latestAt: viewModel.stories.last?.createdAt ?? ""), size: 80) {
                            AvatarView(url: profile.avatar, size: 80)
                                .liquidGlassCircle()
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if did == auth.userDID {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white, Color("AccentColor"))
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .scaleEffect(avatarPressed ? 1.08 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: avatarPressed)
                        .contentShape(Circle())
                        .onTapGesture {
                            if did == auth.userDID {
                                if !viewModel.stories.isEmpty {
                                    showStoryViewer = true
                                } else {
                                    showStoryCreate = true
                                }
                            } else {
                                if !viewModel.stories.isEmpty {
                                    showStoryViewer = true
                                } else if profile.avatar != nil {
                                    showAvatarOverlay = true
                                }
                            }
                        }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            if did == auth.userDID {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                showStoryCreate = true
                            }
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in if !avatarPressed { avatarPressed = true } }
                                .onEnded { _ in avatarPressed = false }
                        )

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
                        }

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
                        VStack(spacing: 0) {
                            if did == auth.userDID {
                                HStack(spacing: 0) {
                                    tabButton(icon: "square.grid.3x3", mode: .grid)
                                    tabButton(icon: "heart", mode: .favorites)
                                    tabButton(icon: "clock", mode: .stories)
                                }
                            }

                            if viewMode == .grid {
                                galleriesGrid
                            }

                            if viewMode == .favorites {
                                favoritesGrid
                            }

                            if viewMode == .stories {
                                storyArchiveGrid
                            }
                        }
                        .highPriorityGesture(
                            did == auth.userDID ?
                                DragGesture(minimumDistance: 30, coordinateSpace: .local)
                                .onEnded { value in
                                    let h = value.translation.width
                                    let v = value.translation.height
                                    guard abs(h) > abs(v) else { return }
                                    let modes: [ProfileViewMode] = [.grid, .favorites, .stories]
                                    guard let currentIdx = modes.firstIndex(of: viewMode) else { return }
                                    if h < 0, currentIdx < modes.count - 1 {
                                        let next = modes[currentIdx + 1]
                                        withAnimation(.easeInOut(duration: 0.2)) { viewMode = next }
                                        if next == .stories {
                                            Task { await viewModel.loadStoryArchive(did: did, auth: auth.authContext()) }
                                        } else if next == .favorites {
                                            Task { await viewModel.loadFavorites(did: did, auth: auth.authContext()) }
                                        }
                                    } else if h > 0, currentIdx > 0 {
                                        withAnimation(.easeInOut(duration: 0.2)) { viewMode = modes[currentIdx - 1] }
                                    }
                                }
                                : nil
                        )
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
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(client: client)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .tint(.primary)
                }
            } else if viewModel.profile != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !viewModel.isBlockHidden {
                            Button(role: viewModel.profile?.viewer?.muted == true ? nil : .destructive) {
                                Task { await viewModel.toggleMute(auth: auth.authContext()) }
                            } label: {
                                Label(
                                    viewModel.profile?.viewer?.muted == true ? "Unmute" : "Mute",
                                    systemImage: viewModel.profile?.viewer?.muted == true ? "speaker.wave.2" : "speaker.slash"
                                )
                            }
                        }
                        Button(role: viewModel.profile?.viewer?.blocking != nil ? nil : .destructive) {
                            Task { await viewModel.toggleBlock(auth: auth.authContext()) }
                        } label: {
                            Label(
                                viewModel.profile?.viewer?.blocking != nil ? "Unblock" : "Block",
                                systemImage: viewModel.profile?.viewer?.blocking != nil ? "circle" : "nosign"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(.primary)
                }
            }
        }
        .navigationDestination(item: $selectedGalleryUri) { uri in
            GalleryDetailView(client: client, galleryUri: uri, deletedGalleryUri: $deletedGalleryUri)
                .navigationTransition(.zoom(sourceID: uri, in: galleryZoomNS))
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
        .fullScreenCover(isPresented: $showAvatarOverlay) {
            if let avatar = viewModel.profile?.avatar {
                AvatarOverlay(url: avatar) {
                    showAvatarOverlay = false
                }
            }
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
        let isActive = viewMode == mode
        let symbolName = isActive ? icon + ".fill" : icon
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { viewMode = mode }
            if mode == .stories {
                Task { await viewModel.loadStoryArchive(did: did, auth: auth.authContext()) }
            } else if mode == .favorites {
                Task { await viewModel.loadFavorites(did: did, auth: auth.authContext()) }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbolName)
                    .font(.system(size: 22))
                    .foregroundStyle(isActive ? .primary : .secondary)
                Rectangle()
                    .fill(viewMode == mode ? Color("AccentColor") : .clear)
                    .frame(width: 32, height: 2.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
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
                        selectedGalleryUri = nil
                        DispatchQueue.main.async {
                            selectedGalleryUri = gallery.uri
                        }
                    } label: {
                        Color.clear
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .overlay {
                                if let photo = gallery.items?.first {
                                    LazyImage(url: URL(string: photo.thumb)) { state in
                                        if let image = state.image {
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } else {
                                            Rectangle().fill(.quaternary)
                                        }
                                    }
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
        if viewModel.favoriteGalleries.isEmpty, !viewModel.isLoading {
            Text("No favorites yet")
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
                ForEach(viewModel.favoriteGalleries) { gallery in
                    Button {
                        selectedGalleryUri = nil
                        DispatchQueue.main.async {
                            selectedGalleryUri = gallery.uri
                        }
                    } label: {
                        Color.clear
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .overlay {
                                if let photo = gallery.items?.first {
                                    LazyImage(url: URL(string: photo.thumb)) { state in
                                        if let image = state.image {
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } else {
                                            Rectangle().fill(.quaternary)
                                        }
                                    }
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
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: gallery.uri, in: galleryZoomNS)
                    .onAppear {
                        if gallery.id == viewModel.favoriteGalleries.last?.id {
                            Task { await viewModel.loadMoreFavorites(did: did, auth: auth.authContext()) }
                        }
                    }
                }
            }
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
}

private struct AvatarOverlay: View {
    let url: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            LazyImage(url: URL(string: url)) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(.circle)
                        .padding(40)
                } else {
                    ProgressView()
                }
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: true)
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

#Preview {
    ProfileView(client: .preview, did: "did:plc:preview")
        .previewEnvironments()
}

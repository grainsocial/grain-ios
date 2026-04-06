import NukeUI
import SwiftUI

enum ProfileViewMode: String, CaseIterable {
    case grid, list
}

struct ProfileView: View {
    @Namespace private var viewModeNS
    @Environment(AuthManager.self) private var auth
    @Environment(ViewedStoryStorage.self) private var viewedStories
    @State private var showStoryViewer = false
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
                        .scaleEffect(avatarPressed ? 1.08 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: avatarPressed)
                        .contentShape(Circle())
                        .onTapGesture {
                            if !viewModel.stories.isEmpty {
                                showStoryViewer = true
                            } else if profile.avatar != nil {
                                showAvatarOverlay = true
                            }
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in if !avatarPressed { avatarPressed = true } }
                                .onEnded { _ in avatarPressed = false }
                        )

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
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Name + handle + bio
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName ?? profile.handle)
                            .font(.subheadline.bold())
                        Text("@\(profile.handle)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                    // Known followers
                    if !viewModel.knownFollowers.isEmpty, did != auth.userDID {
                        NavigationLink {
                            FollowListView(client: client, did: did, mode: .knownFollowers)
                        } label: {
                            KnownFollowersRow(followers: viewModel.knownFollowers)
                        }
                        .buttonStyle(.plain)
                    }

                    // Follow + Germ DM buttons
                    if did != auth.userDID {
                        HStack(spacing: 8) {
                            FollowButton(profile: profile, viewModel: viewModel, auth: auth)

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
                                .tint(Color(red: 0.52, green: 0.63, blue: 1.0))
                            }
                        }
                        .padding(.horizontal)
                    } else if let germUrl = germDMUrl(profile: profile) {
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
                        .tint(Color(red: 0.52, green: 0.63, blue: 1.0))
                        .padding(.horizontal)
                    }

                    // Galleries
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
                                    selectedGalleryUri = gallery.uri
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
                                .onAppear {
                                    if gallery.id == viewModel.galleries.last?.id {
                                        Task { await viewModel.loadMoreGalleries(did: did, auth: auth.authContext()) }
                                    }
                                }
                            }
                        }
                    }
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .padding(.top, 100)
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
                        SettingsView(client: client, onProfileEdited: {
                            Task { await viewModel.load(did: actor, viewer: auth.userDID, auth: auth.authContext()) }
                        })
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .tint(.primary)
                }
            }
        }
        .navigationDestination(item: $selectedGalleryUri) { uri in
            GalleryDetailView(client: client, galleryUri: uri, deletedGalleryUri: $deletedGalleryUri)
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
        }
        .task {
            await viewModel.load(did: actor, viewer: auth.userDID, auth: auth.authContext())
        }
        .onChange(of: deletedGalleryUri) { _, uri in
            if let uri {
                viewModel.galleries.removeAll { $0.uri == uri }
                deletedGalleryUri = nil
            }
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

private struct KnownFollowersRow: View {
    let followers: [FollowerItem]

    private var displayCount: Int {
        max(followers.count, 0)
    }

    private var avatars: [FollowerItem] {
        Array(followers.prefix(3))
    }

    private var names: [String] {
        followers.prefix(2).compactMap { follower -> String? in
            if let name = follower.displayName, !name.isEmpty { return name }
            return follower.handle
        }
    }

    private var othersCount: Int {
        displayCount - names.count
    }

    var body: some View {
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
}

private struct FollowButton: View {
    let profile: GrainProfileDetailed
    let viewModel: ProfileDetailViewModel
    let auth: AuthManager

    var body: some View {
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

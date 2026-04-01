import SwiftUI
import NukeUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var auth
    @State private var showStoryViewer = false
    @State private var viewModel: ProfileDetailViewModel
    @State private var selectedGalleryUri: String?
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?
    let client: XRPCClient
    let did: String
    var isRoot = false

    init(client: XRPCClient, did: String, isRoot: Bool = false) {
        self.client = client
        _viewModel = State(initialValue: ProfileDetailViewModel(client: client))
        self.did = did
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
                    VStack(spacing: 16) {
                        // Avatar + name with glass header
                        VStack(spacing: 8) {
                            StoryRingView(hasStory: !viewModel.stories.isEmpty, size: 80) {
                                AvatarView(url: profile.avatar, size: 80)
                                    .liquidGlassCircle()
                            }
                            .onTapGesture {
                                if !viewModel.stories.isEmpty {
                                    showStoryViewer = true
                                }
                            }

                            Text(profile.displayName ?? profile.handle)
                                .font(.title2.bold())
                            Text("@\(profile.handle)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical)

                        // Stats with glass pills
                        HStack(spacing: 24) {
                            StatView(count: profile.galleryCount ?? 0, label: "Galleries")
                            NavigationLink {
                                FollowListView(client: client, did: did, mode: .followers)
                            } label: {
                                StatView(count: profile.followersCount ?? 0, label: "Followers")
                            }
                            .buttonStyle(.plain)
                            NavigationLink {
                                FollowListView(client: client, did: did, mode: .following)
                            } label: {
                                StatView(count: profile.followsCount ?? 0, label: "Following")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .liquidGlass()

                        // Follow button
                        if did != auth.userDID {
                            Button {
                                Task { await viewModel.toggleFollow(auth: auth.authContext()) }
                            } label: {
                                Text(profile.viewer?.following != nil ? "Following" : "Follow")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(profile.viewer?.following != nil ? .secondary : Color("AccentColor"))
                            .padding(.horizontal)
                        }

                        if let description = profile.description, !description.isEmpty {
                            RichTextView(
                                text: description,
                                font: .body,
                                onMentionTap: { did in selectedProfileDid = did },
                                onHashtagTap: { tag in selectedHashtag = tag }
                            )
                            .padding(.horizontal)
                        }

                        // Gallery grid
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 2),
                            GridItem(.flexible(), spacing: 2),
                            GridItem(.flexible(), spacing: 2)
                        ], spacing: 2) {
                            ForEach(viewModel.galleries) { gallery in
                                Button {
                                    selectedGalleryUri = gallery.uri
                                } label: {
                                    Color.clear
                                        .aspectRatio(3.0/4.0, contentMode: .fit)
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
                } else if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 100)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if did == auth.userDID {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView(client: client, onProfileEdited: {
                                Task { await viewModel.load(did: did, viewer: auth.userDID, auth: auth.authContext()) }
                            })
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedGalleryUri) { uri in
                GalleryDetailView(client: client, galleryUri: uri)
            }
            .navigationDestination(item: $selectedProfileDid) { did in
                ProfileView(client: client, did: did)
            }
            .navigationDestination(item: $selectedHashtag) { tag in
                HashtagFeedView(client: client, tag: tag)
            }
            .customFullScreenCover(isPresented: $showStoryViewer) {
                if let profile = viewModel.profile {
                    StoryViewer(
                        authors: [GrainStoryAuthor(
                            profile: GrainProfile(cid: "", did: did, handle: profile.handle, displayName: profile.displayName, avatar: profile.avatar),
                            storyCount: viewModel.stories.count,
                            latestAt: viewModel.stories.first?.createdAt ?? ""
                        )],
                        startIndex: 0,
                        client: client,
                        onDismiss: { showStoryViewer = false }
                    )
                }
            }
            .background(Color(.systemBackground))
            .refreshable {
                await viewModel.load(did: did, viewer: auth.userDID, auth: auth.authContext())
            }
            .task {
                await viewModel.load(did: did, viewer: auth.userDID, auth: auth.authContext())
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

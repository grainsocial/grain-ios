import SwiftUI
import NukeUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: ProfileDetailViewModel

    let did: String

    init(client: XRPCClient, did: String) {
        _viewModel = State(initialValue: ProfileDetailViewModel(client: client))
        self.did = did
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let profile = viewModel.profile {
                    VStack(spacing: 16) {
                        // Avatar + name with glass header
                        VStack(spacing: 8) {
                            AvatarView(url: profile.avatar, size: 80)
                                .liquidGlassCircle()

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
                            StatView(count: profile.followersCount ?? 0, label: "Followers")
                            StatView(count: profile.followsCount ?? 0, label: "Following")
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
                            .tint(profile.viewer?.following != nil ? .secondary : .accentColor)
                            .padding(.horizontal)
                        }

                        if let description = profile.description, !description.isEmpty {
                            Text(description)
                                .font(.body)
                                .padding(.horizontal)
                        }

                        // Gallery grid
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 2),
                            GridItem(.flexible(), spacing: 2),
                            GridItem(.flexible(), spacing: 2)
                        ], spacing: 2) {
                            ForEach(viewModel.galleries) { gallery in
                                NavigationLink(value: gallery.uri) {
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
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .navigationDestination(for: String.self) { uri in
                GalleryDetailView(client: XRPCClient(baseURL: AuthManager.serverURL), galleryUri: uri)
            }
            .task {
                await viewModel.load(did: did, auth: auth.authContext())
            }
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

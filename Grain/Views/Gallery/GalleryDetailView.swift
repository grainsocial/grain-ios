import SwiftUI
import NukeUI

struct GalleryDetailView: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: GalleryDetailViewModel

    let galleryUri: String

    init(client: XRPCClient, galleryUri: String) {
        _viewModel = State(initialValue: GalleryDetailViewModel(client: client))
        self.galleryUri = galleryUri
    }

    var body: some View {
        ScrollView {
            if let gallery = viewModel.gallery {
                VStack(alignment: .leading, spacing: 16) {
                    // Photos — edge to edge, respecting aspect ratio
                    if let items = gallery.items {
                        ForEach(items) { photo in
                            LazyImage(url: URL(string: photo.fullsize)) { state in
                                if let image = state.image {
                                    image
                                        .resizable()
                                        .aspectRatio(photo.aspectRatio.ratio, contentMode: .fit)
                                } else if state.isLoading {
                                    Rectangle()
                                        .fill(.quaternary)
                                        .aspectRatio(photo.aspectRatio.ratio, contentMode: .fit)
                                }
                            }
                        }
                    }

                    // Title & Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text(gallery.title ?? "")
                            .font(.title2.bold())

                        if let description = gallery.description, !description.isEmpty {
                            Text(description)
                                .font(.body)
                        }

                        // Creator
                        HStack {
                            AvatarView(url: gallery.creator.avatar, size: 32)
                            Text(gallery.creator.displayName ?? gallery.creator.handle)
                                .font(.subheadline.bold())
                        }

                        // Stats & Actions with glass pill
                        HStack(spacing: 16) {
                            Button {
                                Task { await viewModel.toggleFavorite(auth: auth.authContext()) }
                            } label: {
                                Label(
                                    "\(gallery.favCount ?? 0)",
                                    systemImage: gallery.viewer?.fav != nil ? "heart.fill" : "heart"
                                )
                            }
                            .foregroundStyle(gallery.viewer?.fav != nil ? .red : .primary)

                            Label("\(gallery.commentCount ?? 0)", systemImage: "bubble.right")

                            if let cameras = gallery.cameras, !cameras.isEmpty {
                                Label(cameras.first ?? "", systemImage: "camera")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .liquidGlass()
                    }
                    .padding(.horizontal)

                    // Comments
                    if !viewModel.comments.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Comments")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(viewModel.comments) { comment in
                                CommentRow(comment: comment)
                            }
                        }
                    }
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(uri: galleryUri, auth: auth.authContext())
        }
    }
}

struct CommentRow: View {
    let comment: GrainComment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(url: comment.author.avatar, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(comment.author.displayName ?? comment.author.handle)
                    .font(.caption.bold())
                Text(comment.text)
                    .font(.caption)
            }
        }
        .padding(.horizontal)
    }
}

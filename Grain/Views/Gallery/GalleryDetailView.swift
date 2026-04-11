import NukeUI
import SwiftUI

struct GalleryDetailView: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: GalleryDetailViewModel
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?
    @State private var selectedLocation: LocationDestination?
    @State private var showDeleteConfirmation = false
    @State private var showReportSheet = false
    @State private var showCommentSheet = false
    @State private var zoomState = ImageZoomState()
    @State private var cardStoryAuthor: GrainStoryAuthor?
    @Environment(\.dismiss) private var dismiss

    let client: XRPCClient
    let galleryUri: String
    @Binding var deletedGalleryUri: String?

    init(client: XRPCClient, galleryUri: String, deletedGalleryUri: Binding<String?> = .constant(nil)) {
        self.client = client
        _viewModel = State(initialValue: GalleryDetailViewModel(client: client))
        self.galleryUri = galleryUri
        _deletedGalleryUri = deletedGalleryUri
    }

    var body: some View {
        ScrollView {
            if viewModel.gallery != nil {
                VStack(spacing: 0) {
                    GalleryCardView(
                        gallery: Binding(
                            get: { viewModel.gallery! },
                            set: { viewModel.gallery = $0 }
                        ),
                        client: client,
                        onNavigate: {
                            showCommentSheet = true
                        },
                        onCommentTap: {
                            showCommentSheet = true
                        },
                        onProfileTap: { did in
                            selectedProfileDid = did
                        },
                        onHashtagTap: { tag in
                            selectedHashtag = tag
                        },
                        onLocationTap: { h3, name in
                            selectedLocation = LocationDestination(h3Index: h3, name: name)
                        },
                        onStoryTap: { author in
                            cardStoryAuthor = author
                        },
                        onReport: viewModel.gallery?.creator.did != auth.userDID ? { showReportSheet = true } : nil,
                        onDelete: viewModel.gallery?.creator.did == auth.userDID ? { showDeleteConfirmation = true } : nil
                    )

                    // View comments button
                    Button {
                        showCommentSheet = true
                    } label: {
                        HStack {
                            let count = viewModel.gallery?.commentCount ?? 0
                            if count > 0 {
                                Text("View all \(count) comments")
                            } else {
                                Text("Add a comment...")
                            }
                            Spacer()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ProgressView()
                    .padding(.top, 100)
            }
        }
        .environment(zoomState)
        .modifier(ImageZoomOverlay(zoomState: zoomState))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedProfileDid) { did in
            ProfileView(client: client, did: did)
        }
        .navigationDestination(item: $selectedHashtag) { tag in
            HashtagFeedView(client: client, tag: tag)
        }
        .navigationDestination(item: $selectedLocation) { loc in
            LocationFeedView(client: client, h3Index: loc.h3Index, locationName: loc.name)
        }
        .toolbarTitleDisplayMode(.inline)
        .alert("Delete Gallery?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await deleteGallery() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this gallery and all its photos.")
        }
        .sheet(isPresented: $showReportSheet) {
            if let gallery = viewModel.gallery {
                ReportView(client: client, subjectUri: gallery.uri, subjectCid: gallery.cid)
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
        .sheet(isPresented: $showCommentSheet) {
            CommentSheetView(
                client: client,
                galleryUri: galleryUri,
                onDismiss: { showCommentSheet = false },
                onProfileTap: { did in
                    showCommentSheet = false
                    selectedProfileDid = did
                },
                onHashtagTap: { tag in
                    showCommentSheet = false
                    selectedHashtag = tag
                },
                onStoryTap: { author in
                    showCommentSheet = false
                    cardStoryAuthor = author
                },
                onCommentCountChanged: { count in
                    viewModel.gallery?.commentCount = count
                }
            )
        }
        .task {
            guard !isPreview else {
                #if DEBUG
                    viewModel.gallery = PreviewData.gallery1
                    viewModel.comments = PreviewData.comments
                #endif
                return
            }
            await viewModel.load(uri: galleryUri, auth: auth.authContext())
        }
    }

    private func deleteGallery() async {
        guard let authContext = await auth.authContext() else { return }
        let rkey = galleryUri.split(separator: "/").last.map(String.init) ?? ""
        do {
            try await client.deleteGallery(rkey: rkey, auth: authContext)
            deletedGalleryUri = galleryUri
            dismiss()
        } catch {}
    }
}

/// CommentRow stays here since it's shared
struct CommentRow: View {
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @Environment(ViewedStoryStorage.self) private var viewedStories
    let comment: GrainComment
    let userDID: String?
    var isOwn: Bool = false
    var isReply: Bool = false
    var onProfileTap: ((String) -> Void)?
    var onHashtagTap: ((String) -> Void)?
    var onStoryTap: ((GrainStoryAuthor) -> Void)?
    var onReply: (() -> Void)?
    var onDelete: (() -> Void)?
    @State private var expanded = false

    var body: some View {
        if comment.muted == true, !expanded {
            Button {
                expanded = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.slash")
                        .font(.caption)
                    Text("Muted comment")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.leading, isReply ? 50 : 12)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        } else {
            HStack(alignment: .top, spacing: 8) {
                let avatarSize: CGFloat = isReply ? 24 : 28
                StoryRingView(
                    hasStory: storyStatusCache.hasStory(for: comment.author.did),
                    viewed: comment.author.did != userDID && viewedStories.hasViewedAll(did: comment.author.did, storyStatusCache: storyStatusCache),
                    size: avatarSize
                ) {
                    AvatarView(url: comment.author.avatar, size: avatarSize)
                }
                .onTapGesture {
                    if let author = storyStatusCache.author(for: comment.author.did) {
                        onStoryTap?(author)
                    } else {
                        onProfileTap?(comment.author.did)
                    }
                }
                .onLongPressGesture {
                    onProfileTap?(comment.author.did)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(comment.author.displayName ?? comment.author.handle)
                            .font(.subheadline.weight(.semibold))
                        Text(DateFormatting.relativeTime(comment.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    RichTextView(
                        text: comment.text,
                        facets: comment.facets,
                        onMentionTap: onProfileTap,
                        onHashtagTap: onHashtagTap
                    )

                    HStack(spacing: 16) {
                        if onReply != nil {
                            Button {
                                onReply?()
                            } label: {
                                Text("Reply")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.gray)
                            }
                        }
                        if isOwn {
                            Button {
                                onDelete?()
                            } label: {
                                Text("Delete")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.gray)
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer()
            }
            .padding(.leading, isReply ? 50 : 12)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    GalleryDetailView(
        client: .preview,
        galleryUri: "at://did:plc:preview/social.grain.gallery/r1"
    )
    .previewEnvironments()
}

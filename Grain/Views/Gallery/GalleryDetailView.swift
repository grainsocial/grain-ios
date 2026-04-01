import SwiftUI
import NukeUI

struct GalleryDetailView: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: GalleryDetailViewModel
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?
    @State private var commentText = ""
    @State private var isPostingComment = false
    @State private var replyingTo: GrainComment?
    @State private var showDeleteConfirmation = false
    @State private var showReportSheet = false
    @FocusState private var commentFocused: Bool
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

    /// Group comments into roots with their replies underneath.
    private var threadedComments: [(root: GrainComment, replies: [GrainComment])] {
        let roots = viewModel.comments.filter { $0.replyTo == nil }
        let replyMap = Dictionary(grouping: viewModel.comments.filter { $0.replyTo != nil }, by: { $0.replyTo! })
        return roots.map { root in
            (root: root, replies: replyMap[root.uri] ?? [])
        }
    }

    var body: some View {
        ScrollView {
            if viewModel.gallery != nil {
                VStack(spacing: 0) {
                    // Reuse the feed card
                    GalleryCardView(
                        gallery: Binding(
                            get: { viewModel.gallery! },
                            set: { viewModel.gallery = $0 }
                        ),
                        client: client,
                        onProfileTap: { did in
                            selectedProfileDid = did
                        },
                        onHashtagTap: { tag in
                            selectedHashtag = tag
                        }
                    )

                    Divider()

                    // Reply indicator
                    if let replyTarget = replyingTo {
                        HStack {
                            Text("Replying to @\(replyTarget.author.handle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                replyingTo = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    }

                    // Comment input
                    HStack(spacing: 8) {
                        TextField(replyingTo != nil ? "Reply..." : "Add a comment...", text: $commentText)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                            .focused($commentFocused)

                        if !commentText.isEmpty {
                            Button {
                                Task { await postComment() }
                            } label: {
                                Text("Post")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color("AccentColor"))
                            }
                            .disabled(isPostingComment)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Divider()

                    // Threaded comments
                    if !viewModel.comments.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(threadedComments, id: \.root.id) { thread in
                                CommentRow(
                                    comment: thread.root,
                                    isOwn: thread.root.author.did == auth.userDID,
                                    isReply: false,
                                    onProfileTap: { did in selectedProfileDid = did },
                                    onHashtagTap: { tag in selectedHashtag = tag },
                                    onReply: { startReply(to: thread.root) },
                                    onDelete: { Task { await deleteComment(thread.root) } }
                                )

                                ForEach(thread.replies) { reply in
                                    CommentRow(
                                        comment: reply,
                                        isOwn: reply.author.did == auth.userDID,
                                        isReply: true,
                                        onProfileTap: { did in selectedProfileDid = did },
                                        onHashtagTap: { tag in selectedHashtag = tag },
                                        onDelete: { Task { await deleteComment(reply) } }
                                    )
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedProfileDid) { did in
            ProfileView(client: client, did: did)
        }
        .navigationDestination(item: $selectedHashtag) { tag in
            HashtagFeedView(client: client, tag: tag)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let gallery = viewModel.gallery {
                        if gallery.creator.did == auth.userDID {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete Gallery", systemImage: "trash")
                            }
                        } else {
                            Button {
                                showReportSheet = true
                            } label: {
                                Label("Report", systemImage: "flag")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.primary)
                }
                .disabled(viewModel.gallery == nil)
            }
        }
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
        .task {
            await viewModel.load(uri: galleryUri, auth: auth.authContext())
        }
    }

    private func startReply(to comment: GrainComment) {
        replyingTo = comment
        commentFocused = true
    }

    private func postComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let authContext = auth.authContext() else { return }

        isPostingComment = true
        var recordDict: [String: String] = [
            "text": text,
            "subject": galleryUri,
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let replyTarget = replyingTo {
            recordDict["replyTo"] = replyTarget.uri
        }
        let record = AnyCodable(recordDict)
        let repo = TokenStorage.userDID ?? ""
        do {
            _ = try await client.createRecord(collection: "social.grain.comment", repo: repo, record: record, auth: authContext)
            commentText = ""
            replyingTo = nil
            commentFocused = false
            await viewModel.load(uri: galleryUri, auth: authContext)
        } catch {
            // Silently fail for now
        }
        isPostingComment = false
    }

    private func deleteGallery() async {
        guard let authContext = auth.authContext() else { return }
        let rkey = galleryUri.split(separator: "/").last.map(String.init) ?? ""
        do {
            try await client.deleteGallery(rkey: rkey, auth: authContext)
            deletedGalleryUri = galleryUri
            dismiss()
        } catch {
            // Silently fail for now
        }
    }

    private func deleteComment(_ comment: GrainComment) async {
        guard let authContext = auth.authContext() else { return }
        let rkey = comment.uri.split(separator: "/").last.map(String.init) ?? ""
        do {
            try await client.deleteRecord(collection: "social.grain.comment", rkey: rkey, auth: authContext)
            viewModel.comments.removeAll { $0.uri == comment.uri }
        } catch {
            // Silently fail for now
        }
    }
}

struct CommentRow: View {
    let comment: GrainComment
    var isOwn: Bool = false
    var isReply: Bool = false
    var onProfileTap: ((String) -> Void)?
    var onHashtagTap: ((String) -> Void)?
    var onReply: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(url: comment.author.avatar, size: isReply ? 24 : 28)
                .onTapGesture { onProfileTap?(comment.author.did) }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(comment.author.displayName ?? comment.author.handle)
                        .font(.subheadline.weight(.semibold))
                    Text(relativeTime(comment.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                RichTextView(
                    text: comment.text,
                    facets: comment.facets,
                    onMentionTap: onProfileTap,
                    onHashtagTap: onHashtagTap
                )

                // Actions
                HStack(spacing: 16) {
                    if !isReply, onReply != nil {
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

    private func relativeTime(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return "" }
        let interval = Date().timeIntervalSince(date)

        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }
        return "\(Int(interval / 604800))w"
    }
}

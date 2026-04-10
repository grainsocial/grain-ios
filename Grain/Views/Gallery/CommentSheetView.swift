import SwiftUI

struct CommentSheetView: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: GalleryDetailViewModel
    @State private var commentText = ""
    @State private var isPostingComment = false
    @State private var replyingTo: GrainComment?
    @State private var mentionState = MentionAutocompleteState()
    @FocusState private var commentFocused: Bool

    let client: XRPCClient
    let galleryUri: String
    var onDismiss: () -> Void = {}
    var onProfileTap: ((String) -> Void)?
    var onHashtagTap: ((String) -> Void)?
    var onStoryTap: ((GrainStoryAuthor) -> Void)?
    var onCommentCountChanged: ((Int) -> Void)?

    init(
        client: XRPCClient,
        galleryUri: String,
        onDismiss: @escaping () -> Void = {},
        onProfileTap: ((String) -> Void)? = nil,
        onHashtagTap: ((String) -> Void)? = nil,
        onStoryTap: ((GrainStoryAuthor) -> Void)? = nil,
        onCommentCountChanged: ((Int) -> Void)? = nil
    ) {
        self.client = client
        self.galleryUri = galleryUri
        self.onDismiss = onDismiss
        self.onProfileTap = onProfileTap
        self.onHashtagTap = onHashtagTap
        self.onStoryTap = onStoryTap
        self.onCommentCountChanged = onCommentCountChanged
        _viewModel = State(initialValue: GalleryDetailViewModel(client: client))
    }

    private var threadedComments: [(root: GrainComment, replies: [GrainComment])] {
        let roots = viewModel.comments.filter { $0.replyTo == nil }
        let replyMap = Dictionary(grouping: viewModel.comments.filter { $0.replyTo != nil }, by: { $0.replyTo! })
        return roots.map { root in
            (root: root, replies: replyMap[root.uri] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    if viewModel.comments.isEmpty, !viewModel.isLoading {
                        Text("No comments yet")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if viewModel.isLoading, viewModel.comments.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(threadedComments, id: \.root.id) { thread in
                                CommentRow(
                                    comment: thread.root,
                                    userDID: auth.userDID,
                                    isOwn: thread.root.author.did == auth.userDID,
                                    isReply: false,
                                    onProfileTap: { did in
                                        onDismiss()
                                        onProfileTap?(did)
                                    },
                                    onHashtagTap: { tag in
                                        onDismiss()
                                        onHashtagTap?(tag)
                                    },
                                    onStoryTap: { author in
                                        onDismiss()
                                        onStoryTap?(author)
                                    },
                                    onReply: { startReply(to: thread.root) },
                                    onDelete: { Task { await deleteComment(thread.root) } }
                                )

                                ForEach(thread.replies) { reply in
                                    CommentRow(
                                        comment: reply,
                                        userDID: auth.userDID,
                                        isOwn: reply.author.did == auth.userDID,
                                        isReply: true,
                                        onProfileTap: { did in
                                            onDismiss()
                                            onProfileTap?(did)
                                        },
                                        onHashtagTap: { tag in
                                            onDismiss()
                                            onHashtagTap?(tag)
                                        },
                                        onStoryTap: { author in
                                            onDismiss()
                                            onStoryTap?(author)
                                        },
                                        onReply: { startReplyToReply(reply, root: thread.root) },
                                        onDelete: { Task { await deleteComment(reply) } }
                                    )
                                }
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        MentionSuggestionOverlay(state: mentionState) { suggestion in
                            mentionState.complete(handle: suggestion.handle, in: &commentText)
                        }

                        if let replyTarget = replyingTo {
                            HStack {
                                Text("Replying to @\(replyTarget.author.handle)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    replyingTo = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                        }

                        GlassEffectContainer(spacing: 8) {
                            HStack(alignment: .bottom, spacing: 10) {
                                TextField(
                                    replyingTo != nil ? "Reply..." : "Add a comment...",
                                    text: $commentText,
                                    axis: .vertical
                                )
                                .textFieldStyle(.plain)
                                .font(.body)
                                .focused($commentFocused)
                                .lineLimit(1 ... 6)
                                .onChange(of: commentText) { mentionState.update(text: commentText) }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .glassEffect(.regular, in: .capsule)

                                let isEmpty = commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                if !isEmpty {
                                    Button {
                                        Task { await postComment() }
                                    } label: {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .font(.system(size: 28))
                                            .foregroundStyle(Color("AccentColor"))
                                            .frame(width: 44, height: 44)
                                    }
                                    .glassEffect(.regular.interactive(), in: .circle)
                                    .disabled(isPostingComment)
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: commentText.isEmpty)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await viewModel.load(uri: galleryUri, auth: auth.authContext())
        }
    }

    private func startReply(to comment: GrainComment) {
        replyingTo = comment
        commentText = ""
        commentFocused = true
    }

    private func startReplyToReply(_ reply: GrainComment, root: GrainComment) {
        replyingTo = root
        commentText = "@\(reply.author.handle) "
        commentFocused = true
    }

    private func postComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let authContext = await auth.authContext() else { return }

        isPostingComment = true
        var recordDict: [String: String] = [
            "text": text,
            "subject": galleryUri,
            "createdAt": DateFormatting.nowISO(),
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
            onCommentCountChanged?(viewModel.comments.count)
        } catch {}
        isPostingComment = false
    }

    private func deleteComment(_ comment: GrainComment) async {
        guard let authContext = await auth.authContext() else { return }
        let rkey = comment.uri.split(separator: "/").last.map(String.init) ?? ""
        do {
            try await client.deleteRecord(collection: "social.grain.comment", rkey: rkey, auth: authContext)
            viewModel.comments.removeAll { $0.uri == comment.uri }
            onCommentCountChanged?(viewModel.comments.count)
        } catch {}
    }
}

import SwiftUI

struct StoryCommentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @Environment(ViewedStoryStorage.self) private var viewedStories
    let viewModel: StoryCommentsViewModel
    let storyUri: String
    let client: XRPCClient
    var focusInput: Bool = false
    var onProfileTap: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    @State private var commentText = ""
    @State private var replyingTo: GrainComment?
    @State private var mentionState = MentionAutocompleteState()
    @FocusState private var commentFocused: Bool

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
                commentList
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    MentionSuggestionOverlay(state: mentionState) { suggestion in
                        mentionState.complete(handle: suggestion.handle, in: &commentText)
                    }
                    glassInputPill
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss?()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            await viewModel.loadComments(storyUri: storyUri, auth: auth.authContext())
            if focusInput {
                commentFocused = true
            }
        }
    }

    // MARK: - Comment list

    @ViewBuilder
    private var commentList: some View {
        if viewModel.isLoading, viewModel.comments.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else if viewModel.comments.isEmpty {
            Spacer()
            Text("No comments yet")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(threadedComments, id: \.root.id) { thread in
                        CommentRow(
                            comment: thread.root,
                            userDID: auth.userDID,
                            isOwn: thread.root.author.did == auth.userDID,
                            isReply: false,
                            onProfileTap: onProfileTap,
                            onHashtagTap: nil,
                            onStoryTap: nil,
                            onReply: { startReply(to: thread.root) },
                            onDelete: { Task { await deleteComment(thread.root) } }
                        )

                        ForEach(thread.replies) { reply in
                            CommentRow(
                                comment: reply,
                                userDID: auth.userDID,
                                isOwn: reply.author.did == auth.userDID,
                                isReply: true,
                                onProfileTap: onProfileTap,
                                onHashtagTap: nil,
                                onStoryTap: nil,
                                onReply: { startReplyToReply(reply, root: thread.root) },
                                onDelete: { Task { await deleteComment(reply) } }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Glass input pill

    private var glassInputPill: some View {
        VStack(spacing: 0) {
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
                    TextField(replyingTo != nil ? "Reply..." : "Add a comment...", text: $commentText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($commentFocused)
                        .lineLimit(1 ... 5)
                        .onChange(of: commentText) { mentionState.update(text: commentText) }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
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
                        .disabled(viewModel.isPostingComment)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: commentText.isEmpty)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

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
        guard let authContext = await auth.authContext() else { return }
        let text = commentText
        let reply = replyingTo
        commentText = ""
        replyingTo = nil
        commentFocused = false
        await viewModel.postComment(text: text, storyUri: storyUri, replyTo: reply, auth: authContext)
    }

    private func deleteComment(_ comment: GrainComment) async {
        guard let authContext = await auth.authContext() else { return }
        await viewModel.deleteComment(comment, storyUri: storyUri, auth: authContext)
    }
}

#Preview {
    let vm = StoryCommentsViewModel(client: XRPCClient(baseURL: AuthManager.serverURL))
    vm.comments = PreviewData.storyComments
    vm.totalCount = PreviewData.storyComments.count

    return Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            StoryCommentSheet(
                viewModel: vm,
                storyUri: PreviewData.stories[0].uri,
                client: XRPCClient(baseURL: AuthManager.serverURL)
            )
            .environment(AuthManager())
            .environment(StoryStatusCache())
            .environment(ViewedStoryStorage())
        }
}

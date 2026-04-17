import SwiftUI

enum CommentDismissStyle {
    case xmark
    case done
}

struct CommentSheetContent: View {
    let comments: [GrainComment]
    let isLoading: Bool
    let isPostingComment: Bool
    var client: XRPCClient?

    var onPost: (String, GrainComment?) async -> Void
    var onDelete: (GrainComment) async -> Void

    var onDismiss: () -> Void = {}
    var onProfileTap: ((String) -> Void)?
    var onHashtagTap: ((String) -> Void)?
    var onStoryTap: ((GrainStoryAuthor) -> Void)?

    var dismissStyle: CommentDismissStyle = .xmark
    var focusOnAppear: Bool = false

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var commentText = ""
    @State private var replyingTo: GrainComment?
    @State private var mentionState = MentionAutocompleteState()
    @FocusState private var commentFocused: Bool

    private var threadedComments: [(root: GrainComment, replies: [GrainComment])] {
        let roots = comments.filter { $0.replyTo == nil }
        let replyMap = Dictionary(grouping: comments.filter { $0.replyTo != nil }, by: { $0.replyTo! })
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
                switch dismissStyle {
                case .xmark:
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Close comments")
                    }
                case .done:
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            onDismiss()
                        }
                    }
                }
            }
        }
        .task {
            if focusOnAppear {
                commentFocused = true
            }
        }
    }

    // MARK: - Comment list

    @ViewBuilder
    private var commentList: some View {
        if isLoading, comments.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else if comments.isEmpty {
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
                            client: client ?? XRPCClient(baseURL: AuthManager.serverURL),
                            userDID: auth.userDID,
                            isOwn: thread.root.author.did == auth.userDID,
                            isReply: false,
                            onProfileTap: onProfileTap,
                            onHashtagTap: onHashtagTap,
                            onStoryTap: onStoryTap,
                            onReply: { startReply(to: thread.root) },
                            onDelete: { Task { await onDelete(thread.root) } }
                        )

                        ForEach(thread.replies) { reply in
                            CommentRow(
                                comment: reply,
                                client: client ?? XRPCClient(baseURL: AuthManager.serverURL),
                                userDID: auth.userDID,
                                isOwn: reply.author.did == auth.userDID,
                                isReply: true,
                                onProfileTap: onProfileTap,
                                onHashtagTap: onHashtagTap,
                                onStoryTap: onStoryTap,
                                onReply: { startReplyToReply(reply, root: thread.root) },
                                onDelete: { Task { await onDelete(reply) } }
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
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                    Text("Replying to")
                        .foregroundStyle(.secondary)
                    Text("@\(replyTarget.author.handle)")
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        replyingTo = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel reply")
                }
                .font(.subheadline.weight(.medium))
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.top, 6)
            }

            GlassEffectContainer(spacing: 8) {
                let isEmpty = commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                HStack(alignment: .bottom, spacing: 0) {
                    TextField(replyingTo != nil ? "Reply..." : "Add a comment...", text: $commentText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($commentFocused)
                        .lineLimit(1 ... 5)
                        .onChange(of: commentText) { mentionState.update(text: commentText) }
                        .padding(.leading, 18)
                        .padding(.trailing, 8)
                        .padding(.vertical, 12)

                    if !isEmpty {
                        Button {
                            Task { await postComment() }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor, in: .circle)
                        }
                        .accessibilityLabel("Send comment")
                        .buttonStyle(.plain)
                        .disabled(isPostingComment)
                        .padding(.trailing, 8)
                        .padding(.bottom, 7)
                        .transition(
                            .asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            )
                        )
                    }
                }
                .glassEffect(.regular.tint(.primary.opacity(0.1)), in: .capsule)
                .clipped()
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isEmpty)
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
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let reply = replyingTo
        commentText = ""
        replyingTo = nil
        commentFocused = false
        await onPost(text, reply)
    }
}

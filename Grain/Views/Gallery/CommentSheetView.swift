import SwiftUI

struct CommentSheetView: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: GalleryDetailViewModel
    @State private var isPostingComment = false

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

    var body: some View {
        CommentSheetContent(
            comments: viewModel.comments,
            isLoading: viewModel.isLoading,
            isPostingComment: isPostingComment,
            onPost: { text, replyTo in
                guard let authContext = await auth.authContext() else { return }
                isPostingComment = true
                do {
                    _ = try await CommentService.create(
                        subject: galleryUri,
                        text: text,
                        replyTo: replyTo?.uri,
                        client: client,
                        auth: authContext
                    )
                    await viewModel.load(uri: galleryUri, auth: authContext)
                    onCommentCountChanged?(viewModel.comments.count)
                } catch {}
                isPostingComment = false
            },
            onDelete: { comment in
                guard let authContext = await auth.authContext() else { return }
                do {
                    try await CommentService.delete(commentUri: comment.uri, client: client, auth: authContext)
                    viewModel.comments.removeAll { $0.uri == comment.uri }
                    onCommentCountChanged?(viewModel.comments.count)
                } catch {}
            },
            onDismiss: onDismiss,
            onProfileTap: onProfileTap.map { cb in { did in onDismiss(); cb(did) } },
            onHashtagTap: onHashtagTap.map { cb in { tag in onDismiss(); cb(tag) } },
            onStoryTap: onStoryTap.map { cb in { author in onDismiss(); cb(author) } },
            dismissStyle: .xmark
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await viewModel.load(uri: galleryUri, auth: auth.authContext())
        }
    }
}

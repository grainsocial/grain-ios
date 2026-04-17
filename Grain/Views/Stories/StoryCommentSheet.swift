import os
import SwiftUI

private let scsLogger = Logger(subsystem: "social.grain.grain", category: "StoryCommentSheet")
private let scsSignposter = OSSignposter(subsystem: "social.grain.grain", category: "StoryCommentSheet")

struct StoryCommentSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @Environment(ViewedStoryStorage.self) private var viewedStories
    let viewModel: StoryCommentsViewModel
    let storyUri: String
    let client: XRPCClient
    var focusInput: Bool = false
    var onProfileTap: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        CommentSheetContent(
            comments: viewModel.comments,
            isLoading: viewModel.isLoading,
            isPostingComment: viewModel.isPostingComment,
            client: client,
            onPost: { text, replyTo in
                guard let authContext = await auth.authContext() else { return }
                await viewModel.postComment(text: text, storyUri: storyUri, replyTo: replyTo, auth: authContext)
            },
            onDelete: { comment in
                guard let authContext = await auth.authContext() else { return }
                await viewModel.deleteComment(comment, storyUri: storyUri, auth: authContext)
            },
            onDismiss: { onDismiss?() },
            onProfileTap: onProfileTap,
            dismissStyle: .xmark,
            focusOnAppear: false
        )
        .presentationDetents([.large])
        .onAppear {
            scsLogger.info("[onAppear] uri=\(storyUri) focusInput=\(focusInput)")
            scsSignposter.emitEvent("sheet.onAppear", "focusInput=\(focusInput)")
        }
        .onDisappear {
            scsLogger.info("[onDisappear] uri=\(storyUri)")
            scsSignposter.emitEvent("sheet.onDisappear")
        }
        .task {
            scsSignposter.emitEvent("task.load.begin")
            await viewModel.loadComments(storyUri: storyUri, auth: auth.authContext())
            scsSignposter.emitEvent("task.load.end")
        }
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

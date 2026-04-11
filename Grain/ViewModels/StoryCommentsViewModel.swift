import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "StoryComments")
private let scvmSignposter = OSSignposter(subsystem: "social.grain.grain", category: "StoryComments")

@Observable
@MainActor
final class StoryCommentsViewModel {
    var comments: [GrainComment] = []
    // `firstComment` is `response.comments.first`, which is the oldest/chronological
    // comment on the story. Ideally this would prefer comments from followed users,
    // then fall back to most-liked, but the getGalleryThread endpoint doesn't return
    // viewer state on authors or likeCount on comments. Bumping the preview fetch
    // from limit=1 to support client-side selection also adds ~100ms per request.
    // Revisit when the backend hydrates those fields.
    var firstComment: GrainComment?
    var totalCount: Int = 0
    var isLoading = false
    var isPostingComment = false

    private(set) var activeStoryUri: String?
    private var commentCursor: String?
    private var hasMoreComments = true
    private var previewCache: [String: CachedPreview] = [:]
    private let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
    }

    // MARK: - Story Switching

    func switchToStory(uri: String, auth: AuthContext? = nil) {
        guard uri != activeStoryUri else { return }
        activeStoryUri = uri
        comments = []
        commentCursor = nil
        hasMoreComments = true

        if let cached = previewCache[uri] {
            firstComment = cached.comment
            totalCount = cached.count
        } else {
            firstComment = nil
            totalCount = 0
            Task { await loadPreview(storyUri: uri, auth: auth) }
        }
    }

    // MARK: - Preview Loading

    /// Fires background preview loads for the given story URIs. Already-cached URIs are skipped.
    func prefetchPreviews(for storyUris: [String], auth: AuthContext? = nil) {
        for uri in storyUris where previewCache[uri] == nil {
            Task { await loadPreview(storyUri: uri, auth: auth) }
        }
    }

    func loadPreview(storyUri: String, auth: AuthContext? = nil) async {
        if let cached = previewCache[storyUri] {
            if activeStoryUri == nil || activeStoryUri == storyUri {
                firstComment = cached.comment
                totalCount = cached.count
            }
            return
        }

        do {
            let response = try await client.getGalleryThread(gallery: storyUri, limit: 1, auth: auth)
            let preview = CachedPreview(
                comment: response.comments.first,
                count: response.totalCount ?? response.comments.count
            )
            previewCache[storyUri] = preview
            if activeStoryUri == nil || activeStoryUri == storyUri {
                firstComment = preview.comment
                totalCount = preview.count
            }
        } catch {
            logger.error("Failed to load comment preview: \(error)")
        }
    }

    // MARK: - Full Comment Loading

    func loadComments(storyUri: String, auth: AuthContext? = nil) async {
        guard !isLoading else {
            scvmSignposter.emitEvent("loadComments.skipped", "reason=already-loading")
            return
        }
        let state = scvmSignposter.beginInterval("loadComments", "uri=\(storyUri)")
        isLoading = true
        commentCursor = nil
        hasMoreComments = true

        do {
            let response = try await client.getGalleryThread(gallery: storyUri, auth: auth)
            comments = response.comments
            commentCursor = response.cursor
            hasMoreComments = response.cursor != nil
            totalCount = response.totalCount ?? response.comments.count

            // Update cache with fresh data
            let latest = response.comments.first
            previewCache[storyUri] = CachedPreview(comment: latest, count: totalCount)
            if storyUri == activeStoryUri {
                firstComment = latest
            }
            let count = response.comments.count
            scvmSignposter.endInterval("loadComments", state, "count=\(count)")
        } catch {
            logger.error("Failed to load comments: \(error)")
            scvmSignposter.endInterval("loadComments", state, "error")
        }
        isLoading = false
    }

    func loadMoreComments(storyUri: String, auth: AuthContext? = nil) async {
        guard !isLoading, hasMoreComments, let cursor = commentCursor else { return }
        isLoading = true

        do {
            let response = try await client.getGalleryThread(gallery: storyUri, cursor: cursor, auth: auth)
            comments.append(contentsOf: response.comments)
            commentCursor = response.cursor
            hasMoreComments = response.cursor != nil
        } catch {
            logger.error("Failed to load more comments: \(error)")
        }
        isLoading = false
    }

    // MARK: - Comment CRUD

    func postComment(text: String, storyUri: String, replyTo: GrainComment? = nil, auth: AuthContext) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isPostingComment = true
        do {
            _ = try await CommentService.create(
                subject: storyUri,
                text: trimmed,
                replyTo: replyTo?.uri,
                client: client,
                auth: auth
            )
            previewCache.removeValue(forKey: storyUri)
            await loadComments(storyUri: storyUri, auth: auth)
        } catch {
            logger.error("Failed to post comment: \(error)")
        }
        isPostingComment = false
    }

    func deleteComment(_ comment: GrainComment, storyUri: String, auth: AuthContext) async {
        do {
            try await CommentService.delete(commentUri: comment.uri, client: client, auth: auth)
            comments.removeAll { $0.uri == comment.uri }
            totalCount = max(totalCount - 1, 0)

            // Update cache
            let latest = comments.first
            previewCache[storyUri] = CachedPreview(comment: latest, count: totalCount)
            if storyUri == activeStoryUri {
                firstComment = latest
            }
        } catch {
            logger.error("Failed to delete comment: \(error)")
        }
    }
}

// MARK: - Cache

private struct CachedPreview {
    let comment: GrainComment?
    let count: Int
}

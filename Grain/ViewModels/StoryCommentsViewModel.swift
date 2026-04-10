import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "StoryComments")

@Observable
@MainActor
final class StoryCommentsViewModel {
    var comments: [GrainComment] = []
    var latestComment: GrainComment?
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
            latestComment = cached.comment
            totalCount = cached.count
        } else {
            latestComment = nil
            totalCount = 0
            Task { await loadPreview(storyUri: uri, auth: auth) }
        }
    }

    // MARK: - Preview Loading

    func loadPreview(storyUri: String, auth: AuthContext? = nil) async {
        if let cached = previewCache[storyUri] {
            latestComment = cached.comment
            totalCount = cached.count
            return
        }

        do {
            let response = try await client.getStoryThread(story: storyUri, limit: 1, auth: auth)
            let preview = CachedPreview(
                comment: response.comments.first,
                count: response.totalCount ?? response.comments.count
            )
            previewCache[storyUri] = preview
            if storyUri == activeStoryUri {
                latestComment = preview.comment
                totalCount = preview.count
            }
        } catch {
            logger.error("Failed to load comment preview: \(error)")
        }
    }

    // MARK: - Full Comment Loading

    func loadComments(storyUri: String, auth: AuthContext? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        commentCursor = nil
        hasMoreComments = true

        do {
            let response = try await client.getStoryThread(story: storyUri, auth: auth)
            comments = response.comments
            commentCursor = response.cursor
            hasMoreComments = response.cursor != nil
            totalCount = response.totalCount ?? response.comments.count

            // Update cache with fresh data
            let latest = response.comments.first
            previewCache[storyUri] = CachedPreview(comment: latest, count: totalCount)
            if storyUri == activeStoryUri {
                latestComment = latest
            }
        } catch {
            logger.error("Failed to load comments: \(error)")
        }
        isLoading = false
    }

    func loadMoreComments(storyUri: String, auth: AuthContext? = nil) async {
        guard !isLoading, hasMoreComments, let cursor = commentCursor else { return }
        isLoading = true

        do {
            let response = try await client.getStoryThread(story: storyUri, cursor: cursor, auth: auth)
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
        var recordDict: [String: String] = [
            "text": trimmed,
            "subject": storyUri,
            "createdAt": DateFormatting.nowISO(),
        ]
        if let replyTarget = replyTo {
            recordDict["replyTo"] = replyTarget.uri
        }
        let record = AnyCodable(recordDict)
        let repo = TokenStorage.userDID ?? ""

        do {
            _ = try await client.createRecord(collection: "social.grain.comment", repo: repo, record: record, auth: auth)
            previewCache.removeValue(forKey: storyUri)
            await loadComments(storyUri: storyUri, auth: auth)
        } catch {
            logger.error("Failed to post comment: \(error)")
        }
        isPostingComment = false
    }

    func deleteComment(_ comment: GrainComment, storyUri: String, auth: AuthContext) async {
        let rkey = comment.uri.split(separator: "/").last.map(String.init) ?? ""
        do {
            try await client.deleteRecord(collection: "social.grain.comment", rkey: rkey, auth: auth)
            comments.removeAll { $0.uri == comment.uri }
            totalCount = max(totalCount - 1, 0)

            // Update cache
            let latest = comments.first
            previewCache[storyUri] = CachedPreview(comment: latest, count: totalCount)
            if storyUri == activeStoryUri {
                latestComment = latest
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

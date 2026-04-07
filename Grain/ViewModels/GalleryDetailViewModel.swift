import Foundation

@Observable
@MainActor
final class GalleryDetailViewModel {
    var gallery: GrainGallery?
    var comments: [GrainComment] = []
    var isLoading = false
    var error: Error?

    private var commentCursor: String?
    private var hasMoreComments = true
    private let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
    }

    func load(uri: String, auth: AuthContext? = nil) async {
        isLoading = true
        error = nil

        do {
            let galleryResult = try await client.getGallery(uri: uri, auth: auth)
            let commentsResult = try await client.getGalleryThread(gallery: uri, auth: auth)
            gallery = galleryResult.gallery
            comments = commentsResult.comments
            commentCursor = commentsResult.cursor
            hasMoreComments = commentsResult.cursor != nil
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func loadMoreComments(galleryUri: String, auth: AuthContext? = nil) async {
        guard !isLoading, hasMoreComments, let cursor = commentCursor else { return }
        isLoading = true

        do {
            let response = try await client.getGalleryThread(gallery: galleryUri, cursor: cursor, auth: auth)
            comments.append(contentsOf: response.comments)
            commentCursor = response.cursor
            hasMoreComments = response.cursor != nil
        } catch {
            self.error = error
        }
        isLoading = false
    }
}

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
            async let galleryResponse = client.getGallery(uri: uri, auth: auth)
            async let commentsResponse = client.getGalleryThread(gallery: uri, auth: auth)

            let (g, c) = try await (galleryResponse, commentsResponse)
            gallery = g.gallery
            comments = c.comments
            commentCursor = c.cursor
            hasMoreComments = c.cursor != nil
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

    func toggleFavorite(auth: AuthContext?) async {
        guard let gallery, let auth else { return }
        if let favUri = gallery.viewer?.fav {
            // Unfavorite
            let rkey = favUri.split(separator: "/").last.map(String.init) ?? ""
            try? await client.deleteRecord(collection: "social.grain.favorite", rkey: rkey, auth: auth)
            self.gallery?.viewer?.fav = nil
            self.gallery?.favCount = (self.gallery?.favCount ?? 1) - 1
        } else {
            // Favorite
            let record = AnyCodable([
                "subject": gallery.uri,
                "createdAt": ISO8601DateFormatter().string(from: Date())
            ])
            let repo = TokenStorage.userDID ?? ""
            let response = try? await client.createRecord(collection: "social.grain.favorite", repo: repo, record: record, auth: auth)
            self.gallery?.viewer = GalleryViewerState(fav: response?.uri)
            self.gallery?.favCount = (self.gallery?.favCount ?? 0) + 1
        }
    }
}

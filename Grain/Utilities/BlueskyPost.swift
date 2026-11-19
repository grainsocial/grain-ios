import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "BlueskyPost")

enum BlueskyPost {
    static let collection = "app.bsky.feed.post"

    /// Cross-post a gallery or story to Bluesky as grain-serve words it.
    ///
    /// `social.grain.gallery.getCrossPost` answers the whole post record, its
    /// photos the blobs the subject already holds in the author's repository,
    /// and it is written as it is.
    ///
    /// Pass `rkey` when the caller might run this more than once — a resumed
    /// gallery publish, say. With a record key of our own the write becomes an
    /// overwrite instead of a second post on the user's timeline; `createdAt`
    /// keeps that overwrite's timestamp the first attempt's.
    static func create(
        subject: String,
        client: XRPCClient,
        repo: String,
        auth: AuthContext,
        rkey: String? = nil,
        createdAt: String? = nil
    ) async throws {
        logger.info("Creating Bluesky cross-post for \(subject)")
        guard var record = try await client.getCrossPost(subject: subject).post.dictValue else {
            throw XRPCError.httpError(statusCode: 0, body: Data("getCrossPost answered no post record".utf8))
        }
        if let createdAt {
            record["createdAt"] = AnyCodable(createdAt)
        }

        let result: CreateRecordResponse = if let rkey {
            try await client.putRecord(collection: collection, rkey: rkey, record: AnyCodable(record), repo: repo, auth: auth)
        } else {
            try await client.createRecord(collection: collection, repo: repo, record: AnyCodable(record), auth: auth)
        }
        logger.info("Bluesky cross-post created: uri=\(result.uri ?? "nil"), cid=\(result.cid ?? "nil")")
    }
}

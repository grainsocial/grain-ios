import Foundation

/// Shared helpers for creating and deleting `social.grain.comment` records.
/// Used by both gallery and story comment flows.
enum CommentService {
    static let collection = "social.grain.comment"

    /// Creates a comment record with optional reply-to.
    static func create(
        subject: String,
        text: String,
        replyTo: String? = nil,
        client: XRPCClient,
        auth: AuthContext
    ) async throws -> CreateRecordResponse {
        let facets = await BlueskyPost.parseTextToFacets(text)
        var recordDict: [String: AnyCodable] = [
            "text": AnyCodable(text),
            "subject": AnyCodable(subject),
            "createdAt": AnyCodable(DateFormatting.nowISO()),
        ]
        if let replyTo {
            recordDict["replyTo"] = AnyCodable(replyTo)
        }
        if !facets.isEmpty {
            recordDict["facets"] = AnyCodable(facets.map { $0.toAnyCodableDict() } as [[String: AnyCodable]])
        }
        let repo = TokenStorage.userDID ?? ""
        return try await client.createRecord(
            collection: collection,
            repo: repo,
            record: AnyCodable(recordDict),
            auth: auth
        )
    }

    /// Deletes a comment by its full URI (extracts the rkey).
    static func delete(
        commentUri: String,
        client: XRPCClient,
        auth: AuthContext
    ) async throws {
        let rkey = commentUri.split(separator: "/").last.map(String.init) ?? ""
        try await client.deleteRecord(
            collection: collection,
            rkey: rkey,
            auth: auth
        )
    }
}

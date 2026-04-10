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
        var recordDict: [String: String] = [
            "text": text,
            "subject": subject,
            "createdAt": DateFormatting.nowISO(),
        ]
        if let replyTo {
            recordDict["replyTo"] = replyTo
        }
        let record = AnyCodable(recordDict)
        let repo = TokenStorage.userDID ?? ""
        return try await client.createRecord(
            collection: collection,
            repo: repo,
            record: record,
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

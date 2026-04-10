import Foundation

/// Shared helpers for creating and deleting `social.grain.favorite` records.
/// Used by both gallery and story favorite flows. Callers manage their own
/// optimistic state updates (e.g. viewer.fav, favCount).
enum FavoriteService {
    static let collection = "social.grain.favorite"

    /// Creates a favorite record pointing at the given subject URI.
    static func create(
        subject: String,
        client: XRPCClient,
        auth: AuthContext
    ) async throws -> CreateRecordResponse {
        let record = AnyCodable([
            "subject": subject,
            "createdAt": DateFormatting.nowISO(),
        ])
        let repo = TokenStorage.userDID ?? ""
        return try await client.createRecord(
            collection: collection,
            repo: repo,
            record: record,
            auth: auth
        )
    }

    /// Deletes a favorite by its full URI (extracts the rkey).
    static func delete(
        favoriteUri: String,
        client: XRPCClient,
        auth: AuthContext
    ) async throws {
        let rkey = favoriteUri.split(separator: "/").last.map(String.init) ?? ""
        try await client.deleteRecord(
            collection: collection,
            rkey: rkey,
            auth: auth
        )
    }
}

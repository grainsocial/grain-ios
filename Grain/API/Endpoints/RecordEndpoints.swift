import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "Records")

struct CreateRecordInput: Codable, Sendable {
    let collection: String
    let repo: String
    let record: AnyCodable
}

struct CreateRecordResponse: Codable, Sendable {
    var uri: String?
    var cid: String?
}

struct PutRecordInput: Codable, Sendable {
    let collection: String
    let rkey: String
    let record: AnyCodable
    let repo: String
}

struct DeleteRecordInput: Codable, Sendable {
    let repo: String
    let collection: String
    let rkey: String
}

struct IndexRecordsInput: Codable, Sendable {
    let uris: [String]
}

struct DeleteGalleryInput: Codable, Sendable {
    let rkey: String
}

struct GetRecordResponse: Codable, Sendable {
    var uri: String?
    var cid: String?
    var record: AnyCodable?
}

/// One write inside a `com.atproto.repo.applyWrites` batch.
///
/// Every write names its rkey, so a batch that has to be retried addresses
/// the same records both times.
struct ApplyWrite: Codable, Sendable {
    let type: String
    let collection: String
    let rkey: String
    /// The record, for a create or an update.
    let value: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case collection
        case rkey
        case value
    }

    static func create(collection: String, rkey: String, value: AnyCodable) -> ApplyWrite {
        ApplyWrite(type: "com.atproto.repo.applyWrites#create", collection: collection, rkey: rkey, value: value)
    }

    static func update(collection: String, rkey: String, value: AnyCodable) -> ApplyWrite {
        ApplyWrite(type: "com.atproto.repo.applyWrites#update", collection: collection, rkey: rkey, value: value)
    }

    static func delete(collection: String, rkey: String) -> ApplyWrite {
        ApplyWrite(type: "com.atproto.repo.applyWrites#delete", collection: collection, rkey: rkey, value: nil)
    }
}

struct ApplyWritesInput: Codable, Sendable {
    let repo: String
    let writes: [ApplyWrite]
}

struct ApplyWriteResult: Codable, Sendable {
    var uri: String?
    var cid: String?
}

struct ApplyWritesResponse: Codable, Sendable {
    var results: [ApplyWriteResult]?
}

/// Writes go to the account's PDS as `com.atproto.repo.*` calls, with the
/// account's DID as the repo. Each one that lands is then handed to the
/// AppView's `social.grain.sync.indexRecords`, so the next read sees it
/// without waiting on the firehose.
extension XRPCClient {
    /// How many URIs one `indexRecords` call takes.
    static let indexBatchSize = 25

    func getRecord(uri: String, auth: AuthContext? = nil) async throws -> GetRecordResponse {
        try await query("dev.hatk.getRecord", params: ["uri": uri], auth: auth, as: GetRecordResponse.self)
    }

    func createRecord(collection: String, repo: String, record: AnyCodable, auth: AuthContext? = nil) async throws -> CreateRecordResponse {
        let response = try await procedure(
            "com.atproto.repo.createRecord",
            input: CreateRecordInput(collection: collection, repo: repo, record: record),
            auth: auth,
            as: CreateRecordResponse.self
        )
        await indexRecords([response.uri].compactMap(\.self), auth: auth)
        return response
    }

    /// Create or overwrite the record at `rkey`. `repo` defaults to the
    /// signed-in account's.
    func putRecord(collection: String, rkey: String, record: AnyCodable, repo: String? = nil, auth: AuthContext? = nil) async throws -> CreateRecordResponse {
        let repo = repo ?? auth?.did ?? ""
        let response = try await procedure(
            "com.atproto.repo.putRecord",
            input: PutRecordInput(collection: collection, rkey: rkey, record: record, repo: repo),
            auth: auth,
            as: CreateRecordResponse.self
        )
        await indexRecords([response.uri ?? Self.uri(repo, collection, rkey)], auth: auth)
        return response
    }

    /// Apply every write in a single atomic PDS commit. Either all the records
    /// land or none do: there is no partially-created gallery to clean up.
    func applyWrites(_ writes: [ApplyWrite], auth: AuthContext? = nil) async throws -> ApplyWritesResponse {
        let repo = auth?.did ?? ""
        let response = try await procedure(
            "com.atproto.repo.applyWrites",
            input: ApplyWritesInput(repo: repo, writes: writes),
            auth: auth,
            as: ApplyWritesResponse.self
        )
        await indexRecords(writes.map { Self.uri(repo, $0.collection, $0.rkey) }, auth: auth)
        return response
    }

    func deleteRecord(collection: String, rkey: String, auth: AuthContext? = nil) async throws {
        let repo = auth?.did ?? ""
        try await procedure(
            "com.atproto.repo.deleteRecord",
            input: DeleteRecordInput(repo: repo, collection: collection, rkey: rkey),
            auth: auth
        )
        await indexRecords([Self.uri(repo, collection, rkey)], auth: auth)
    }

    /// Ask the AppView to index `uris` now, deleted ones included, in batches
    /// it accepts. Only Grain's own collections are its to index; a Bluesky
    /// cross-post is not. A failure is logged and never fails the write it
    /// follows: the firehose brings the record in the end.
    func indexRecords(_ uris: [String], auth: AuthContext?) async {
        let uris = uris.filter { $0.contains("/social.grain.") }
        guard let auth, !uris.isEmpty else { return }
        for start in stride(from: 0, to: uris.count, by: Self.indexBatchSize) {
            let batch = Array(uris[start ..< min(start + Self.indexBatchSize, uris.count)])
            do {
                try await procedure("social.grain.sync.indexRecords", input: IndexRecordsInput(uris: batch), auth: auth)
            } catch {
                logger.error("indexRecords failed for \(batch.count) record(s): \(error)")
            }
        }
    }

    static func uri(_ repo: String, _ collection: String, _ rkey: String) -> String {
        "at://\(repo)/\(collection)/\(rkey)"
    }

    func deleteGallery(rkey: String, auth: AuthContext? = nil) async throws {
        try await procedure("social.grain.unspecced.deleteGallery", input: DeleteGalleryInput(rkey: rkey), auth: auth)
    }

    func deleteAccount(auth: AuthContext? = nil) async throws {
        try await procedure("social.grain.unspecced.deleteAccount", input: EmptyInput(), auth: auth)
    }
}

private struct EmptyInput: Codable, Sendable {}

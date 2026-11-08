import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "Records")

struct CreateRecordInput: Codable, Sendable {
    let collection: String
    let repo: String
    var rkey: String?
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
    /// The CID the record must still have for the put to land.
    var swapRecord: String?
}

struct DeleteRecordInput: Codable, Sendable {
    let repo: String
    let collection: String
    let rkey: String
}

struct IndexRecordsInput: Codable, Sendable {
    let uris: [String]
}

/// `com.atproto.repo.getRecord`'s answer.
struct GetRecordResponse: Codable, Sendable {
    var uri: String?
    var cid: String?
    var value: AnyCodable?
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

/// A page of `com.atproto.repo.listRecords`.
struct ListRecordsResponse: Codable, Sendable {
    struct Record: Codable, Sendable {
        let uri: String
        var cid: String?
        var value: AnyCodable?
    }

    var records: [Record]
    var cursor: String?
}

struct DescribeRepoResponse: Codable, Sendable {
    var collections: [String]?
}

struct DeleteAccountInput: Codable, Sendable {
    let did: String
}

struct DeleteAccountResponse: Codable, Sendable {
    var deleted: Int?
    var done: Bool?
}

/// Writes go to the account's PDS as `com.atproto.repo.*` calls, with the
/// account's DID as the repo. Each one that lands is then handed to the
/// AppView's `social.grain.sync.indexRecords`, so the next read sees it
/// without waiting on the firehose.
extension XRPCClient {
    /// How many URIs one `indexRecords` call takes.
    static let indexBatchSize = 25

    /// How many writes one `applyWrites` commit takes.
    static let writeBatchSize = 200

    /// Read the record at `uri` from its repo, at the account's PDS.
    func getRecord(uri: String, auth: AuthContext? = nil) async throws -> GetRecordResponse {
        let parts = uri.replacingOccurrences(of: "at://", with: "").split(separator: "/", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { throw XRPCError.invalidURL }
        return try await query(
            "com.atproto.repo.getRecord",
            params: ["repo": parts[0], "collection": parts[1], "rkey": parts[2]],
            auth: auth,
            as: GetRecordResponse.self
        )
    }

    /// Create a record, at `rkey` if one is given.
    func createRecord(collection: String, repo: String, rkey: String? = nil, record: AnyCodable, auth: AuthContext? = nil) async throws -> CreateRecordResponse {
        let response = try await procedure(
            "com.atproto.repo.createRecord",
            input: CreateRecordInput(collection: collection, repo: repo, rkey: rkey, record: record),
            auth: auth,
            as: CreateRecordResponse.self
        )
        await indexRecords([response.uri].compactMap(\.self), auth: auth)
        return response
    }

    /// Create or overwrite the record at `rkey`. `repo` defaults to the
    /// signed-in account's. With `swapRecord`, only if the record there
    /// still has that CID.
    func putRecord(collection: String, rkey: String, record: AnyCodable, repo: String? = nil, swapRecord: String? = nil, auth: AuthContext? = nil) async throws -> CreateRecordResponse {
        let repo = repo ?? auth?.did ?? ""
        let response = try await procedure(
            "com.atproto.repo.putRecord",
            input: PutRecordInput(collection: collection, rkey: rkey, record: record, repo: repo, swapRecord: swapRecord),
            auth: auth,
            as: CreateRecordResponse.self
        )
        await indexRecords([response.uri ?? Self.uri(repo, collection, rkey)], auth: auth)
        return response
    }

    /// Apply every write in a single atomic PDS commit. Either all the records
    /// land or none do: there is no partially-created gallery to clean up.
    /// The records are then indexed, unless `indexing` is false.
    func applyWrites(_ writes: [ApplyWrite], auth: AuthContext? = nil, indexing: Bool = true) async throws -> ApplyWritesResponse {
        let repo = auth?.did ?? ""
        let response = try await procedure(
            "com.atproto.repo.applyWrites",
            input: ApplyWritesInput(repo: repo, writes: writes),
            auth: auth,
            as: ApplyWritesResponse.self
        )
        if indexing {
            await indexRecords(writes.map { Self.uri(repo, $0.collection, $0.rkey) }, auth: auth)
        }
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

    /// Every record of the account's in `collection`, from its PDS.
    func listAllRecords(collection: String, auth: AuthContext) async throws -> [ListRecordsResponse.Record] {
        var records: [ListRecordsResponse.Record] = []
        var cursor: String?
        repeat {
            var params = ["repo": auth.did, "collection": collection, "limit": "100"]
            if let cursor {
                params["cursor"] = cursor
            }
            let page = try await query("com.atproto.repo.listRecords", params: params, auth: auth, as: ListRecordsResponse.self)
            records += page.records
            cursor = page.records.isEmpty ? nil : page.cursor
        } while cursor != nil
        return records
    }

    /// Delete `uris` from the account's repo, `writeBatchSize` to a commit,
    /// in the order given, each commit indexed unless `indexing` is false.
    func deleteRecords(_ uris: [String], auth: AuthContext, indexing: Bool = true) async throws {
        let writes: [ApplyWrite] = uris.compactMap { uri in
            let parts = uri.split(separator: "/").map(String.init)
            guard parts.count >= 3 else { return nil }
            return .delete(collection: parts[parts.count - 2], rkey: parts[parts.count - 1])
        }
        for start in stride(from: 0, to: writes.count, by: Self.writeBatchSize) {
            let batch = Array(writes[start ..< min(start + Self.writeBatchSize, writes.count)])
            _ = try await applyWrites(batch, auth: auth, indexing: indexing)
        }
    }

    /// Delete the account's gallery `rkey` and what goes with it, at its
    /// PDS, as grain-serve deletes one for the web: the exif of the photos
    /// it alone places, its items, those photos, the account's own
    /// favorites and comments on it, then the gallery. Each commit is then
    /// indexed.
    func deleteGallery(rkey: String, auth: AuthContext) async throws {
        let gallery = Self.uri(auth.did, "social.grain.gallery", rkey)
        let photoPrefix = "at://\(auth.did)/social.grain.photo/"
        func field(_ record: ListRecordsResponse.Record, _ name: String) -> String? {
            record.value?.dictValue?[name]?.stringValue
        }

        let items = try await listAllRecords(collection: "social.grain.gallery.item", auth: auth)
        let its = items.filter { field($0, "gallery") == gallery }
        let elsewhere = Set(items.filter { field($0, "gallery") != gallery }.compactMap { field($0, "item") })
        let photos = Set(its.compactMap { field($0, "item") }.filter { $0.hasPrefix(photoPrefix) && !elsewhere.contains($0) })

        let exif = try await listAllRecords(collection: "social.grain.photo.exif", auth: auth)
            .filter { field($0, "photo").map(photos.contains) ?? false }
        let favorites = try await listAllRecords(collection: "social.grain.favorite", auth: auth)
            .filter { field($0, "subject") == gallery }
        let comments = try await listAllRecords(collection: "social.grain.comment", auth: auth)
            .filter { field($0, "subject") == gallery }

        let going = exif.map(\.uri).sorted()
            + its.map(\.uri).sorted()
            + photos.sorted()
            + favorites.map(\.uri).sorted()
            + comments.map(\.uri).sorted()
            + [gallery]
        try await deleteRecords(going, auth: auth)
    }

    /// Delete the account's grain data: every record in each of its
    /// `social.grain.*` collections, at its PDS, then ask grain-serve to
    /// forget it, which it does once the PDS lists none of them. The
    /// atproto account, and other apps' records in it, are untouched.
    func deleteAccount(auth: AuthContext) async throws {
        let repo = try await query("com.atproto.repo.describeRepo", params: ["repo": auth.did], auth: auth, as: DescribeRepoResponse.self)
        for collection in repo.collections ?? [] where collection.hasPrefix("social.grain.") {
            let uris = try await listAllRecords(collection: collection, auth: auth).map(\.uri)
            try await deleteRecords(uris, auth: auth, indexing: false)
        }
        try await procedure(
            "social.grain.server.deleteAccount",
            input: DeleteAccountInput(did: auth.did),
            auth: auth,
            as: DeleteAccountResponse.self
        )
    }
}

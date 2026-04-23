import Foundation

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
    var repo: String?
}

struct DeleteRecordInput: Codable, Sendable {
    let collection: String
    let rkey: String
}

struct DeleteGalleryInput: Codable, Sendable {
    let rkey: String
}

struct GetRecordResponse: Codable, Sendable {
    var uri: String?
    var cid: String?
    var record: AnyCodable?
}

extension XRPCClient {
    func getRecord(uri: String, auth: AuthContext? = nil) async throws -> GetRecordResponse {
        try await query("dev.hatk.getRecord", params: ["uri": uri], auth: auth, as: GetRecordResponse.self)
    }

    func createRecord(collection: String, repo: String, record: AnyCodable, auth: AuthContext? = nil) async throws -> CreateRecordResponse {
        try await procedure("dev.hatk.createRecord", input: CreateRecordInput(collection: collection, repo: repo, record: record), auth: auth, as: CreateRecordResponse.self)
    }

    func putRecord(collection: String, rkey: String, record: AnyCodable, repo: String? = nil, auth: AuthContext? = nil) async throws -> CreateRecordResponse {
        try await procedure("dev.hatk.putRecord", input: PutRecordInput(collection: collection, rkey: rkey, record: record, repo: repo), auth: auth, as: CreateRecordResponse.self)
    }

    func deleteRecord(collection: String, rkey: String, auth: AuthContext? = nil) async throws {
        try await procedure("dev.hatk.deleteRecord", input: DeleteRecordInput(collection: collection, rkey: rkey), auth: auth)
    }

    func deleteGallery(rkey: String, auth: AuthContext? = nil) async throws {
        try await procedure("social.grain.unspecced.deleteGallery", input: DeleteGalleryInput(rkey: rkey), auth: auth)
    }

    func deleteAccount(auth: AuthContext? = nil) async throws {
        try await procedure("social.grain.unspecced.deleteAccount", input: EmptyInput(), auth: auth)
    }
}

private struct EmptyInput: Codable, Sendable {}

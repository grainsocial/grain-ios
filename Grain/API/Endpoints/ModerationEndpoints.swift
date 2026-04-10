import Foundation

struct LabelDefinition: Codable, Sendable, Identifiable {
    let identifier: String
    var locales: [LabelLocale]?
    var blurs: String?
    var defaultSetting: String?

    var id: String {
        identifier
    }

    var displayName: String {
        locales?.first?.name ?? identifier
    }
}

struct LabelLocale: Codable, Sendable {
    let name: String
}

struct DescribeLabelsResponse: Codable, Sendable {
    let definitions: [LabelDefinition]?
}

struct CreateReportInput: Codable, Sendable {
    let subject: StrongRef
    let label: String
    var reason: String?
}

struct StrongRef: Codable, Sendable {
    let type: String
    let uri: String
    let cid: String

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case uri
        case cid
    }
}

struct CreateReportResponse: Codable, Sendable {
    let id: Int
}

// MARK: - Block / Mute types

struct MuteActorInput: Codable, Sendable {
    let actor: String
}

struct BlockItem: Codable, Sendable, Identifiable {
    let did: String
    var handle: String?
    var displayName: String?
    var avatar: String?
    let blockUri: String

    var id: String {
        did
    }
}

struct MuteItem: Codable, Sendable, Identifiable {
    let did: String
    var handle: String?
    var displayName: String?
    var avatar: String?

    var id: String {
        did
    }
}

struct BlockListResponse: Codable, Sendable {
    let items: [BlockItem]?
    var cursor: String?
}

struct MuteListResponse: Codable, Sendable {
    let items: [MuteItem]?
    var cursor: String?
}

extension XRPCClient {
    func describeLabels(auth: AuthContext? = nil) async throws -> [LabelDefinition] {
        let response = try await query("dev.hatk.describeLabels", auth: auth, as: DescribeLabelsResponse.self)
        return response.definitions ?? []
    }

    func createReport(subjectUri: String, subjectCid: String, label: String, reason: String? = nil, auth: AuthContext? = nil) async throws {
        let input = CreateReportInput(
            subject: StrongRef(type: "com.atproto.repo.strongRef", uri: subjectUri, cid: subjectCid),
            label: label,
            reason: reason
        )
        try await procedure("dev.hatk.createReport", input: input, auth: auth)
    }

    // MARK: - Blocks

    @discardableResult
    func blockActor(did: String, auth: AuthContext) async throws -> CreateRecordResponse {
        let repo = TokenStorage.userDID ?? ""
        let record = AnyCodable([
            "subject": did,
            "createdAt": DateFormatting.nowISO(),
        ])
        return try await createRecord(collection: "social.grain.graph.block", repo: repo, record: record, auth: auth)
    }

    func unblockActor(blockUri: String, auth: AuthContext) async throws {
        let rkey = blockUri.split(separator: "/").last.map(String.init) ?? ""
        try await deleteRecord(collection: "social.grain.graph.block", rkey: rkey, auth: auth)
    }

    func getBlocks(auth: AuthContext) async throws -> BlockListResponse {
        try await query("social.grain.unspecced.getBlocks", auth: auth, as: BlockListResponse.self)
    }

    // MARK: - Mutes

    func muteActor(did: String, auth: AuthContext) async throws {
        try await procedure("social.grain.graph.muteActor", input: MuteActorInput(actor: did), auth: auth)
    }

    func unmuteActor(did: String, auth: AuthContext) async throws {
        try await procedure("social.grain.graph.unmuteActor", input: MuteActorInput(actor: did), auth: auth)
    }

    func getMutes(auth: AuthContext) async throws -> MuteListResponse {
        try await query("social.grain.unspecced.getMutes", auth: auth, as: MuteListResponse.self)
    }
}

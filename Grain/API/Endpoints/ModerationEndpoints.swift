import Foundation

/// A label grain's labeler gives out, as
/// `com.atproto.label.defs#labelValueDefinition` has one.
struct LabelDefinition: Codable, Sendable, Identifiable, Equatable {
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

struct LabelLocale: Codable, Sendable, Equatable {
    let name: String
    var description: String?
}

extension LabelDefinition {
    private static func grain(_ identifier: String, _ blurs: String, _ defaultSetting: String, _ name: String, _ description: String) -> LabelDefinition {
        LabelDefinition(identifier: identifier, locales: [LabelLocale(name: name, description: description)], blurs: blurs, defaultSetting: defaultSetting)
    }

    /// The labels grain gives out, as grain-serve defines them
    /// (`grain::labels::DEFINITIONS`), in its order: the reasons a report
    /// names and the warnings a gallery carries. grain-serve publishes them
    /// only to its admins, so the app carries them, as the web does.
    static let all: [LabelDefinition] = [
        grain("copyright", "content", "hide", "Copyright Violation", "Content that infringes on copyright or intellectual property."),
        grain("csae", "content", "hide", "Child Safety", "Sexual content involving a minor, or the exploitation, grooming or endangerment of a child."),
        grain("gore", "media", "hide", "Graphic Media", "Graphic or violent imagery."),
        grain("harassment", "none", "warn", "Harassment", "Targeted harassment, bullying, or hate speech."),
        grain("misleading", "none", "warn", "Misleading", "Impersonation, misinformation, or deceptive content."),
        grain("nudity", "media", "warn", "Nudity", "Content containing nudity."),
        grain("other", "none", "ignore", "Other", "Content that does not fit other report categories."),
        grain("sexual", "media", "warn", "Sexual Content", "Unwanted or mislabeled sexual content."),
        grain("spam", "content", "hide", "Spam", "Unwanted or repetitive promotional content."),
    ]

    /// The `reasonType` a report for each label names: the one grain-serve
    /// files under that label (`grain::labels::label_for`). atproto's where
    /// it has one, Ozone's for graphic media and child safety, grain's own
    /// for the rest.
    static let reportReasons: [String: String] = [
        "copyright": "social.grain.moderation.defs#reasonCopyright",
        "csae": "tools.ozone.report.defs#reasonChildSafetyOther",
        "gore": "tools.ozone.report.defs#reasonViolenceGraphicContent",
        "harassment": "com.atproto.moderation.defs#reasonRude",
        "misleading": "com.atproto.moderation.defs#reasonMisleading",
        "nudity": "social.grain.moderation.defs#reasonNudity",
        "other": "com.atproto.moderation.defs#reasonOther",
        "sexual": "com.atproto.moderation.defs#reasonSexual",
        "spam": "com.atproto.moderation.defs#reasonSpam",
    ]

    /// The `reasonType` a report filed under `label` names.
    static func reasonType(for label: String) -> String {
        reportReasons[label] ?? reportReasons["other"]!
    }
}

/// `com.atproto.moderation.createReport`'s input.
struct CreateReportInput: Codable, Sendable {
    let reasonType: String
    var reason: String?
    let subject: StrongRef
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
    /// Report a record to grain, filed under `label`. The call goes through
    /// the PDS to grain's AppView, which files grain's reports, rather than
    /// to the PDS's own moderation service.
    func createReport(subjectUri: String, subjectCid: String, label: String, reason: String? = nil, auth: AuthContext? = nil) async throws {
        let input = CreateReportInput(
            reasonType: LabelDefinition.reasonType(for: label),
            reason: reason,
            subject: StrongRef(type: "com.atproto.repo.strongRef", uri: subjectUri, cid: subjectCid)
        )
        try await procedure(Self.createReportMethod, input: input, auth: auth)
    }

    static let createReportMethod = "com.atproto.moderation.createReport"

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
        try await query("social.grain.graph.getBlocks", auth: auth, as: BlockListResponse.self)
    }

    // MARK: - Mutes

    func muteActor(did: String, auth: AuthContext) async throws {
        try await procedure("social.grain.graph.muteActor", input: MuteActorInput(actor: did), auth: auth)
    }

    func unmuteActor(did: String, auth: AuthContext) async throws {
        try await procedure("social.grain.graph.unmuteActor", input: MuteActorInput(actor: did), auth: auth)
    }

    func getMutes(auth: AuthContext) async throws -> MuteListResponse {
        try await query("social.grain.graph.getMutes", auth: auth, as: MuteListResponse.self)
    }
}

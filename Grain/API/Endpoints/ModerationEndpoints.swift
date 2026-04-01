import Foundation

struct LabelDefinition: Codable, Sendable, Identifiable {
    let identifier: String
    var locales: [LabelLocale]?
    var blurs: String?
    var defaultSetting: String?

    var id: String { identifier }

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
}

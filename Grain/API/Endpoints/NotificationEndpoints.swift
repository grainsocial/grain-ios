import Foundation

struct GetNotificationsResponse: Codable, Sendable {
    let notifications: [GrainNotification]
    var cursor: String?
    var unseenCount: Int?
}

extension XRPCClient {
    func markNotificationsSeen(auth: AuthContext? = nil) async throws {
        struct PutPreferenceInput: Encodable {
            let key: String
            let value: String
        }
        let input = PutPreferenceInput(key: "lastSeenNotifications", value: DateFormatting.nowISO())
        try await procedure("dev.hatk.putPreference", input: input, auth: auth)
    }

    func getNotifications(
        limit: Int = 100,
        cursor: String? = nil,
        countOnly: Bool = false,
        auth: AuthContext? = nil
    ) async throws -> GetNotificationsResponse {
        var params = ["limit": String(limit)]
        if let cursor { params["cursor"] = cursor }
        if countOnly { params["countOnly"] = "true" }
        return try await query("social.grain.unspecced.getNotifications", params: params, auth: auth, as: GetNotificationsResponse.self)
    }
}

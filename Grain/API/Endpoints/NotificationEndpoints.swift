import Foundation

struct GetNotificationsResponse: Codable, Sendable {
    let notifications: [GrainNotification]
    var cursor: String?
    var unseenCount: Int?
}

extension XRPCClient {
    func getNotifications(
        limit: Int = 20,
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

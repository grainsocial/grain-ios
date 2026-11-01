import Foundation

struct GetNotificationsResponse: Codable, Sendable {
    let notifications: [GrainNotification]
    var cursor: String?
    /// When the viewer last marked their notifications seen, if they have.
    var seenAt: String?
}

struct GetUnreadCountResponse: Codable, Sendable {
    let count: Int
}

extension XRPCClient {
    /// Mark every notification up to now seen.
    func markNotificationsSeen(auth: AuthContext? = nil) async throws {
        struct UpdateSeenInput: Encodable {
            let seenAt: String
        }
        let input = UpdateSeenInput(seenAt: DateFormatting.nowISO())
        try await procedure("social.grain.notification.updateSeen", input: input, auth: auth)
    }

    func getNotifications(
        limit: Int = 100,
        cursor: String? = nil,
        auth: AuthContext? = nil
    ) async throws -> GetNotificationsResponse {
        var params = ["limit": String(limit)]
        if let cursor {
            params["cursor"] = cursor
        }
        return try await query("social.grain.notification.listNotifications", params: params, auth: auth, as: GetNotificationsResponse.self)
    }

    /// How many notifications have come in since they were last seen.
    func getUnreadCount(auth: AuthContext? = nil) async throws -> Int {
        try await query("social.grain.notification.getUnreadCount", auth: auth, as: GetUnreadCountResponse.self).count
    }
}

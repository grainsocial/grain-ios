import Foundation

@Observable
@MainActor
final class NotificationsViewModel {
    var notifications: [GrainNotification] = []
    var unseenCount: Int = 0
    var isLoading = false
    var error: Error?

    private var cursor: String?
    private var hasMore = true
    private var client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
    }

    func updateClient(_ client: XRPCClient) {
        self.client = client
    }

    func loadInitial(auth: AuthContext? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        cursor = nil
        hasMore = true

        do {
            let response = try await client.getNotifications(auth: auth)
            notifications = response.notifications
            unseenCount = response.unseenCount ?? 0
            cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func loadMore(auth: AuthContext? = nil) async {
        guard !isLoading, hasMore, let cursor else { return }
        isLoading = true

        do {
            let response = try await client.getNotifications(cursor: cursor, auth: auth)
            notifications.append(contentsOf: response.notifications)
            self.cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func markAsSeen(auth: AuthContext? = nil) async {
        guard unseenCount > 0 else { return }
        let previousCount = unseenCount
        unseenCount = 0
        do {
            try await client.markNotificationsSeen(auth: auth)
        } catch {
            unseenCount = previousCount
        }
    }

    func fetchUnseenCount(auth: AuthContext? = nil) async {
        do {
            let response = try await client.getNotifications(countOnly: true, auth: auth)
            unseenCount = response.unseenCount ?? 0
        } catch {}
    }
}

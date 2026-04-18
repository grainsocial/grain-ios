import Foundation
import Nuke
import os
import SwiftUI
import UserNotifications

private let notifSignposter = OSSignposter(subsystem: "social.grain.grain", category: "AppLaunch")

@Observable
@MainActor
final class NotificationsViewModel {
    var notifications: [GrainNotification] = []
    var grouped: [GroupedNotification] = []
    var unseenCount: Int = 0 {
        didSet { UNUserNotificationCenter.current().setBadgeCount(unseenCount) }
    }

    var isLoading = false
    var error: Error?

    private var cursor: String?
    private var hasMore = true
    private var client: XRPCClient
    private var prefetcher = ImagePrefetcher()

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
            withAnimation(nil) {
                notifications = response.notifications
                grouped = GroupedNotification.group(notifications)
                unseenCount = response.unseenCount ?? 0
                cursor = response.cursor
                hasMore = response.cursor != nil
            }
            prefetchImages(response.notifications)
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
            var updatedGroups = grouped
            GroupedNotification.mergeNewPage(response.notifications, into: &updatedGroups)
            withAnimation(nil) {
                notifications.append(contentsOf: response.notifications)
                grouped = updatedGroups
            }
            self.cursor = response.cursor
            hasMore = response.cursor != nil
            prefetchImages(response.notifications)
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

    private static let thumbSize: CGFloat = 44
    private static let thumbSquareSize: CGSize = {
        let px = thumbSize * UIScreen.main.scale
        return CGSize(width: px, height: px)
    }()

    private static let thumbPortraitSize: CGSize = {
        let scale = UIScreen.main.scale
        return CGSize(width: thumbSize * scale, height: thumbSize * 4 / 3 * scale)
    }()

    private func prefetchImages(_ notifs: [GrainNotification]) {
        let avatarURLs = notifs.compactMap(\.author.avatar).compactMap { URL(string: $0) }
        var requests = avatarURLs.map { ImageRequest(url: $0) }

        for notif in notifs {
            if let thumb = notif.galleryThumb, let url = URL(string: thumb) {
                requests.append(ImageRequest(url: url, processors: [.resize(size: Self.thumbSquareSize, contentMode: .aspectFill)]))
            }
            if let thumb = notif.storyThumb, let url = URL(string: thumb) {
                requests.append(ImageRequest(url: url, processors: [.resize(size: Self.thumbPortraitSize, contentMode: .aspectFill)]))
            }
        }

        prefetcher.startPrefetching(with: requests)
    }

    nonisolated func fetchUnseenCount(auth: AuthContext? = nil) async {
        let spid = notifSignposter.makeSignpostID()
        let state = notifSignposter.beginInterval("Notif.fetchUnseenCount", id: spid)
        defer { notifSignposter.endInterval("Notif.fetchUnseenCount", state) }

        let client = await MainActor.run { self.client }
        do {
            let netSpid = notifSignposter.makeSignpostID()
            let netState = notifSignposter.beginInterval("Notif.network", id: netSpid)
            let response = try await client.getNotifications(countOnly: true, auth: auth)
            notifSignposter.endInterval("Notif.network", netState)

            await MainActor.run { self.unseenCount = response.unseenCount ?? 0 }
        } catch {}
    }
}

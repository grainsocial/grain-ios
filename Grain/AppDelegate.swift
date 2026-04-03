import UIKit
import UserNotifications

/// AppDelegate for handling push notification registration and tap callbacks.
@MainActor
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var pushManager: PushManager?
    var onNotificationTap: ((DeepLink) -> Void)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        pushManager?.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushManager?.didFailToRegisterForRemoteNotifications(error: error)
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Handle notification tap — route to appropriate view
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let type = userInfo["type"] as? String else { return }

        let deepLink: DeepLink?
        switch type {
        case "gallery-favorite", "gallery-comment", "comment-reply":
            if let uri = userInfo["uri"] as? String {
                deepLink = parseGalleryUri(uri)
            } else {
                deepLink = nil
            }
        case "follow":
            if let did = userInfo["did"] as? String {
                deepLink = .profile(did: did)
            } else {
                deepLink = nil
            }
        default:
            deepLink = nil
        }

        if let deepLink {
            await MainActor.run {
                onNotificationTap?(deepLink)
            }
        }
    }

    private func parseGalleryUri(_ uri: String) -> DeepLink? {
        // at://did:plc:xxx/social.grain.gallery/rkey
        let parts = uri.replacingOccurrences(of: "at://", with: "").split(separator: "/")
        guard parts.count >= 3 else { return nil }
        let did = String(parts[0])
        let rkey = String(parts[2])
        return .gallery(did: did, rkey: rkey)
    }
}

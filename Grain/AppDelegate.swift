import os
import UIKit
import UserNotifications

private let appDelegateSignposter = OSSignposter(subsystem: "social.grain.grain", category: "AppLaunch")

/// AppDelegate for handling push notification registration and tap callbacks.
@MainActor
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var pushManager: PushManager?
    var onNotificationTap: ((DeepLink) -> Void)?

    override init() {
        super.init()
        appDelegateSignposter.emitEvent("AppDelegateInit")
    }

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        appDelegateSignposter.emitEvent("AppDelegateDidFinishLaunching")
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = GrainSceneDelegate.self
        return config
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        pushManager?.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushManager?.didFailToRegisterForRemoteNotifications(error: error)
    }

    /// Show notifications even when app is in foreground
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Handle notification tap — route to appropriate view
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let type = userInfo["type"] as? String else { return }

        let deepLink: DeepLink? = switch type {
        case "gallery-favorite", "gallery-comment", "comment-reply":
            if let uri = userInfo["uri"] as? String {
                parseGalleryUri(uri)
            } else {
                nil
            }
        case "gallery-mention", "gallery-comment-mention":
            if let uri = userInfo["uri"] as? String {
                parseGalleryUri(uri, commentUri: userInfo["commentUri"] as? String)
            } else {
                nil
            }
        case "follow":
            if let did = userInfo["did"] as? String {
                .profile(did: did)
            } else {
                nil
            }
        default:
            nil
        }

        if let deepLink {
            await MainActor.run {
                onNotificationTap?(deepLink)
            }
        }
    }

    private nonisolated func parseGalleryUri(_ uri: String, commentUri: String? = nil) -> DeepLink? {
        // at://did:plc:xxx/social.grain.gallery/rkey
        let parts = uri.replacingOccurrences(of: "at://", with: "").split(separator: "/")
        guard parts.count >= 3 else { return nil }
        let did = String(parts[0])
        let rkey = String(parts[2])
        return .gallery(did: did, rkey: rkey, commentUri: commentUri)
    }
}

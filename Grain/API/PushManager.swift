import Foundation
import UIKit
import UserNotifications
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "Push")

/// Manages push notification registration and token delivery to the hatk server.
@Observable
@MainActor
final class PushManager: NSObject {
    private weak var authManager: AuthManager?

    func configure(authManager: AuthManager) {
        self.authManager = authManager
    }

    /// Request notification permission and register for remote notifications.
    func registerIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()

            switch settings.authorizationStatus {
            case .notDetermined:
                do {
                    let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                    if granted {
                        logger.info("Push permission granted")
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                } catch {
                    logger.error("Push permission request failed: \(error)")
                }
            case .authorized, .provisional:
                UIApplication.shared.registerForRemoteNotifications()
            default:
                logger.info("Push notifications not authorized (status: \(String(describing: settings.authorizationStatus)))")
            }
        }
    }

    /// Called when APNs returns a device token.
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        logger.info("APNs token: \(token.prefix(16))...")

        Task {
            await sendTokenToServer(token: token)
        }
    }

    /// Called when APNs registration fails.
    func didFailToRegisterForRemoteNotifications(error: Error) {
        logger.error("APNs registration failed: \(error)")
    }

    /// Unregister the current token on logout.
    /// Must be called while auth context is still valid (before token storage is cleared).
    func unregisterToken() {
        guard let token = currentToken,
              let authManager else { return }
        let client = authManager.makeClient()
        currentToken = nil
        Task {
            guard let auth = await authManager.authContext() else { return }
            do {
                try await client.procedure(
                    "dev.hatk.push.unregisterToken",
                    input: UnregisterTokenInput(token: token),
                    auth: auth
                )
                logger.info("Push token unregistered from server")
            } catch {
                logger.error("Failed to unregister push token: \(error)")
            }
        }
    }

    // MARK: - Private

    private var currentToken: String? {
        get { UserDefaults.standard.string(forKey: "apns_device_token") }
        set { UserDefaults.standard.set(newValue, forKey: "apns_device_token") }
    }

    private func sendTokenToServer(token: String) async {
        currentToken = token

        guard let authManager, let auth = await authManager.authContext() else {
            logger.warning("No auth context, skipping token registration")
            return
        }

        let client = authManager.makeClient()
        do {
            try await client.procedure(
                "dev.hatk.push.registerToken",
                input: RegisterTokenInput(token: token, platform: "apns"),
                auth: auth
            )
            logger.info("Push token registered with server")
        } catch {
            logger.error("Failed to register push token: \(error)")
        }
    }

}

private struct RegisterTokenInput: Encodable {
    let token: String
    let platform: String
}

private struct UnregisterTokenInput: Encodable {
    let token: String
}

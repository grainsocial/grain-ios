import Foundation
import os
import UIKit
import UserNotifications

private let logger = Logger(subsystem: "social.grain.grain", category: "Push")

/// Manages push notification registration and token delivery to the server.
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

    /// Unregister the current token when an account stops being active — on
    /// sign-out, or on a switch to another account.
    ///
    /// Takes the outgoing account's auth context explicitly and uses a client
    /// with no refresh hook: by the time this resolves, the app may already be
    /// acting as somebody else, and unregistering *their* device token is
    /// exactly the bug this avoids.
    func unregisterToken(auth: AuthContext?) async {
        guard let token = currentToken, let auth else { return }
        currentToken = nil
        let client = XRPCClient(baseURL: AuthManager.serverURL)
        do {
            do {
                try await client.procedure(
                    "social.grain.notification.unregisterPush",
                    input: PushRegistrationInput(token: token),
                    auth: auth
                )
            } catch let error where Self.isMethodMissing(error) {
                try await client.procedure(
                    "dev.hatk.push.unregisterToken",
                    input: UnregisterTokenInput(token: token),
                    auth: auth
                )
            }
            logger.info("Push token unregistered from server")
        } catch {
            logger.error("Failed to unregister push token: \(error)")
        }
    }

    // MARK: - Private

    private var currentToken: String? {
        get { StorageEnvironment.defaults.string(forKey: "apns_device_token") }
        set { StorageEnvironment.defaults.set(newValue, forKey: "apns_device_token") }
    }

    private func sendTokenToServer(token: String) async {
        currentToken = token

        guard let authManager, let auth = await authManager.authContext() else {
            logger.warning("No auth context, skipping token registration")
            return
        }

        let client = authManager.makeClient()
        do {
            do {
                try await client.procedure(
                    "social.grain.notification.registerPush",
                    input: PushRegistrationInput(token: token),
                    auth: auth
                )
            } catch let error where Self.isMethodMissing(error) {
                try await client.procedure(
                    "dev.hatk.push.registerToken",
                    input: RegisterTokenInput(token: token, platform: "apns"),
                    auth: auth
                )
            }
            logger.info("Push token registered with server")
        } catch {
            logger.error("Failed to register push token: \(error)")
        }
    }

    /// Whether the server answered that it does not serve the method at all,
    /// as a server without `social.grain.notification.registerPush` does. Only
    /// then is the older `registerToken` call tried; any other failure, such as
    /// a 401 or a rejected input, is the answer.
    nonisolated static func isMethodMissing(_ error: Error) -> Bool {
        guard case let XRPCError.httpError(statusCode, body) = error else { return false }
        if statusCode == 404 || statusCode == 501 {
            return true
        }
        guard let body,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let name = object["error"] as? String
        else { return false }
        return name == "MethodNotImplemented" || name == "MethodNotFound"
    }
}

/// The input of `social.grain.notification.registerPush` and `unregisterPush`,
/// shaped as Bluesky's `app.bsky.notification.registerPush`.
struct PushRegistrationInput: Encodable, Equatable {
    /// The service that sends the pushes.
    static let grainServiceDid = "did:web:grain.social"
    /// The bundle id APNs pushes are addressed to.
    static let grainAppId = "social.grain.grain"

    let serviceDid: String
    let token: String
    let platform: String
    let appId: String

    init(token: String) {
        serviceDid = Self.grainServiceDid
        self.token = token
        platform = "ios"
        appId = Self.grainAppId
    }
}

private struct RegisterTokenInput: Encodable {
    let token: String
    let platform: String
}

private struct UnregisterTokenInput: Encodable {
    let token: String
}

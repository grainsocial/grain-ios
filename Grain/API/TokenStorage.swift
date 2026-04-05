import Foundation
@preconcurrency import KeychainAccess

/// Secure storage for OAuth tokens using Keychain.
enum TokenStorage {
    private static let keychain = Keychain(service: "social.grain.oauth")

    static var accessToken: String? {
        get { try? keychain.get("access_token") }
        set {
            if let newValue { try? keychain.set(newValue, key: "access_token") } else { try? keychain.remove("access_token") }
        }
    }

    static var refreshToken: String? {
        get { try? keychain.get("refresh_token") }
        set {
            if let newValue { try? keychain.set(newValue, key: "refresh_token") } else { try? keychain.remove("refresh_token") }
        }
    }

    static var userDID: String? {
        get { try? keychain.get("user_did") }
        set {
            if let newValue { try? keychain.set(newValue, key: "user_did") } else { try? keychain.remove("user_did") }
        }
    }

    static var userHandle: String? {
        get { try? keychain.get("user_handle") }
        set {
            if let newValue { try? keychain.set(newValue, key: "user_handle") } else { try? keychain.remove("user_handle") }
        }
    }

    static var tokenExpiresAt: Date? {
        get {
            guard let str = try? keychain.get("token_expires_at"),
                  let interval = Double(str) else { return nil }
            return Date(timeIntervalSince1970: interval)
        }
        set {
            if let newValue { try? keychain.set(String(newValue.timeIntervalSince1970), key: "token_expires_at") } else { try? keychain.remove("token_expires_at") }
        }
    }

    static var isExpired: Bool {
        guard let expiresAt = tokenExpiresAt else { return true }
        return Date() >= expiresAt
    }

    static var userAvatar: String? {
        get { try? keychain.get("user_avatar") }
        set {
            if let newValue { try? keychain.set(newValue, key: "user_avatar") } else { try? keychain.remove("user_avatar") }
        }
    }

    static func clear() {
        accessToken = nil
        refreshToken = nil
        userDID = nil
        userHandle = nil
        userAvatar = nil
        tokenExpiresAt = nil
    }
}

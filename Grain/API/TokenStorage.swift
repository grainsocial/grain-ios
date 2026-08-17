import Foundation
@preconcurrency import KeychainAccess

/// A signed-in account the app can switch to.
struct StoredAccount: Codable, Identifiable, Hashable {
    let did: String
    var handle: String?
    var avatar: String?

    var id: String {
        did
    }
}

/// Secure storage for OAuth tokens using Keychain.
///
/// Every credential is namespaced by DID so several accounts can stay signed in
/// at once. Reads and writes take the DID explicitly — a token refresh that
/// lands after the user switched accounts must not write over the account they
/// switched to. `activeDID` records which one the UI is currently showing.
enum TokenStorage {
    private static let keychain = Keychain(service: "social.grain.oauth")

    // MARK: - Account list

    private static let accountsKey = "accounts"
    private static let activeDIDKey = "active_did"

    /// Every account with credentials on this device, in the order they were added.
    static var accounts: [StoredAccount] {
        get {
            guard let data = try? keychain.getData(accountsKey),
                  let decoded = try? JSONDecoder().decode([StoredAccount].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            try? keychain.set(data, key: accountsKey)
        }
    }

    /// The DID the app is currently acting as.
    static var activeDID: String? {
        get { try? keychain.get(activeDIDKey) }
        set {
            if let newValue {
                try? keychain.set(newValue, key: activeDIDKey)
            } else {
                try? keychain.remove(activeDIDKey)
            }
        }
    }

    /// Alias for `activeDID`, kept for call sites that just want "who am I".
    static var userDID: String? {
        get { activeDID }
        set { activeDID = newValue }
    }

    /// Add or update an account in the list, preserving its position.
    static func upsertAccount(_ account: StoredAccount) {
        var list = accounts
        if let index = list.firstIndex(where: { $0.did == account.did }) {
            // Don't let a nil handle/avatar from a fresh token response wipe
            // details a previous profile fetch resolved.
            list[index].handle = account.handle ?? list[index].handle
            list[index].avatar = account.avatar ?? list[index].avatar
        } else {
            list.append(account)
        }
        accounts = list
    }

    // MARK: - Per-account credentials

    private static func read(_ name: String, _ did: String) -> String? {
        try? keychain.get("\(name)::\(did)")
    }

    private static func write(_ name: String, _ did: String, _ value: String?) {
        let key = "\(name)::\(did)"
        if let value {
            try? keychain.set(value, key: key)
        } else {
            try? keychain.remove(key)
        }
    }

    static func accessToken(for did: String) -> String? {
        read("access_token", did)
    }

    static func refreshToken(for did: String) -> String? {
        read("refresh_token", did)
    }

    static func handle(for did: String) -> String? {
        read("user_handle", did)
    }

    static func avatar(for did: String) -> String? {
        read("user_avatar", did)
    }

    static func tokenExpiresAt(for did: String) -> Date? {
        guard let raw = read("token_expires_at", did), let interval = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    /// Space-separated OAuth scope string from the token response. Used at
    /// launch to detect tokens minted before newer scopes were added so the
    /// app can force a fresh sign-in. `nil` for sessions created before this
    /// field was introduced — treat as a full scope mismatch.
    static func grantedScope(for did: String) -> String? {
        read("token_scope", did)
    }

    static func setAvatar(_ avatar: String?, for did: String) {
        write("user_avatar", did, avatar)
    }

    /// Persist a token response for one account. `scope` is only overwritten
    /// when the response carries one — refresh responses often omit it.
    static func storeTokens(
        did: String,
        accessToken: String,
        refreshToken: String?,
        handle: String?,
        expiresAt: Date,
        scope: String?
    ) {
        write("access_token", did, accessToken)
        write("refresh_token", did, refreshToken)
        if let handle {
            write("user_handle", did, handle)
        }
        write("token_expires_at", did, String(expiresAt.timeIntervalSince1970))
        if let scope {
            write("token_scope", did, scope)
        }
    }

    /// Whether `did` has enough stored state to resume without a fresh sign-in.
    static func hasCredentials(for did: String) -> Bool {
        accessToken(for: did) != nil && refreshToken(for: did) != nil
    }

    /// Forget one account: wipe its credentials and drop it from the list.
    /// Clears `activeDID` if it was the active one — the caller decides which
    /// account, if any, takes over.
    static func removeAccount(_ did: String) {
        for name in ["access_token", "refresh_token", "user_handle", "user_avatar", "token_expires_at", "token_scope"] {
            write(name, did, nil)
        }
        accounts = accounts.filter { $0.did != did }
        if activeDID == did {
            activeDID = nil
        }
    }

    // MARK: - Migration

    /// Pre-multi-account installs stored a single unsuffixed credential set.
    /// Move it under its DID and seed the account list. Idempotent: it only
    /// fires while a legacy `user_did` entry is still present.
    /// Returns the migrated DID so the caller can move the DPoP key with it.
    @discardableResult
    static func migrateLegacyAccountIfNeeded() -> String? {
        guard let did = try? keychain.get("user_did"), !did.isEmpty else { return nil }

        let legacyHandle = try? keychain.get("user_handle")
        let legacyAvatar = try? keychain.get("user_avatar")
        for name in ["access_token", "refresh_token", "user_handle", "user_avatar", "token_expires_at", "token_scope"] {
            write(name, did, try? keychain.get(name))
        }

        upsertAccount(StoredAccount(did: did, handle: legacyHandle, avatar: legacyAvatar))
        activeDID = did

        for legacy in ["access_token", "refresh_token", "user_handle", "user_avatar", "token_expires_at", "token_scope", "user_did"] {
            try? keychain.remove(legacy)
        }
        return did
    }
}

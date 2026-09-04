import Foundation

/// Namespacing for local state that belongs to one signed-in account.
///
/// Several accounts share a single app sandbox, so anything scoped to "the
/// signed-in user" — viewed stories, recent searches, cached feeds — has the
/// owning DID folded into its key. Without it, switching accounts would show
/// the previous account's cached feed and read state.
enum AccountScopedStorage {
    /// Non-sensitive mirror of `TokenStorage.activeDID`. The Keychain is the
    /// source of truth, but it's too slow to consult from the launch path — the
    /// feed cache is read before the first frame — and the DID is public data.
    static var activeAccountID: String? {
        get { StorageEnvironment.defaults.string(forKey: "activeAccountID") }
        set {
            if let newValue {
                StorageEnvironment.defaults.set(newValue, forKey: "activeAccountID")
            } else {
                StorageEnvironment.defaults.removeObject(forKey: "activeAccountID")
            }
        }
    }

    /// UserDefaults keys holding per-account state, unsuffixed.
    private static let scopedDefaultsKeys = [
        "viewedStoryUris",
        "viewedStoryAuthors",
        "recentSearchProfiles",
        "recentSearchText",
    ]

    /// Suffix `base` with the DID that owns it. A nil DID yields the bare key,
    /// which is also what pre-multi-account builds wrote.
    static func key(_ base: String, did: String?) -> String {
        guard let did else { return base }
        return "\(base)::\(did)"
    }

    /// Claim any unsuffixed state left by a pre-multi-account build for `did`.
    /// Runs once — after the move there's nothing left at the bare key.
    static func migrateLegacyState(to did: String) {
        let defaults = StorageEnvironment.defaults
        for base in scopedDefaultsKeys {
            guard let legacy = defaults.object(forKey: base) else { continue }
            if defaults.object(forKey: key(base, did: did)) == nil {
                defaults.set(legacy, forKey: key(base, did: did))
            }
            defaults.removeObject(forKey: base)
        }
        FeedCache.shared.adoptLegacyEntries(did: did)
    }

    /// Delete everything account-scoped for `did`, leaving other accounts alone.
    static func purge(did: String) {
        for base in scopedDefaultsKeys {
            StorageEnvironment.defaults.removeObject(forKey: key(base, did: did))
        }
        FeedCache.shared.purge(did: did)
    }
}

import Foundation

struct RecentProfileSearch: Codable, Identifiable, Equatable {
    let did: String
    var displayName: String?
    var handle: String?
    var avatar: String?
    var id: String {
        did
    }
}

struct RecentTextSearch: Codable, Identifiable, Equatable {
    let query: String
    var id: String {
        query
    }
}

@Observable
@MainActor
final class RecentSearchStorage {
    var profiles: [RecentProfileSearch] = []
    var textSearches: [RecentTextSearch] = []

    private static let profilesKey = "recentSearchProfiles"
    private static let textKey = "recentSearchText"
    private static let maxProfiles = 10
    private static let maxText = 10

    /// Search history is per-account, so the keys carry the owning DID.
    private let profilesKey: String
    private let textKey: String

    init(did: String? = AccountScopedStorage.activeAccountID) {
        profilesKey = AccountScopedStorage.key(Self.profilesKey, did: did)
        textKey = AccountScopedStorage.key(Self.textKey, did: did)
        load()
    }

    func addProfile(did: String, displayName: String?, handle: String?, avatar: String?) {
        profiles.removeAll { $0.did == did }
        profiles.insert(RecentProfileSearch(did: did, displayName: displayName, handle: handle, avatar: avatar), at: 0)
        if profiles.count > Self.maxProfiles {
            profiles = Array(profiles.prefix(Self.maxProfiles))
        }
        save()
    }

    func addTextSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        textSearches.removeAll { $0.query.lowercased() == trimmed.lowercased() }
        textSearches.insert(RecentTextSearch(query: trimmed), at: 0)
        if textSearches.count > Self.maxText {
            textSearches = Array(textSearches.prefix(Self.maxText))
        }
        save()
    }

    func removeProfile(_ did: String) {
        profiles.removeAll { $0.did == did }
        save()
    }

    func removeTextSearch(_ query: String) {
        textSearches.removeAll { $0.query == query }
        save()
    }

    func clearAll() {
        profiles = []
        textSearches = []
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([RecentProfileSearch].self, from: data)
        {
            profiles = decoded
        }
        if let data = UserDefaults.standard.data(forKey: textKey),
           let decoded = try? JSONDecoder().decode([RecentTextSearch].self, from: data)
        {
            textSearches = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        if let data = try? JSONEncoder().encode(textSearches) {
            UserDefaults.standard.set(data, forKey: textKey)
        }
    }
}

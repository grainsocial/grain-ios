import Foundation

/// Synchronous disk cache for the first-page feed response.
///
/// Allows `FeedViewModel.init()` to pre-populate `galleries` before the first
/// SwiftUI body evaluation, so the feed renders with real content immediately
/// while the background network refresh runs.
///
/// Entries are filed under the account that fetched them — a feed is personal,
/// and switching accounts must not flash the previous one's galleries.
final class FeedCache: @unchecked Sendable {
    static let shared = FeedCache()

    private let directory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("grain_feed_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Load cached galleries for `key`. Returns `[]` if no cache exists or decode fails.
    func load(key: String) -> [GrainGallery] {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let galleries = try? JSONDecoder().decode([GrainGallery].self, from: data)
        else { return [] }
        return galleries
    }

    /// Persist `galleries` to disk for `key`. No-ops on empty arrays.
    func save(_ galleries: [GrainGallery], key: String) {
        guard !galleries.isEmpty,
              let data = try? JSONEncoder().encode(galleries)
        else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    /// Drop every entry belonging to `did` (that account was signed out).
    func purge(did: String) {
        let suffix = "\(Self.accountSeparator)\(Self.sanitize(did)).json"
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.lastPathComponent.hasSuffix(suffix) {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    /// Re-file entries written before the cache was account-scoped under `did`,
    /// the account that must have written them.
    func adoptLegacyEntries(did: String) {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for entry in entries where !entry.lastPathComponent.contains(Self.accountSeparator) {
            let key = entry.deletingPathExtension().lastPathComponent
            try? FileManager.default.moveItem(at: entry, to: fileURL(for: key, did: did))
        }
    }

    private static let accountSeparator = "--acct-"

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func fileURL(for key: String, did: String? = AccountScopedStorage.activeAccountID) -> URL {
        let safe = Self.sanitize(key)
        guard let did else { return directory.appendingPathComponent("\(safe).json") }
        return directory.appendingPathComponent("\(safe)\(Self.accountSeparator)\(Self.sanitize(did)).json")
    }
}

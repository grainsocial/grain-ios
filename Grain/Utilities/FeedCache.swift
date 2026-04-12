import Foundation

/// Synchronous disk cache for the first-page feed response.
///
/// Allows `FeedViewModel.init()` to pre-populate `galleries` before the first
/// SwiftUI body evaluation, so the feed renders with real content immediately
/// while the background network refresh runs.
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

    private func fileURL(for key: String) -> URL {
        let safe = key
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }
}

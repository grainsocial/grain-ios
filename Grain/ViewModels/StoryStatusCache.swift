import Foundation

@Observable
@MainActor
final class StoryStatusCache {
    private struct CachedEntry {
        let author: GrainStoryAuthor
        let expiresAt: Date
    }

    private static let storyLifetime: TimeInterval = 86400 // 24 hours

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let dateFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string) ?? dateFormatterNoFrac.date(from: string)
    }

    private var entries: [String: CachedEntry] = [:]

    /// Live authors whose stories have not yet expired.
    var authorsByDid: [String: GrainStoryAuthor] {
        let now = Date()
        return entries.compactMapValues { $0.expiresAt > now ? $0.author : nil }
    }

    var didsWithStories: Set<String> {
        Set(authorsByDid.keys)
    }

    func hasStory(for did: String) -> Bool {
        guard let entry = entries[did] else { return false }
        return entry.expiresAt > Date()
    }

    func author(for did: String) -> GrainStoryAuthor? {
        guard let entry = entries[did], entry.expiresAt > Date() else { return nil }
        return entry.author
    }

    func update(from authors: [GrainStoryAuthor]) {
        entries = Dictionary(uniqueKeysWithValues: authors.filter { $0.storyCount > 0 }.map { author in
            let expiresAt: Date = if let latestAt = Self.parseDate(author.latestAt) {
                latestAt.addingTimeInterval(Self.storyLifetime)
            } else {
                .distantPast
            }
            return (author.profile.did, CachedEntry(author: author, expiresAt: expiresAt))
        })
    }

    /// Remove a specific author from the cache (e.g. after deleting their last story).
    func remove(did: String) {
        entries.removeValue(forKey: did)
    }

    /// Remove entries whose stories have expired. Call on app foreground and background.
    func purgeExpired() {
        let now = Date()
        entries = entries.filter { $0.value.expiresAt > now }
    }
}

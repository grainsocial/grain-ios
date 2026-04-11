import Foundation

@Observable
@MainActor
final class ViewedStoryStorage {
    private var viewedUris: Set<String> = []
    private var authorLastViewed: [String: String] = [:] // DID → latest story createdAt

    private static let urisKey = "viewedStoryUris"
    private static let authorKey = "viewedStoryAuthors"

    private var saveTask: Task<Void, Never>?

    init() {
        load()
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateFormatterNoFrac: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string) ?? dateFormatterNoFrac.date(from: string)
    }

    /// Mark a story as viewed, updating both the URI set and author timestamp.
    func markViewed(uri: String, authorDid: String, createdAt: String) {
        viewedUris.insert(uri)
        if let existing = authorLastViewed[authorDid],
           let existingDate = Self.parseDate(existing),
           let newDate = Self.parseDate(createdAt)
        {
            if newDate > existingDate {
                authorLastViewed[authorDid] = createdAt
            }
        } else {
            authorLastViewed[authorDid] = createdAt
        }
        scheduleSave()
    }

    /// Check if a specific story has been viewed.
    func isViewed(uri: String) -> Bool {
        viewedUris.contains(uri)
    }

    /// Convenience: check viewed state using StoryStatusCache to resolve `latestAt`.
    func hasViewedAll(did: String, storyStatusCache: StoryStatusCache) -> Bool {
        guard let author = storyStatusCache.author(for: did) else { return false }
        return hasViewedAll(authorDid: did, latestAt: author.latestAt)
    }

    /// Check if all stories from an author have been viewed.
    func hasViewedAll(authorDid: String, latestAt: String) -> Bool {
        guard let lastViewed = authorLastViewed[authorDid],
              let lastViewedDate = Self.parseDate(lastViewed),
              let latestDate = Self.parseDate(latestAt) else { return false }
        return lastViewedDate >= latestDate
    }

    /// Find the index of the first unviewed story in a list.
    /// Returns 0 if all stories have been viewed (replay from start).
    func firstUnviewedIndex(in stories: [any StoryIdentifiable]) -> Int {
        for (index, story) in stories.enumerated() where !viewedUris.contains(story.storyUri) {
            return index
        }
        return 0
    }

    /// Clean up entries older than 24 hours (stories expire).
    func cleanup() {
        let cutoff = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400))
        authorLastViewed = authorLastViewed.filter { $0.value > cutoff }
        // URIs can't be time-filtered easily, but limit set size
        if viewedUris.count > 500 {
            viewedUris = Set(viewedUris.suffix(200))
        }
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.urisKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        {
            viewedUris = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.authorKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        {
            authorLastViewed = decoded
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(viewedUris) {
            UserDefaults.standard.set(data, forKey: Self.urisKey)
        }
        if let data = try? JSONEncoder().encode(authorLastViewed) {
            UserDefaults.standard.set(data, forKey: Self.authorKey)
        }
    }
}

/// Protocol so we can pass different story types to `firstUnviewedIndex`.
protocol StoryIdentifiable {
    var storyUri: String { get }
}

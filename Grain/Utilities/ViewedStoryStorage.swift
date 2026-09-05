import Foundation
import os

private let storageSignposter = OSSignposter(subsystem: "social.grain.grain", category: "AppLaunch")
private let storageLogger = Logger(subsystem: "social.grain.grain", category: "AppLaunch")

/// Which stories this account has watched.
///
/// The appview is the source of truth, so a story watched on the web or on
/// Android is grey here and the other way round. This is the local copy of
/// that: it answers synchronously, which the rings need, and it is what the
/// server's answer gets merged into (`absorb`) and what gets reported back to
/// it (`flushPending`). Reports that fail stay queued until one succeeds.
///
/// Two things are tracked, because the strip and the viewer ask different
/// questions. The URI set answers "has this exact story been seen", which is
/// how the viewer picks the story to open on. The per-author high-water mark
/// answers "is this author fully caught up", which decides the ring.
@Observable
@MainActor
final class ViewedStoryStorage {
    private var viewedUris: Set<String> = []
    private var authorLastViewed: [String: String] = [:] // DID → latest story createdAt
    /// Watched here but not yet acknowledged by the appview.
    private var pendingSync: Set<String> = []

    private static let urisKey = "viewedStoryUris"
    private static let authorKey = "viewedStoryAuthors"
    private static let pendingKey = "viewedStoryPending"

    /// The server accepts this many per call.
    static let syncBatchSize = 100

    private var saveTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    /// Account these entries belong to. What you've watched is per-account.
    private var did: String?

    /// Sends a batch of story URIs to the appview. Wired once the session's
    /// client exists; until then watched stories simply queue.
    @ObservationIgnored var uploader: (@MainActor ([String]) async throws -> Void)?

    private var urisKey: String {
        AccountScopedStorage.key(Self.urisKey, did: did)
    }

    private var authorKey: String {
        AccountScopedStorage.key(Self.authorKey, did: did)
    }

    private var pendingKey: String {
        AccountScopedStorage.key(Self.pendingKey, did: did)
    }

    init(did: String? = AccountScopedStorage.activeAccountID) {
        self.did = did
        load()
    }

    /// Point the store at another account, flushing pending writes for the one
    /// being left behind.
    func switchAccount(did newDID: String?) {
        guard newDID != did else { return }
        saveTask?.cancel()
        syncTask?.cancel()
        save()
        did = newDID
        viewedUris = []
        authorLastViewed = [:]
        pendingSync = []
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

    /// Mark a story as viewed, updating both the URI set and author timestamp,
    /// and queue it for the appview.
    func markViewed(uri: String, authorDid: String, createdAt: String) {
        viewedUris.insert(uri)
        advanceAuthorMark(authorDid: authorDid, to: createdAt)
        pendingSync.insert(uri)
        scheduleSave()
        scheduleSync()
    }

    /// Only ever move the mark forward. Watching an older story again must
    /// not make a newer unwatched one look seen.
    private func advanceAuthorMark(authorDid: String, to createdAt: String) {
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
    }

    // MARK: - Server state

    /// Take on what the appview says has been watched. The strip's author list
    /// carries a per-author high-water mark; nothing here is queued for upload,
    /// because it came from the server in the first place.
    func absorb(authors: [GrainStoryAuthor]) {
        var changed = false
        for author in authors {
            guard let lastViewedAt = author.lastViewedAt else { continue }
            let before = authorLastViewed[author.profile.did]
            advanceAuthorMark(authorDid: author.profile.did, to: lastViewedAt)
            if authorLastViewed[author.profile.did] != before {
                changed = true
            }
        }
        if changed {
            scheduleSave()
        }
    }

    /// Same, from a list of stories: each one the server flags as watched
    /// joins the URI set and moves its author's mark.
    func absorb(stories: [GrainStory]) {
        var changed = false
        for story in stories where story.viewer?.viewed == true {
            if viewedUris.insert(story.uri).inserted {
                changed = true
            }
            let before = authorLastViewed[story.creator.did]
            advanceAuthorMark(authorDid: story.creator.did, to: story.createdAt)
            if authorLastViewed[story.creator.did] != before {
                changed = true
            }
        }
        if changed {
            scheduleSave()
        }
    }

    /// Stories watched here that the appview has not yet been told about.
    var pendingUploadCount: Int {
        pendingSync.count
    }

    /// Report everything queued to the appview. A batch that fails goes back
    /// in the queue for next time; nothing is lost by being offline.
    func flushPending() async {
        guard let uploader, !pendingSync.isEmpty else { return }
        let account = did
        let batch = Array(pendingSync.prefix(Self.syncBatchSize))
        pendingSync.subtract(batch)
        do {
            try await uploader(batch)
        } catch {
            // Only restore if the account is still the one the batch belongs to.
            if account == did {
                pendingSync.formUnion(batch)
            }
            scheduleSave()
            return
        }
        scheduleSave()
        if !pendingSync.isEmpty {
            await flushPending()
        }
    }

    /// A short debounce, so a run of stories goes up as one call.
    private func scheduleSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.flushPending()
        }
    }

    // MARK: - Queries

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
        // URIs can't be time-filtered easily, but limit set size. The upload
        // queue is separate, so trimming here loses nothing the server is owed.
        if viewedUris.count > 500 {
            viewedUris = Set(viewedUris.suffix(200))
        }
        save()
    }

    // MARK: - Persistence

    private func load() {
        let spid = storageSignposter.makeSignpostID()
        let state = storageSignposter.beginInterval("ViewedStorageLoad", id: spid)
        storageLogger.debug("[ViewedStorageLoad] begin")
        defer {
            storageSignposter.endInterval("ViewedStorageLoad", state)
            storageLogger.debug("[ViewedStorageLoad] end uris=\(self.viewedUris.count) authors=\(self.authorLastViewed.count) pending=\(self.pendingSync.count)")
        }
        if let data = StorageEnvironment.defaults.data(forKey: urisKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        {
            viewedUris = decoded
        }
        if let data = StorageEnvironment.defaults.data(forKey: authorKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        {
            authorLastViewed = decoded
        }
        if let data = StorageEnvironment.defaults.data(forKey: pendingKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        {
            pendingSync = decoded
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
            StorageEnvironment.defaults.set(data, forKey: urisKey)
        }
        if let data = try? JSONEncoder().encode(authorLastViewed) {
            StorageEnvironment.defaults.set(data, forKey: authorKey)
        }
        if let data = try? JSONEncoder().encode(pendingSync) {
            StorageEnvironment.defaults.set(data, forKey: pendingKey)
        }
    }
}

/// Protocol so we can pass different story types to `firstUnviewedIndex`.
protocol StoryIdentifiable {
    var storyUri: String { get }
}

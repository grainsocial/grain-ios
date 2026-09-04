import Foundation

/// social.grain.unspecced.getNotifications#notificationItem
struct GrainNotification: Codable, Sendable, Identifiable {
    let uri: String
    let reason: String
    let createdAt: String
    let author: GrainProfile
    var galleryUri: String?
    var galleryTitle: String?
    var galleryThumb: String?
    var storyUri: String?
    var storyThumb: String?
    var commentText: String?
    var replyToText: String?

    var id: String {
        uri
    }

    var reasonType: NotificationReason {
        NotificationReason(rawValue: reason) ?? .unknown
    }
}

enum NotificationReason: String, Sendable {
    case galleryFavorite = "gallery-favorite"
    case galleryComment = "gallery-comment"
    case galleryCommentMention = "gallery-comment-mention"
    case galleryMention = "gallery-mention"
    case commentFavorite = "comment-favorite"
    case storyFavorite = "story-favorite"
    case storyComment = "story-comment"
    case reply
    case follow
    case unknown

    var isGroupable: Bool {
        switch self {
        case .galleryFavorite, .storyFavorite, .commentFavorite, .follow: true
        default: false
        }
    }
}

struct GroupedNotification: Identifiable, Equatable, Hashable {
    static func == (lhs: GroupedNotification, rhs: GroupedNotification) -> Bool {
        lhs.notification.uri == rhs.notification.uri
            && lhs.cachedAuthors.count == rhs.cachedAuthors.count
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(notification.uri)
    }

    let notification: GrainNotification
    var additional: [GrainNotification]
    /// Pre-computed on creation so SwiftUI doesn't recompute during layout.
    private(set) var cachedAuthors: [GrainProfile]

    var id: String {
        notification.uri
    }

    var authorCount: Int {
        cachedAuthors.count
    }

    var isGrouped: Bool {
        !additional.isEmpty
    }

    var allAuthors: [GrainProfile] {
        cachedAuthors
    }

    init(notification: GrainNotification, additional: [GrainNotification]) {
        self.notification = notification
        self.additional = additional
        var seen = Set<String>()
        var authors: [GrainProfile] = []
        for notif in [notification] + additional where seen.insert(notif.author.did).inserted {
            authors.append(notif.author)
        }
        cachedAuthors = authors
    }

    mutating func addAuthor(_ notif: GrainNotification) {
        additional.append(notif)
        if !cachedAuthors.contains(where: { $0.did == notif.author.did }) {
            cachedAuthors.append(notif.author)
        }
    }

    private nonisolated(unsafe) static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    @MainActor
    private static func parseDate(_ str: String) -> TimeInterval {
        dateFormatter.date(from: str)?.timeIntervalSince1970 ?? 0
    }

    @MainActor
    static func group(_ notifications: [GrainNotification]) -> [GroupedNotification] {
        var groups: [GroupedNotification] = []
        mergeNewPage(notifications, into: &groups)
        return groups
    }

    /// Merge a new page into existing groups without regrouping the entire list.
    @MainActor
    static func mergeNewPage(_ newNotifs: [GrainNotification], into groups: inout [GroupedNotification]) {
        for notif in newNotifs {
            if notif.reasonType.isGroupable, absorb(notif, into: &groups) {
                continue
            }
            groups.append(GroupedNotification(notification: notif, additional: []))
        }
    }

    /// How far apart two notifications can be and still read as one event.
    private static let groupingWindow: TimeInterval = 48 * 60 * 60

    /// Fold `notif` into the first group it belongs to, returning false when no
    /// group will take it and it needs a row of its own.
    ///
    /// Somebody already on the row — whether as its head or in its facepile —
    /// is absorbed without being counted twice, rather than being turned away
    /// into a duplicate row. That second case is what an unfavorite followed by
    /// a refavorite looks like coming back from the appview.
    @MainActor
    private static func absorb(_ notif: GrainNotification, into groups: inout [GroupedNotification]) -> Bool {
        let timestamp = parseDate(notif.createdAt)
        let subject = subjectKey(notif)

        for i in groups.indices {
            let group = groups[i]

            guard abs(parseDate(group.notification.createdAt) - timestamp) < groupingWindow,
                  notif.reasonType == group.notification.reasonType,
                  subjectKey(group.notification) == subject
            else { continue }

            let alreadyOnTheRow = notif.author.did == group.notification.author.did
                || group.additional.contains { $0.author.did == notif.author.did }
            if !alreadyOnTheRow {
                groups[i].addAuthor(notif)
            }
            return true
        }

        return false
    }

    private static func subjectKey(_ notif: GrainNotification) -> String {
        if notif.reasonType == .follow {
            return "__follow__"
        }
        return notif.galleryUri ?? notif.storyUri ?? notif.uri
    }
}

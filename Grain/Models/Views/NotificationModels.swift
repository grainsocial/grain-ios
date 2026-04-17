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
        for notif in [notification] + additional {
            if seen.insert(notif.author.did).inserted {
                authors.append(notif.author)
            }
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
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    @MainActor
    private static func parseDate(_ str: String) -> TimeInterval {
        dateFormatter.date(from: str)?.timeIntervalSince1970 ?? 0
    }

    @MainActor
    static func group(_ notifications: [GrainNotification]) -> [GroupedNotification] {
        let twoDays: TimeInterval = 48 * 60 * 60
        var groups: [GroupedNotification] = []

        for notif in notifications {
            guard notif.reasonType.isGroupable else {
                groups.append(GroupedNotification(notification: notif, additional: []))
                continue
            }

            let ts = parseDate(notif.createdAt)
            var matched = false

            for i in groups.indices {
                let g = groups[i]
                let gts = parseDate(g.notification.createdAt)

                guard abs(gts - ts) < twoDays,
                      notif.reasonType == g.notification.reasonType,
                      subjectKey(notif) == subjectKey(g.notification),
                      notif.author.did != g.notification.author.did
                else { continue }

                let alreadyHas = g.additional.contains { $0.author.did == notif.author.did }
                if !alreadyHas {
                    groups[i].addAuthor(notif)
                }
                matched = true
                break
            }

            if !matched {
                groups.append(GroupedNotification(notification: notif, additional: []))
            }
        }

        return groups
    }

    /// Merge a new page into existing groups without regrouping the entire list.
    @MainActor
    static func mergeNewPage(_ newNotifs: [GrainNotification], into groups: inout [GroupedNotification]) {
        let twoDays: TimeInterval = 48 * 60 * 60

        for notif in newNotifs {
            guard notif.reasonType.isGroupable else {
                groups.append(GroupedNotification(notification: notif, additional: []))
                continue
            }

            let ts = parseDate(notif.createdAt)
            var matched = false

            for i in groups.indices {
                let g = groups[i]
                let gts = parseDate(g.notification.createdAt)

                guard abs(gts - ts) < twoDays,
                      notif.reasonType == g.notification.reasonType,
                      subjectKey(notif) == subjectKey(g.notification),
                      notif.author.did != g.notification.author.did
                else { continue }

                let alreadyHas = g.additional.contains { $0.author.did == notif.author.did }
                if !alreadyHas {
                    groups[i].addAuthor(notif)
                }
                matched = true
                break
            }

            if !matched {
                groups.append(GroupedNotification(notification: notif, additional: []))
            }
        }
    }

    private static func subjectKey(_ notif: GrainNotification) -> String {
        if notif.reasonType == .follow { return "__follow__" }
        return notif.galleryUri ?? notif.storyUri ?? notif.uri
    }
}

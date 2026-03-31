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
    var commentText: String?
    var replyToText: String?

    var id: String { uri }

    var reasonType: NotificationReason {
        NotificationReason(rawValue: reason) ?? .unknown
    }
}

enum NotificationReason: String, Sendable {
    case galleryFavorite = "gallery-favorite"
    case galleryComment = "gallery-comment"
    case galleryCommentMention = "gallery-comment-mention"
    case galleryMention = "gallery-mention"
    case reply
    case follow
    case unknown
}

import Foundation
@testable import Grain

/// Response payloads shaped like the real endpoints, so a rendered view takes
/// its loaded branch rather than its error branch. Image URLs point at
/// `test.local` and simply fail to load, which is the same path a broken
/// thumbnail takes in production.
enum Fixtures {
    static let profile = """
    {
      "cid": "bafyprofile",
      "did": "did:plc:test",
      "handle": "tester.grain.social",
      "displayName": "Tester",
      "avatar": "https://test.local/avatar.jpg",
      "createdAt": "2025-01-01T00:00:00Z"
    }
    """

    static let photo = """
    {
      "uri": "at://did:plc:test/social.grain.photo/1",
      "cid": "bafyphoto",
      "thumb": "https://test.local/thumb.jpg",
      "fullsize": "https://test.local/full.jpg",
      "alt": "A test photo",
      "aspectRatio": {"width": 3, "height": 2}
    }
    """

    static let gallery = """
    {
      "uri": "at://did:plc:test/social.grain.gallery/1",
      "cid": "bafygallery",
      "title": "A test gallery",
      "description": "Description long enough to need wrapping in the card.",
      "creator": \(profile),
      "items": [\(photo)],
      "favCount": 3,
      "commentCount": 2,
      "createdAt": "2025-01-02T00:00:00Z",
      "indexedAt": "2025-01-02T00:00:00Z"
    }
    """

    static let feed = """
    {"items": [\(gallery)], "cursor": null}
    """

    static let notifications = """
    {
      "notifications": [
        {
          "uri": "at://did:plc:test/notification/1",
          "reason": "like",
          "createdAt": "2025-01-03T00:00:00Z",
          "author": \(profile),
          "galleryUri": "at://did:plc:test/social.grain.gallery/1",
          "galleryTitle": "A test gallery"
        },
        {
          "uri": "at://did:plc:test/notification/2",
          "reason": "follow",
          "createdAt": "2025-01-03T00:00:00Z",
          "author": \(profile)
        },
        {
          "uri": "at://did:plc:test/notification/3",
          "reason": "comment",
          "createdAt": "2025-01-03T00:00:00Z",
          "author": \(profile),
          "commentText": "A test comment"
        }
      ],
      "cursor": null
    }
    """
}

extension Fixtures {
    /// `getGallery` wraps the gallery; the bare object above is what the feed
    /// returns inside its items array.
    static let galleryResponse = """
    {"gallery": \(gallery)}
    """

    static let commentThread = """
    {
      "comments": [
        {
          "uri": "at://did:plc:test/social.grain.comment/1",
          "cid": "bafycomment1",
          "author": \(profile),
          "text": "A comment mentioning @tester.grain.social and #film.",
          "createdAt": "2025-01-03T00:00:00Z",
          "favCount": 2
        },
        {
          "uri": "at://did:plc:test/social.grain.comment/2",
          "cid": "bafycomment2",
          "author": \(profile),
          "text": "A reply to it.",
          "replyTo": "at://did:plc:test/social.grain.comment/1",
          "createdAt": "2025-01-03T01:00:00Z"
        }
      ],
      "cursor": null,
      "totalCount": 2
    }
    """
}

// MARK: - Whole-app routing

extension Fixtures {
    static let profileDetailed = """
    {
      "cid": "bafyprofile",
      "did": "did:plc:test",
      "handle": "tester.grain.social",
      "displayName": "Tester",
      "description": "A profile with a description long enough to wrap onto a second line.",
      "avatar": "https://test.local/avatar.jpg",
      "cameras": ["Fujifilm X100V", "Leica M6"],
      "followersCount": 1200,
      "followsCount": 34,
      "galleryCount": 5,
      "indexedAt": "2025-01-01T00:00:00Z",
      "createdAt": "2025-01-01T00:00:00Z"
    }
    """

    /// Two people, one already followed, so a list renders both button states.
    static let actorList = """
    {"totalCount": 2, "items": [
      {
        "did": "did:plc:a", "handle": "alpha.test", "displayName": "Alpha",
        "description": "First person", "avatar": "https://test.local/a.jpg",
        "viewer": {"following": "at://did:plc:test/social.grain.graph.follow/1"}
      },
      {"did": "did:plc:b", "handle": "beta.test", "displayName": "Beta", "viewer": {}}
    ], "cursor": null}
    """

    static let blockList = """
    {"items": [
      {"did": "did:plc:a", "handle": "alpha.test", "displayName": "Alpha",
       "avatar": "https://test.local/a.jpg", "blockUri": "at://did:plc:test/social.grain.graph.block/1"},
      {"did": "did:plc:b", "handle": "beta.test", "blockUri": "at://did:plc:test/social.grain.graph.block/2"}
    ], "cursor": null}
    """

    static let muteList = """
    {"items": [
      {"did": "did:plc:a", "handle": "alpha.test", "displayName": "Alpha", "avatar": "https://test.local/a.jpg"},
      {"did": "did:plc:b", "handle": "beta.test"}
    ], "cursor": null}
    """

    static let suggestedFollows = """
    {"items": [
      {"did": "did:plc:a", "handle": "alpha.test", "displayName": "Alpha", "followersCount": 120},
      {"did": "did:plc:b", "handle": "beta.test", "followersCount": 3}
    ]}
    """

    static let storyAuthors = """
    {"authors": [
      {"profile": \(profile), "storyCount": 2, "latestAt": "\(freshTimestamp)"},
      {
        "profile": {"cid": "c2", "did": "did:plc:other", "handle": "other.test", "displayName": "Other"},
        "storyCount": 1, "latestAt": "\(freshTimestamp)"
      }
    ]}
    """

    static let stories = """
    {"stories": [
      {
        "uri": "at://did:plc:test/social.grain.story/1", "cid": "bafystory1",
        "creator": \(profile),
        "thumb": "https://test.local/thumb.jpg", "fullsize": "https://test.local/full.jpg",
        "aspectRatio": {"width": 3, "height": 4},
        "createdAt": "\(freshTimestamp)"
      },
      {
        "uri": "at://did:plc:test/social.grain.story/2", "cid": "bafystory2",
        "creator": \(profile),
        "thumb": "https://test.local/thumb2.jpg", "fullsize": "https://test.local/full2.jpg",
        "aspectRatio": {"width": 4, "height": 3},
        "locationDisplay": "Test City",
        "createdAt": "\(freshTimestamp)"
      }
    ]}
    """

    static let preferences = """
    {"preferences": {
      "pinnedFeeds": [
        {"id": "recent", "label": "Recent", "type": "feed", "path": "/"},
        {"id": "following", "label": "Following", "type": "feed", "path": "/feeds/following"},
        {"id": "camera:Leica M6", "label": "Leica M6", "type": "camera", "path": "/c/leica"}
      ],
      "includeExif": true,
      "includeLocation": true
    }}
    """

    static let labelDefinitions = """
    {"definitions": [
      {"identifier": "nudity", "blurs": "media", "defaultSetting": "warn",
       "locales": [{"name": "Nudity"}]},
      {"identifier": "spoiler", "blurs": "content", "defaultSetting": "warn",
       "locales": [{"name": "Spoiler"}]}
    ]}
    """

    static let locations = """
    {"locations": [
      {"name": "Lisboa", "h3Index": "8a2a1072b59ffff", "galleryCount": 12},
      {"name": "Porto", "h3Index": "8a2a1072b58ffff", "galleryCount": 4}
    ]}
    """

    static let cameras = """
    {"cameras": [
      {"camera": "Fujifilm X100V", "photoCount": 40},
      {"camera": "Leica M6", "photoCount": 12}
    ]}
    """

    /// Stories expire 24 hours after `latestAt`, so a literal date would turn
    /// every story fixture into a time bomb.
    static var freshTimestamp: String {
        DateFormatting.nowISO(date: Date().addingTimeInterval(-3600))
    }

    /// A correct payload for every endpoint a screen might fan out to, so a
    /// render settles on its loaded state rather than its error state.
    static var routes: [String: String] {
        [
            "getFeed": feed,
            "getGallery": galleryResponse,
            "getCommentThread": commentThread,
            "getPreferences": preferences,
            "getLocations": locations,
            "getCameras": cameras,
            "searchGalleries": feed,
            "searchProfiles": actorList,
            "searchActorsTypeahead": #"{"actors": []}"#,
            "getActorProfile": profileDetailed,
            "getProfile": profileDetailed,
            "getStoryAuthors": storyAuthors,
            "getStoryArchive": stories,
            "getStories": stories,
            "getStory": #"{"story": null}"#,
            "getNotifications": notifications,
            "describeLabels": labelDefinitions,
            "getKnownFollowers": actorList,
            "getGalleryFavorites": actorList,
            "getFollowers": actorList,
            "getFollowing": actorList,
            "getSuggestedFollows": suggestedFollows,
            "getBlocks": blockList,
            "getMutes": muteList,
            "getActorFavorites": feed,
            "getActorGalleries": feed,
        ]
    }
}

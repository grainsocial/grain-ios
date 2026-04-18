import AppIntents
import Foundation

// MARK: - Shortcut action routing

extension Notification.Name {
    static let grainShortcutAction = Notification.Name("GrainShortcutAction")
}

enum GrainShortcutAction: String {
    case feed, search, notifications, profile, createGallery, createStory
}

// MARK: - Intents

struct OpenFeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Feed"
    static let description = IntentDescription("Browse your photo feed in Grain.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .grainShortcutAction, object: GrainShortcutAction.feed.rawValue)
        return .result()
    }
}

struct OpenSearchIntent: AppIntent {
    static let title: LocalizedStringResource = "Search"
    static let description = IntentDescription("Search for photos, profiles, and hashtags in Grain.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .grainShortcutAction, object: GrainShortcutAction.search.rawValue)
        return .result()
    }
}

struct OpenNotificationsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Notifications"
    static let description = IntentDescription("Check your latest activity in Grain.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .grainShortcutAction, object: GrainShortcutAction.notifications.rawValue)
        return .result()
    }
}

struct OpenProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Open My Profile"
    static let description = IntentDescription("View your profile and galleries in Grain.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .grainShortcutAction, object: GrainShortcutAction.profile.rawValue)
        return .result()
    }
}

struct CreateStoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Story"
    static let description = IntentDescription("Start posting a new story in Grain.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .grainShortcutAction, object: GrainShortcutAction.createStory.rawValue)
        return .result()
    }
}

struct CreateGalleryIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Gallery"
    static let description = IntentDescription("Start posting a new photo gallery in Grain.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .grainShortcutAction, object: GrainShortcutAction.createGallery.rawValue)
        return .result()
    }
}

// MARK: - Shortcuts provider

struct GrainShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateStoryIntent(),
            phrases: [
                "Create a story in \(.applicationName)",
                "New \(.applicationName) story",
                "Post a \(.applicationName) story",
            ],
            shortTitle: "Create Story",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CreateGalleryIntent(),
            phrases: [
                "Create a gallery in \(.applicationName)",
                "New \(.applicationName) gallery",
                "Post to \(.applicationName)",
            ],
            shortTitle: "Create Gallery",
            systemImageName: "plus.square.on.square"
        )
        AppShortcut(
            intent: OpenFeedIntent(),
            phrases: [
                "Open feed in \(.applicationName)",
                "Show \(.applicationName) feed",
            ],
            shortTitle: "Open Feed",
            systemImageName: "photo.on.rectangle"
        )
        AppShortcut(
            intent: OpenSearchIntent(),
            phrases: [
                "Search in \(.applicationName)",
                "Open \(.applicationName) search",
            ],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenNotificationsIntent(),
            phrases: [
                "Open \(.applicationName) notifications",
                "Show \(.applicationName) notifications",
            ],
            shortTitle: "Notifications",
            systemImageName: "bell"
        )
        AppShortcut(
            intent: OpenProfileIntent(),
            phrases: [
                "Open my \(.applicationName) profile",
                "Show my \(.applicationName) profile",
            ],
            shortTitle: "My Profile",
            systemImageName: "person"
        )
    }
}

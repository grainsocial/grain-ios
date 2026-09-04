@testable import Grain
import XCTest

/// Siri phrases and the Home Screen quick actions both end up posting one
/// notification that `MainTabView` listens for. The rawValues are the contract
/// between the two halves, and nothing else checks that they still line up.
@MainActor
final class AppShortcutsTests: GrainTestCase {
    private func actionPosted(by run: @MainActor () async throws -> Void) async rethrows -> String? {
        final class Box: @unchecked Sendable {
            var value: String?
        }
        let box = Box()
        let token = NotificationCenter.default.addObserver(
            forName: .grainShortcutAction, object: nil, queue: nil
        ) { notification in
            box.value = notification.object as? String
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await run()
        return box.value
    }

    func testEveryIntentPostsItsOwnAction() async throws {
        let cases: [(String, @MainActor () async throws -> Void)] = [
            (GrainShortcutAction.feed.rawValue, { _ = try await OpenFeedIntent().perform() }),
            (GrainShortcutAction.search.rawValue, { _ = try await OpenSearchIntent().perform() }),
            (GrainShortcutAction.notifications.rawValue, { _ = try await OpenNotificationsIntent().perform() }),
            (GrainShortcutAction.profile.rawValue, { _ = try await OpenProfileIntent().perform() }),
            (GrainShortcutAction.createStory.rawValue, { _ = try await CreateStoryIntent().perform() }),
            (GrainShortcutAction.createGallery.rawValue, { _ = try await CreateGalleryIntent().perform() }),
        ]

        for (expected, run) in cases {
            let posted = try await actionPosted(by: run)
            XCTAssertEqual(posted, expected)
        }
    }

    /// The Info.plist quick actions carry these strings, so renaming a case
    /// silently breaks the Home Screen long-press menu.
    func testTheActionRawValuesAreTheOnesTheInfoPlistUses() {
        XCTAssertEqual(GrainShortcutAction.createStory.rawValue, "createStory")
        XCTAssertEqual(GrainShortcutAction.createGallery.rawValue, "createGallery")
        XCTAssertEqual(GrainShortcutAction(rawValue: "feed"), .feed)
        XCTAssertNil(GrainShortcutAction(rawValue: "somethingElse"))
    }

    /// Every quick action declared in Info.plist has to map to a case the app
    /// can route, or long-pressing the icon does nothing.
    func testEveryInfoPlistQuickActionMapsToAKnownAction() throws {
        let items = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]],
            "The app bundle declares no quick actions"
        )
        XCTAssertFalse(items.isEmpty)

        for item in items {
            let type = try XCTUnwrap(item["UIApplicationShortcutItemType"] as? String)
            let suffix = String(type.split(separator: ".").last ?? "")
            XCTAssertNotNil(
                GrainShortcutAction(rawValue: suffix),
                "Quick action \(type) doesn't map to a GrainShortcutAction"
            )
            XCTAssertFalse((item["UIApplicationShortcutItemTitle"] as? String ?? "").isEmpty)
        }
    }

    /// The provider is resolved by the system at install time; a malformed one
    /// silently drops every phrase.
    func testTheShortcutsProviderDeclaresOneShortcutPerIntent() {
        XCTAssertEqual(GrainShortcuts.appShortcuts.count, 6)
    }
}

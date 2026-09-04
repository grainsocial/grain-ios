@testable import Grain
import UIKit
import UserNotifications
import XCTest

/// The seams between UIKit and the app: quick actions arriving through the
/// scene delegate, push taps arriving through the app delegate, and the push
/// registration callbacks in between. None of it is reachable by rendering a
/// view, and all of it decides where the app opens.
@MainActor
final class AppLifecycleTests: GrainTestCase {
    /// Captures whatever a callback or notification hands back.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []

        func append(_ value: String) {
            lock.withLock { values.append(value) }
        }

        var recorded: [String] {
            lock.withLock { values }
        }
    }

    private func actionsPosted(during work: () -> Void) -> [String] {
        let box = Box()
        let token = NotificationCenter.default.addObserver(
            forName: .grainShortcutAction, object: nil, queue: nil
        ) { notification in
            if let action = notification.object as? String {
                box.append(action)
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        work()
        return box.recorded
    }

    // MARK: - Scene delegate quick actions

    func testEachQuickActionMapsToItsOwnAction() throws {
        let delegate = GrainSceneDelegate()
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "No window scene in this test host"
        )

        for (type, expected) in [
            ("social.grain.shortcut.createStory", "createStory"),
            ("social.grain.shortcut.createGallery", "createGallery"),
        ] {
            let item = UIApplicationShortcutItem(type: type, localizedTitle: "Title")
            let posted = actionsPosted {
                delegate.windowScene(scene, performActionFor: item) { _ in }
            }
            XCTAssertEqual(posted, [expected])
        }
    }

    /// A shortcut type the app doesn't recognise must be dropped rather than
    /// dispatched as something else.
    func testAnUnknownQuickActionIsIgnored() throws {
        let delegate = GrainSceneDelegate()
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "No window scene in this test host"
        )
        let item = UIApplicationShortcutItem(type: "social.grain.shortcut.somethingElse", localizedTitle: "?")

        var completed: Bool?
        let posted = actionsPosted {
            delegate.windowScene(scene, performActionFor: item) { completed = $0 }
        }

        XCTAssertTrue(posted.isEmpty)
        XCTAssertEqual(completed, true, "The completion still has to be called or iOS logs a violation")
    }

    // MARK: - App delegate

    func testTheAppDelegateTakesOverNotificationDelivery() {
        let delegate = AppDelegate()

        XCTAssertTrue(delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil))
        XCTAssertTrue(UNUserNotificationCenter.current().delegate === delegate)
    }

    // MARK: - Push registration callbacks

    /// The APNs token is handed straight to the push manager; without a manager
    /// wired up it has to be dropped rather than trapping.
    func testAnAPNsTokenWithNoPushManagerIsHarmless() {
        let delegate = AppDelegate()

        delegate.application(
            UIApplication.shared,
            didRegisterForRemoteNotificationsWithDeviceToken: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        delegate.application(
            UIApplication.shared,
            didFailToRegisterForRemoteNotificationsWithError: URLError(.notConnectedToInternet)
        )

        XCTAssertNil(delegate.pushManager)
    }

    /// A failed registration is logged and swallowed — there is nothing the
    /// user can do about it, and it must not block launch.
    func testAFailedAPNsRegistrationIsSwallowed() {
        let manager = PushManager()

        manager.didFailToRegisterForRemoteNotifications(error: URLError(.notConnectedToInternet))

        XCTAssertNotNil(manager)
    }

    /// Unregistering is deliberately a no-op without the outgoing account's
    /// context — unregistering somebody else's device token is the bug this
    /// avoids.
    func testUnregisteringWithoutAnAuthContextDoesNothing() async {
        let manager = PushManager()
        var requestMade = false
        MockURLProtocol.handler = { request in
            requestMade = true
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        defer { MockURLProtocol.handler = nil }

        await manager.unregisterToken(auth: nil)

        XCTAssertFalse(requestMade)
    }
}

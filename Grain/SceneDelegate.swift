import UIKit

@MainActor
class GrainSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _: UIScene,
        willConnectTo _: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let item = connectionOptions.shortcutItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Self.dispatch(type: item.type)
            }
        }
    }

    func windowScene(
        _: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Self.dispatch(type: shortcutItem.type)
        completionHandler(true)
    }

    private static func dispatch(type: String) {
        let action: GrainShortcutAction? = switch type {
        case "social.grain.shortcut.createStory": .createStory
        case "social.grain.shortcut.createGallery": .createGallery
        default: nil
        }
        if let action {
            NotificationCenter.default.post(name: .grainShortcutAction, object: action.rawValue)
        }
    }
}

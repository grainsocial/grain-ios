import Nuke
import SwiftUI

@main
struct GrainApp: App {
    init() {
        var config = ImagePipeline.Configuration.withDataCache
        if let dataCache = try? DataCache(name: "social.grain.images") {
            config.dataCache = dataCache
        }
        ImagePipeline.shared = ImagePipeline(configuration: config)
    }

    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var authManager = AuthManager()
    @State private var pushManager = PushManager()
    @State private var storyStatusCache = StoryStatusCache()
    @State private var viewedStoryStorage = ViewedStoryStorage()
    @State private var labelDefsCache = LabelDefinitionsCache()
    @State private var pendingDeepLink: DeepLink?

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    MainTabView(pendingDeepLink: $pendingDeepLink)
                        .environment(authManager)
                        .environment(pushManager)
                        .environment(storyStatusCache)
                        .environment(viewedStoryStorage)
                        .environment(labelDefsCache)
                        .tint(Color("AccentColor"))
                        .onAppear {
                            viewedStoryStorage.cleanup()
                            pushManager.configure(authManager: authManager)
                            appDelegate.pushManager = pushManager
                            appDelegate.onNotificationTap = { deepLink in
                                pendingDeepLink = deepLink
                            }
                            authManager.onLogout = { [pushManager] in
                                pushManager.unregisterToken()
                            }
                            pushManager.registerIfNeeded()
                        }
                } else {
                    LoginView()
                        .environment(authManager)
                        .tint(Color("AccentColor"))
                }
            }
            .onOpenURL { url in
                if let deepLink = DeepLink.from(url: url) {
                    pendingDeepLink = deepLink
                }
            }
            .onChange(of: scenePhase) {
                if scenePhase == .background {
                    viewedStoryStorage.cleanup()
                }
            }
        }
        .environment(authManager)
    }
}

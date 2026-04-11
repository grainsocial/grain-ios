import Nuke
import os
import SwiftUI

private let appSignposter = OSSignposter(subsystem: "social.grain.grain", category: "AppLaunch")
private let appLogger = Logger(subsystem: "social.grain.grain", category: "AppLaunch")

@main
struct GrainApp: App {
    init() {
        // Defer Nuke DataCache setup off the main-thread init path — no images
        // load during the ~800ms before MainTabView.task fires, so this is safe.
        Task.detached(priority: .userInitiated) {
            let spid = appSignposter.makeSignpostID()
            let state = appSignposter.beginInterval("NukePipelineSetup", id: spid)
            appLogger.debug("[NukePipelineSetup] begin")
            var config = ImagePipeline.Configuration.withDataCache
            if let dataCache = try? DataCache(name: "social.grain.images") {
                config.dataCache = dataCache
            }
            await MainActor.run { ImagePipeline.shared = ImagePipeline(configuration: config) }
            appSignposter.endInterval("NukePipelineSetup", state)
            appLogger.debug("[NukePipelineSetup] end")
        }
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
                            Task {
                                viewedStoryStorage.cleanup()
                                storyStatusCache.purgeExpired()
                            }
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
                    Task {
                        viewedStoryStorage.cleanup()
                        storyStatusCache.purgeExpired()
                    }
                }
            }
        }
        .environment(authManager)
    }
}

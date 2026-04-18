import AppIntents
import Nuke
import os
import SwiftUI

private let appSignposter = OSSignposter(subsystem: "social.grain.grain", category: "AppLaunch")
private let appLogger = Logger(subsystem: "social.grain.grain", category: "AppLaunch")

@main
struct GrainApp: App {
    init() {
        LaunchMetrics.beginTFP()
        LaunchMetrics.beginPreBody()
        appSignposter.emitEvent("GrainAppInitBegin")
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
            await MainActor.run { ImagePipeline.shared = ImagePipeline(configuration: config, delegate: GrainImagePipelineDelegate()) }
            appSignposter.endInterval("NukePipelineSetup", state)
            appLogger.debug("[NukePipelineSetup] end")
        }
        Task.detached(priority: .userInitiated) {
            let spid = appSignposter.makeSignpostID()
            let state = appSignposter.beginInterval("ConnectionPreheat", id: spid)
            var req = URLRequest(url: AuthManager.serverURL.appendingPathComponent("_health"))
            req.httpMethod = "GET"
            req.timeoutInterval = 5
            _ = try? await URLSession.shared.data(for: req)
            appSignposter.endInterval("ConnectionPreheat", state)
        }
        appSignposter.emitEvent("GrainAppInitEnd")
    }

    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var authManager = AuthManager()
    @State private var pushManager = PushManager()
    @State private var storyStatusCache = StoryStatusCache()
    @State private var viewedStoryStorage = ViewedStoryStorage()
    @State private var labelDefsCache = LabelDefinitionsCache()
    @State private var pendingDeepLink: DeepLink?
    @AppStorage("appearance") private var appearance: String = "auto"

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            let _ = appSignposter.emitEvent("WindowGroupBodyBegin")
            let isAuthed = authManager.isAuthenticated
            let _ = appSignposter.emitEvent("AuthGateResolved")
            Group {
                if isAuthed {
                    MainTabView(pendingDeepLink: $pendingDeepLink)
                        .environment(authManager)
                        .environment(pushManager)
                        .environment(storyStatusCache)
                        .environment(viewedStoryStorage)
                        .environment(labelDefsCache)
                        .tint(Color.accentColor)
                        .onAppear {
                            appSignposter.emitEvent("WindowOnAppear")
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
                        .tint(Color.accentColor)
                }
            }
            .onOpenURL { url in
                if let deepLink = DeepLink.from(url: url) {
                    pendingDeepLink = deepLink
                }
            }
            .task(priority: .background) {
                GrainShortcuts.updateAppShortcutParameters()
            }
            .preferredColorScheme(colorScheme)
        }
        .environment(authManager)
    }
}

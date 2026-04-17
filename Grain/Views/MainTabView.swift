import os
import SwiftUI

private let launchSignposter = OSSignposter(subsystem: "social.grain.grain", category: "AppLaunch")
private let launchLogger = Logger(subsystem: "social.grain.grain", category: "AppLaunch")

private enum AppTab: Hashable {
    case feed, notifications, profile, search
}

struct MainTabView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(LabelDefinitionsCache.self) private var labelDefsCache
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @Environment(ViewedStoryStorage.self) private var viewedStories
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .feed
    @State private var commentPresenter = StoryCommentPresenter()
    @State private var client: XRPCClient?
    @State private var showCreate = false
    @State private var avatarTabImage: UIImage?
    @State private var feedRefreshID = UUID()
    @State private var notificationsVM = NotificationsViewModel(client: XRPCClient(baseURL: AuthManager.serverURL))
    @Binding var pendingDeepLink: DeepLink?

    @MainActor static let badgeAppearanceConfigured: Bool = MainActor.assumeIsolated {
        let _spid = launchSignposter.makeSignpostID()
        let _state = launchSignposter.beginInterval("BadgeAppearanceSetup", id: _spid)
        let color = UIColor(named: "AccentColor")
        let textAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]
        let appearance = UITabBarAppearance()
        @MainActor func apply(_ itemAppearance: UITabBarItemAppearance) {
            itemAppearance.normal.badgeBackgroundColor = color
            itemAppearance.normal.badgeTextAttributes = textAttrs
            itemAppearance.selected.badgeBackgroundColor = color
            itemAppearance.selected.badgeTextAttributes = textAttrs
        }
        apply(appearance.stackedLayoutAppearance)
        apply(appearance.inlineLayoutAppearance)
        apply(appearance.compactInlineLayoutAppearance)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        launchSignposter.endInterval("BadgeAppearanceSetup", _state)
        return true
    }

    var body: some View {
        let _ = launchSignposter.emitEvent("MainTabViewBodyBegin")
        let _ = LaunchMetrics.endPreBodyOnce()
        let _ = Self.badgeAppearanceConfigured
        Group {
            if let client {
                let _ = launchSignposter.emitEvent("TabViewBodyBegin")
                TabView(selection: $selectedTab) {
                    Tab("Feed", systemImage: "photo.on.rectangle", value: AppTab.feed) {
                        FeedView(client: client, pendingDeepLink: $pendingDeepLink, showCreate: $showCreate)
                            .id(feedRefreshID)
                    }

                    Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                        SearchView(client: client)
                    }

                    Tab("Notifications", systemImage: "bell", value: AppTab.notifications) {
                        NotificationsView(client: client, viewModel: notificationsVM)
                    }
                    .badge(notificationsVM.unseenCount)

                    Tab(value: AppTab.profile) {
                        if let did = auth.userDID {
                            ProfileView(client: client, did: did, isRoot: true)
                        }
                    } label: {
                        if let img = avatarTabImage {
                            Label {
                                Text("Profile")
                            } icon: {
                                Image(uiImage: img)
                                    .renderingMode(.original)
                            }
                        } else {
                            Label("Profile", systemImage: "person")
                        }
                    }
                }
                .tint(Color.accentColor)
                .environment(commentPresenter)
            } else {
                Color.clear
            }
        }
        .task {
            let taskSpid = launchSignposter.makeSignpostID()
            let taskState = launchSignposter.beginInterval("MainTabLaunch", id: taskSpid)
            launchLogger.debug("[MainTabLaunch] begin")

            commentPresenter.configure(
                auth: auth,
                storyStatusCache: storyStatusCache,
                viewedStories: viewedStories
            )
            let c = auth.makeClient()
            client = c
            notificationsVM.updateClient(c)

            // Start avatar fetch immediately — it doesn't need an auth context
            let avatarSpid = launchSignposter.makeSignpostID()
            let avatarState = launchSignposter.beginInterval("AvatarFetch", id: avatarSpid)
            launchLogger.debug("[AvatarFetch] begin")
            async let avatarFetch: Void = auth.fetchAvatarIfNeeded()

            // Resolve auth context once (may refresh token) while avatar is in flight
            let ctx = await auth.authContext()

            // Kick off notifications + label defs in parallel now that we have ctx
            let notifSpid = launchSignposter.makeSignpostID()
            let labelsSpid = launchSignposter.makeSignpostID()
            let notifState = launchSignposter.beginInterval("NotificationsFetch", id: notifSpid)
            launchLogger.debug("[NotificationsFetch] begin")
            let labelsState = launchSignposter.beginInterval("LabelDefsFetch", id: labelsSpid)
            launchLogger.debug("[LabelDefsFetch] begin")
            async let notifFetch: Void = notificationsVM.fetchUnseenCount(auth: ctx)
            async let labelsFetch: Void = labelDefsCache.loadIfNeeded(client: c, auth: ctx)

            await avatarFetch
            launchSignposter.endInterval("AvatarFetch", avatarState)
            launchLogger.debug("[AvatarFetch] end")

            await notifFetch
            launchSignposter.endInterval("NotificationsFetch", notifState)
            launchLogger.debug("[NotificationsFetch] end")

            await labelsFetch
            launchSignposter.endInterval("LabelDefsFetch", labelsState)
            launchLogger.debug("[LabelDefsFetch] end")

            launchSignposter.endInterval("MainTabLaunch", taskState)
            launchLogger.debug("[MainTabLaunch] end")
        }
        .onChange(of: auth.avatarImage) {
            if let uiImage = auth.avatarImage {
                avatarTabImage = circularAvatar(uiImage, size: 26)
            }
        }
        .onChange(of: pendingDeepLink) {
            if pendingDeepLink != nil {
                selectedTab = .feed
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task {
                    try? await auth.refreshIfNeeded()
                    await notificationsVM.fetchUnseenCount(auth: auth.authContext())
                    if let client {
                        await labelDefsCache.loadIfNeeded(client: client, auth: auth.authContext())
                    }
                }
            } else if scenePhase == .background {
                Task {
                    viewedStories.cleanup()
                    storyStatusCache.purgeExpired()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .grainShortcutAction)) { notification in
            guard let rawValue = notification.object as? String,
                  let action = GrainShortcutAction(rawValue: rawValue)
            else { return }
            switch action {
            case .feed: selectedTab = .feed
            case .search: selectedTab = .search
            case .notifications: selectedTab = .notifications
            case .profile: selectedTab = .profile
            case .createGallery:
                selectedTab = .feed
                showCreate = true
            }
        }
    }

    private func circularAvatar(_ image: UIImage, size: CGFloat) -> UIImage {
        let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let circled = renderer.image { _ in
            UIBezierPath(ovalIn: rect).addClip()
            image.draw(in: rect)
        }
        return circled.withRenderingMode(.alwaysOriginal)
    }
}

#Preview {
    MainTabView(pendingDeepLink: .constant(nil))
        .previewEnvironments()
        .environment(PushManager())
}

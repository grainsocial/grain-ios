import SwiftUI

private enum AppTab: Hashable {
    case feed, notifications, profile, search
}

struct MainTabView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(LabelDefinitionsCache.self) private var labelDefsCache
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .feed
    @State private var client = XRPCClient(baseURL: AuthManager.serverURL)
    @State private var showCreate = false
    @State private var avatarTabImage: UIImage?
    @State private var feedRefreshID = UUID()
    @State private var notificationsVM = NotificationsViewModel(client: XRPCClient(baseURL: AuthManager.serverURL))
    @Binding var pendingDeepLink: DeepLink?

    @MainActor static let badgeAppearanceConfigured: Bool = MainActor.assumeIsolated {
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
        return true
    }

    var body: some View {
        let _ = Self.badgeAppearanceConfigured
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
        .tint(Color("AccentColor"))
        .task {
            let c = auth.makeClient()
            client = c
            notificationsVM.updateClient(c)
            await auth.fetchAvatarIfNeeded()
            if let uiImage = auth.avatarImage {
                avatarTabImage = circularAvatar(uiImage, size: 26)
            }
            await notificationsVM.fetchUnseenCount(auth: auth.authContext())
            await labelDefsCache.loadIfNeeded(client: c, auth: auth.authContext())
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
                    await labelDefsCache.loadIfNeeded(client: client, auth: auth.authContext())
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
        .environment(AuthManager())
        .environment(PushManager())
        .environment(StoryStatusCache())
        .environment(ViewedStoryStorage())
        .environment(LabelDefinitionsCache())
}

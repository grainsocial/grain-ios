import SwiftUI

struct MainTabView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var client = XRPCClient(baseURL: AuthManager.serverURL)
    @State private var showCreate = false
    @State private var avatarTabImage: UIImage?
    @State private var feedRefreshID = UUID()
    @State private var notificationsVM = NotificationsViewModel(client: XRPCClient(baseURL: AuthManager.serverURL))
    @Binding var pendingDeepLink: DeepLink?

    static let badgeAppearanceConfigured: Bool = {
        let color = UIColor(named: "AccentColor")
        let textAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]
        let appearance = UITabBarAppearance()
        func apply(_ itemAppearance: UITabBarItemAppearance) {
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
    }()

    var body: some View {
        let _ = Self.badgeAppearanceConfigured
        TabView(selection: $selectedTab) {
            TabSection {
                Tab("Feed", systemImage: "photo.on.rectangle", value: 0) {
                    FeedView(client: client, pendingDeepLink: $pendingDeepLink, showCreate: $showCreate)
                        .id(feedRefreshID)
                }

                Tab("Notifications", systemImage: "bell", value: 1) {
                    NotificationsView(client: client, viewModel: notificationsVM)
                }
                .badge(notificationsVM.unseenCount)

                Tab(value: 2) {
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
        }
        .tabBarMinimizeBehavior(.onScrollDown)
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
        }
        .onChange(of: auth.avatarImage) {
            if let uiImage = auth.avatarImage {
                avatarTabImage = circularAvatar(uiImage, size: 26)
            }
        }
        .onChange(of: pendingDeepLink) {
            if pendingDeepLink != nil {
                selectedTab = 0
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await notificationsVM.fetchUnseenCount(auth: auth.authContext()) }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateGalleryView(client: client) {
                selectedTab = 0
                feedRefreshID = UUID()
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

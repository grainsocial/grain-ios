import SwiftUI

struct MainTabView: View {
    @Environment(AuthManager.self) private var auth
    @State private var selectedTab = 0
    @State private var client = XRPCClient(baseURL: AuthManager.serverURL)
    @State private var showCreate = false
    @State private var avatarTabImage: UIImage?
    @State private var feedRefreshID = UUID()

    var body: some View {
        TabView(selection: $selectedTab) {
            TabSection {
                Tab("Feed", systemImage: "photo.on.rectangle", value: 0) {
                    FeedView(client: client)
                        .id(feedRefreshID)
                }

                Tab("Search", systemImage: "magnifyingglass", value: 1) {
                    SearchView(client: client)
                }

                Tab("Notifications", systemImage: "bell", value: 2) {
                    NotificationsView(client: client)
                }

                Tab(value: 3) {
                    if let did = auth.userDID {
                        ProfileView(client: client, did: did)
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

            Tab(value: 99, role: .search) {
                Color.clear
            } label: {
                Label("Create", systemImage: "plus")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            client = auth.makeClient()
            await auth.fetchAvatarIfNeeded()
            if let uiImage = auth.avatarImage {
                avatarTabImage = circularAvatar(uiImage, size: 26)
            }
        }
        .onChange(of: auth.avatarImage) {
            if let uiImage = auth.avatarImage {
                avatarTabImage = circularAvatar(uiImage, size: 26)
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 99 {
                selectedTab = oldValue
                showCreate = true
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                CreateGalleryView(client: client) {
                    selectedTab = 0
                    feedRefreshID = UUID()
                }
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


import SwiftUI

@main
struct GrainApp: App {
    @State private var authManager = AuthManager()
    @State private var pendingDeepLink: DeepLink?

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    MainTabView(pendingDeepLink: $pendingDeepLink)
                        .environment(authManager)
                        .tint(Color("AccentColor"))
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
        }
        .environment(authManager)
    }
}

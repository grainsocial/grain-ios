import SwiftUI

@main
struct GrainApp: App {
    @State private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                MainTabView()
                    .environment(authManager)
                    .tint(Color("AccentColor"))
            } else {
                LoginView()
                    .environment(authManager)
                    .tint(Color("AccentColor"))
            }
        }
        .environment(authManager)
    }
}

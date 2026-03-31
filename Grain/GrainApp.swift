import SwiftUI

@main
struct GrainApp: App {
    @State private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                MainTabView()
                    .environment(authManager)
            } else {
                LoginView()
                    .environment(authManager)
            }
        }
        .environment(authManager)
    }
}

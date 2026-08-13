import SwiftUI

struct ModerationView: View {
    let client: XRPCClient

    var body: some View {
        List {
            NavigationLink("Muted users") {
                MutedUsersView(client: client)
            }
            NavigationLink("Blocked users") {
                BlockedUsersView(client: client)
            }
        }
        .navigationTitle("Moderation")
    }
}

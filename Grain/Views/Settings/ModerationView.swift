import SwiftUI

struct ModerationView: View {
    let client: XRPCClient

    var body: some View {
        List {
            NavigationLink("Muted Users") {
                MutedUsersView(client: client)
            }
            NavigationLink("Blocked Users") {
                BlockedUsersView(client: client)
            }
        }
        .navigationTitle("Moderation")
    }
}

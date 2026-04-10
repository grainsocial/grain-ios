import SwiftUI

struct ModerationView: View {
    let client: XRPCClient

    var body: some View {
        List {
            NavigationLink {
                BlockedUsersView(client: client)
            } label: {
                Label("Blocked Users", systemImage: "nosign")
            }
            NavigationLink {
                MutedUsersView(client: client)
            } label: {
                Label("Muted Users", systemImage: "speaker.slash")
            }
        }
        .navigationTitle("Moderation")
    }
}

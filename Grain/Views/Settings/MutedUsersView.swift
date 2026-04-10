import NukeUI
import SwiftUI

struct MutedUsersView: View {
    @Environment(AuthManager.self) private var auth
    let client: XRPCClient
    @State private var items: [MuteItem] = []
    @State private var isLoading = true
    @State private var unmuting: Set<String> = []

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No Muted Users",
                    systemImage: "speaker.slash",
                    description: Text("You haven't muted anyone.")
                )
            } else {
                List {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            NavigationLink {
                                ProfileView(client: client, did: item.did)
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(url: item.avatar, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.displayName ?? item.handle ?? item.did)
                                            .font(.subheadline.weight(.semibold))
                                        if let handle = item.handle {
                                            Text("@\(handle)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                Task { await unmute(item) }
                            } label: {
                                Text("Unmute")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .disabled(unmuting.contains(item.did))
                        }
                    }
                }
            }
        }
        .navigationTitle("Muted Users")
        .task {
            await loadMutes()
        }
    }

    private func loadMutes() async {
        guard let authContext = await auth.authContext() else { return }
        do {
            let response = try await client.getMutes(auth: authContext)
            items = response.items ?? []
        } catch {}
        isLoading = false
    }

    private func unmute(_ item: MuteItem) async {
        guard let authContext = await auth.authContext() else { return }
        unmuting.insert(item.did)
        do {
            try await client.unmuteActor(did: item.did, auth: authContext)
            items.removeAll { $0.did == item.did }
        } catch {}
        unmuting.remove(item.did)
    }
}

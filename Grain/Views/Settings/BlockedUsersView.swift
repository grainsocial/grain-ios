import NukeUI
import SwiftUI

struct BlockedUsersView: View {
    @Environment(AuthManager.self) private var auth
    let client: XRPCClient
    @State private var items: [BlockItem] = []
    @State private var isLoading = true
    @State private var unblocking: Set<String> = []

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No Blocked Users",
                    systemImage: "nosign",
                    description: Text("You haven't blocked anyone.")
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
                                Task { await unblock(item) }
                            } label: {
                                Text("Unblock")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .disabled(unblocking.contains(item.did))
                        }
                    }
                }
            }
        }
        .navigationTitle("Blocked Users")
        .task {
            await loadBlocks()
        }
    }

    private func loadBlocks() async {
        guard let authContext = await auth.authContext() else { return }
        do {
            let response = try await client.getBlocks(auth: authContext)
            items = response.items ?? []
        } catch {}
        isLoading = false
    }

    private func unblock(_ item: BlockItem) async {
        guard let authContext = await auth.authContext() else { return }
        unblocking.insert(item.did)
        do {
            try await client.unblockActor(blockUri: item.blockUri, auth: authContext)
            items.removeAll { $0.did == item.did }
        } catch {}
        unblocking.remove(item.did)
    }
}

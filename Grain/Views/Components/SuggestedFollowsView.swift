import SwiftUI

struct SuggestedFollowsView: View {
    @Environment(AuthManager.self) private var auth
    let client: XRPCClient
    @Binding var suggestions: [SuggestedItem]
    var onProfileTap: ((String) -> Void)?
    @State private var dismissedDids: Set<String> = []
    @State private var followedDids: Set<String> = []
    @State private var followingInProgress: Set<String> = []

    private var visibleItems: [SuggestedItem] {
        suggestions.filter { !dismissedDids.contains($0.did) && !followedDids.contains($0.did) }
    }

    var body: some View {
        if !visibleItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Suggested for you")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(visibleItems) { item in
                            suggestionCard(item)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func suggestionCard(_ item: SuggestedItem) -> some View {
        VStack(spacing: 10) {
            AvatarView(url: item.avatar, size: 64)
                .onTapGesture { onProfileTap?(item.did) }

            Text(item.displayName ?? item.handle ?? "")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Text(item.description ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32)

            Button {
                followUser(item)
            } label: {
                Text("Follow")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(followingInProgress.contains(item.did))
        }
        .frame(width: 150)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.secondary.opacity(0.1))
        }
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation { _ = dismissedDids.insert(item.did) }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .padding(6)
        }
    }

    private func followUser(_ item: SuggestedItem) {
        followingInProgress.insert(item.did)
        Task {
            guard let authContext = await auth.authContext() else { return }
            let record = AnyCodable([
                "subject": item.did,
                "createdAt": DateFormatting.nowISO(),
            ])
            let repo = TokenStorage.userDID ?? ""
            do {
                _ = try await client.createRecord(collection: "social.grain.graph.follow", repo: repo, record: record, auth: authContext)
                withAnimation { _ = followedDids.insert(item.did) }
            } catch {}
            followingInProgress.remove(item.did)
        }
    }
}

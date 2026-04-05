import NukeUI
import SwiftUI

enum FollowListMode: Hashable {
    case followers
    case following
    case knownFollowers
}

struct FollowListView: View {
    @Environment(AuthManager.self) private var auth
    let client: XRPCClient
    let did: String
    let mode: FollowListMode
    @State private var items: [FollowListItem] = []
    @State private var cursor: String?
    @State private var totalCount: Int?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var selectedProfileDid: String?
    @State private var cardStoryAuthor: GrainStoryAuthor?
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @Environment(ViewedStoryStorage.self) private var viewedStories

    private var title: String {
        switch mode {
        case .followers: "Followers"
        case .following: "Following"
        case .knownFollowers: "Followers you know"
        }
    }

    private var displayCount: String {
        "\(totalCount ?? items.count) \(title.lowercased())"
    }

    var body: some View {
        Group {
            if !hasLoaded, isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hasLoaded, items.isEmpty {
                ContentUnavailableView(
                    "No \(title)",
                    systemImage: mode == .knownFollowers ? "person.2" : mode == .followers ? "person.2" : "person.badge.plus",
                    description: Text(mode == .knownFollowers ? "None of the people you follow are following this account." : mode == .followers ? "No one is following this account yet." : "This account isn't following anyone yet.")
                )
            } else {
                List {
                    ForEach(items) { item in
                        Button {
                            selectedProfileDid = item.did
                        } label: {
                            rowContent(item: item)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.visible)
                        .onAppear {
                            if item.id == items.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await reload()
                }
            }
        }
        .navigationTitle(title)
        .navigationDestination(item: $selectedProfileDid) { did in
            ProfileView(client: client, did: did)
        }
        .fullScreenCover(item: $cardStoryAuthor) { author in
            StoryViewer(
                authors: [author],
                client: client,
                onProfileTap: { did in
                    cardStoryAuthor = nil
                    selectedProfileDid = did
                },
                onDismiss: { cardStoryAuthor = nil }
            )
            .environment(auth)
        }
        .task {
            await reload()
        }
        .onAppear {
            if hasLoaded {
                Task { await reload() }
            }
        }
    }

    private func rowContent(item: FollowListItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            StoryRingView(hasStory: storyStatusCache.hasStory(for: item.did), viewed: viewedStories.hasViewedAll(did: item.did, storyStatusCache: storyStatusCache), size: 50) {
                AvatarView(url: item.avatar, size: 50)
            }
            .onTapGesture {
                if let author = storyStatusCache.author(for: item.did) {
                    cardStoryAuthor = author
                } else {
                    selectedProfileDid = item.did
                }
            }
            .onLongPressGesture {
                selectedProfileDid = item.did
            }
            VStack(alignment: .leading, spacing: 2) {
                if let displayName = item.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                if let handle = item.handle {
                    Text(handle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let desc = item.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func reload() async {
        cursor = nil
        do {
            switch mode {
            case .followers:
                let response = try await client.getFollowers(actor: did, viewer: auth.userDID, cursor: nil, auth: auth.authContext())
                items = (response.items ?? []).map { FollowListItem(from: $0) }
                cursor = response.cursor
                totalCount = response.totalCount
            case .following:
                let response = try await client.getFollowing(actor: did, viewer: auth.userDID, cursor: nil, auth: auth.authContext())
                items = (response.items ?? []).map { FollowListItem(from: $0) }
                cursor = response.cursor
                totalCount = response.totalCount
            case .knownFollowers:
                if let viewer = auth.userDID {
                    let response = try await client.getKnownFollowers(actor: did, viewer: viewer, auth: auth.authContext())
                    items = (response.items ?? []).map { FollowListItem(from: $0) }
                    totalCount = items.count
                }
            }
        } catch {
            // keep existing items on error
        }
        hasLoaded = true
    }

    private func loadMore() async {
        guard !isLoading else { return }
        if !items.isEmpty, cursor == nil { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let existingIDs = Set(items.map(\.id))
            switch mode {
            case .followers:
                let response = try await client.getFollowers(actor: did, viewer: auth.userDID, cursor: cursor, auth: auth.authContext())
                if let newItems = response.items {
                    let filtered = newItems.filter { !existingIDs.contains($0.did) }
                    items.append(contentsOf: filtered.map { FollowListItem(from: $0) })
                }
                cursor = response.cursor
            case .following:
                let response = try await client.getFollowing(actor: did, viewer: auth.userDID, cursor: cursor, auth: auth.authContext())
                if let newItems = response.items {
                    let filtered = newItems.filter { !existingIDs.contains($0.did) }
                    items.append(contentsOf: filtered.map { FollowListItem(from: $0) })
                }
                cursor = response.cursor
            case .knownFollowers:
                break // No pagination for known followers
            }
        } catch {
            // silently fail
        }
    }

    private func toggleFollow(for targetDid: String) async {
        guard let authContext = auth.authContext(), let repo = auth.userDID else { return }
        guard let index = items.firstIndex(where: { $0.did == targetDid }) else { return }
        let item = items[index]

        if let followUri = item.followingUri, followUri != "pending" {
            let rkey = followUri.split(separator: "/").last.map(String.init) ?? ""
            items[index].followingUri = nil
            do {
                try await client.deleteRecord(collection: "social.grain.graph.follow", rkey: rkey, auth: authContext)
                if mode == .following, did == repo {
                    if let idx = items.firstIndex(where: { $0.did == targetDid }) {
                        items.remove(at: idx)
                    }
                    if let count = totalCount { totalCount = max(0, count - 1) }
                }
            } catch {
                if let idx = items.firstIndex(where: { $0.did == targetDid }) {
                    items[idx].followingUri = followUri
                }
            }
        } else if item.followingUri == nil {
            items[index].followingUri = "pending"
            do {
                let record = AnyCodable([
                    "subject": item.did,
                    "createdAt": DateFormatting.nowISO(),
                ])
                let result = try await client.createRecord(
                    collection: "social.grain.graph.follow",
                    repo: repo,
                    record: record,
                    auth: authContext
                )
                if let idx = items.firstIndex(where: { $0.did == targetDid }) {
                    items[idx].followingUri = result.uri
                }
            } catch {
                if let idx = items.firstIndex(where: { $0.did == targetDid }) {
                    items[idx].followingUri = nil
                }
            }
        }
    }
}

struct FollowListItem: Identifiable {
    let did: String
    var handle: String?
    var displayName: String?
    var description: String?
    var avatar: String?
    var followingUri: String?
    var id: String {
        did
    }

    init(from follower: FollowerItem) {
        did = follower.did
        handle = follower.handle
        displayName = follower.displayName
        description = follower.description
        avatar = follower.avatar
        followingUri = follower.viewer?.following
    }

    init(from following: FollowingItem) {
        did = following.did
        handle = following.handle
        displayName = following.displayName
        description = following.description
        avatar = following.avatar
        followingUri = following.viewer?.following
    }
}

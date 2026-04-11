import SwiftUI

struct StoryStripView: View {
    @Environment(ViewedStoryStorage.self) private var viewedStories
    let authors: [GrainStoryAuthor]
    let userDid: String?
    let userAvatar: String?
    var sortVersion: Int = 0
    let onAuthorTap: (GrainStoryAuthor, Int) -> Void
    var onAuthorLongPress: ((String) -> Void)?
    let onCreateTap: () -> Void

    private let avatarSize: CGFloat = 68

    @State private var sorted: [GrainStoryAuthor] = []
    @State private var liftedDids: Set<String> = []

    private var ownAuthor: GrainStoryAuthor? {
        authors.first(where: { $0.profile.did == userDid })
    }

    private func computeSorted() -> [GrainStoryAuthor] {
        let others = authors.filter { $0.profile.did != userDid }
        let unviewed = others.filter { !viewedStories.hasViewedAll(authorDid: $0.profile.did, latestAt: $0.latestAt) }
        let viewed = others.filter { viewedStories.hasViewedAll(authorDid: $0.profile.did, latestAt: $0.latestAt) }
        return unviewed + viewed
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // Your story
                VStack(spacing: 4) {
                    ZStack(alignment: .bottomTrailing) {
                        StoryRingView(hasStory: ownAuthor != nil, viewed: false, size: avatarSize) {
                            AvatarView(url: userAvatar, size: avatarSize)
                        }
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, Color("AccentColor"))
                            .offset(x: 2, y: 2)
                    }
                    Text("Your story")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .onTapGesture {
                    if let own = ownAuthor {
                        onAuthorTap(own, 0)
                    } else {
                        onCreateTap()
                    }
                }
                .onLongPressGesture {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onCreateTap()
                }

                ForEach(sorted, id: \.id) { author in
                    let isViewed = viewedStories.hasViewedAll(authorDid: author.profile.did, latestAt: author.latestAt)
                    let isLifted = liftedDids.contains(author.profile.did)
                    VStack(spacing: 4) {
                        StoryRingView(hasStory: true, viewed: isViewed, size: avatarSize) {
                            AvatarView(url: author.profile.avatar, size: avatarSize)
                        }
                        Text(author.profile.displayName ?? author.profile.handle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: avatarSize + 8)
                    }
                    .scaleEffect(isLifted ? 1.03 : 1.0)
                    .offset(y: isLifted ? -3 : 0)
                    .zIndex(isViewed ? 0 : 1)
                    .onTapGesture { onAuthorTap(author, 0) }
                    .onLongPressGesture { onAuthorLongPress?(author.profile.did) }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
        .onAppear { sorted = computeSorted() }
        .onChange(of: authors.map(\.id)) { sorted = computeSorted() }
        .onChange(of: sortVersion) {
            let newSorted = computeSorted()

            // Find where old and new order diverge — that's the gap
            let oldIds = sorted.map(\.profile.did)
            let newIds = newSorted.map(\.profile.did)

            withAnimation(.smooth(duration: 0.5)) {
                sorted = newSorted
            }

            // Skip wave if order didn't change
            guard oldIds != newIds,
                  let gapIndex = zip(oldIds, newIds).enumerated().first(where: { $1.0 != $1.1 })?.offset
            else { return }

            // Wave follows the read card as it slides right past unreads
            let unreadCount = newSorted.count(where: { !viewedStories.hasViewedAll(authorDid: $0.profile.did, latestAt: $0.latestAt) })
            let travelDistance = max(unreadCount - gapIndex, 1)
            for (index, author) in newSorted.enumerated() {
                guard !viewedStories.hasViewedAll(authorDid: author.profile.did, latestAt: author.latestAt) else { continue }
                guard index >= gapIndex else { continue }
                let did = author.profile.did
                let progress = Double(index - gapIndex) / Double(travelDistance)
                let delay = progress * 0.4
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                        _ = liftedDids.insert(did)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.18) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        _ = liftedDids.remove(did)
                    }
                }
            }
        }
    }
}

#Preview {
    StoryStripView(
        authors: PreviewData.storyAuthors,
        userDid: "did:plc:prevuser1",
        userAvatar: nil,
        onAuthorTap: { _, _ in },
        onCreateTap: {}
    )
    .previewEnvironments()
}

import SwiftUI

struct StoryStripView: View {
    @Environment(ViewedStoryStorage.self) private var viewedStories
    let authors: [GrainStoryAuthor]
    let userAvatar: String?
    let onAuthorTap: (GrainStoryAuthor, Int) -> Void
    var onAuthorLongPress: ((String) -> Void)?
    let onCreateTap: () -> Void

    private let avatarSize: CGFloat = 68

    var body: some View {
        let unviewed = authors.filter { !viewedStories.hasViewedAll(authorDid: $0.profile.did, latestAt: $0.latestAt) }
        let viewed = authors.filter { viewedStories.hasViewedAll(authorDid: $0.profile.did, latestAt: $0.latestAt) }
        let sorted = unviewed + viewed
        let orderKey = sorted.map(\.id).joined(separator: ",")

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // Create button
                VStack(spacing: 4) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(url: userAvatar, size: avatarSize)
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
                .onTapGesture { onCreateTap() }

                ForEach(sorted, id: \.id) { author in
                    let isViewed = viewedStories.hasViewedAll(authorDid: author.profile.did, latestAt: author.latestAt)
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
                    .onTapGesture { onAuthorTap(author, 0) }
                    .onLongPressGesture { onAuthorLongPress?(author.profile.did) }
                }
            }
            .id(orderKey)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

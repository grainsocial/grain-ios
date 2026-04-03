import SwiftUI

struct StoryStripView: View {
    let authors: [GrainStoryAuthor]
    let userAvatar: String?
    let onAuthorTap: (GrainStoryAuthor, Int) -> Void
    var onAuthorLongPress: ((String) -> Void)?
    let onCreateTap: () -> Void

    private let avatarSize: CGFloat = 68

    var body: some View {
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

                // Author avatars
                ForEach(Array(authors.enumerated()), id: \.element.id) { index, author in
                    VStack(spacing: 4) {
                        StoryRingView(hasStory: true, size: avatarSize) {
                            AvatarView(url: author.profile.avatar, size: avatarSize)
                        }
                        Text(author.profile.displayName ?? author.profile.handle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: avatarSize + 8)
                    }
                    .onTapGesture { onAuthorTap(author, index) }
                    .onLongPressGesture { onAuthorLongPress?(author.profile.did) }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

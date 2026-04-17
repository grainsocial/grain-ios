import Nuke
import NukeUI
import os
import SwiftUI

private let notificationsLaunchSignposter = OSSignposter(subsystem: "social.grain.grain", category: "AppLaunch")

struct NotificationsView: View {
    @Environment(AuthManager.self) private var auth
    var viewModel: NotificationsViewModel
    @State private var selectedGalleryUri: String?
    @State private var selectedProfileDid: String?
    @State private var cardStoryAuthor: GrainStoryAuthor?
    @State private var selectedStory: GrainStory?
    @State private var selectedGroup: GroupedNotification?
    let client: XRPCClient

    init(client: XRPCClient, viewModel: NotificationsViewModel) {
        self.client = client
        self.viewModel = viewModel
        notificationsLaunchSignposter.emitEvent("NotificationsViewInit")
    }

    var body: some View {
        let _ = notificationsLaunchSignposter.emitEvent("NotificationsViewBodyBegin")
        NavigationStack {
            NotificationListContent(
                viewModel: viewModel,
                client: client,
                authContext: { await auth.authContext() },
                onProfileTap: { selectedProfileDid = $0 },
                onGalleryTap: { selectedGalleryUri = $0 },
                onStoryAuthorTap: { cardStoryAuthor = $0 },
                onStoryTap: { selectedStory = $0 },
                onGroupTap: { selectedGroup = $0 }
            )
            .navigationTitle("Notifications")
            .navigationDestination(item: $selectedGalleryUri) { uri in
                GalleryDetailView(client: client, galleryUri: uri)
            }
            .navigationDestination(item: $selectedProfileDid) { did in
                ProfileView(client: client, did: did)
            }
            .navigationDestination(item: $selectedGroup) { group in
                GroupedAuthorsView(
                    group: group,
                    client: client
                )
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
            .fullScreenCover(item: $selectedStory) { story in
                StoryViewer(
                    authors: [GrainStoryAuthor(
                        profile: story.creator,
                        storyCount: 1,
                        latestAt: story.createdAt
                    )],
                    initialStories: [story],
                    client: client,
                    onProfileTap: { did in
                        selectedStory = nil
                        selectedProfileDid = did
                    },
                    onDismiss: { selectedStory = nil }
                )
                .environment(auth)
            }
            .task {
                if viewModel.notifications.isEmpty || viewModel.unseenCount > 0 {
                    await viewModel.loadInitial(auth: auth.authContext())
                }
                if viewModel.unseenCount > 0 {
                    await viewModel.markAsSeen(auth: auth.authContext())
                }
            }
        }
    }
}

// MARK: - List Content (no @Environment — auth passed as closure)

private struct NotificationListContent: View {
    let viewModel: NotificationsViewModel
    let client: XRPCClient
    let authContext: () async -> AuthContext?
    let onProfileTap: (String) -> Void
    let onGalleryTap: (String) -> Void
    let onStoryAuthorTap: (GrainStoryAuthor) -> Void
    let onStoryTap: (GrainStory) -> Void
    let onGroupTap: (GroupedNotification) -> Void

    var body: some View {
        List {
            ForEach(viewModel.grouped) { group in
                NotificationRowContainer(
                    group: group,
                    client: client,
                    authContext: authContext,
                    onProfileTap: onProfileTap,
                    onGalleryTap: onGalleryTap,
                    onStoryAuthorTap: onStoryAuthorTap,
                    onStoryTap: onStoryTap,
                    onGroupTap: onGroupTap
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .onAppear {
                    if group.id == viewModel.grouped.last?.id {
                        Task { await viewModel.loadMore(auth: authContext()) }
                    }
                }
            }
            .listRowSeparator(.visible)
            .listRowSeparatorTint(Color(.separator))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.loadInitial(auth: authContext())
        }
    }
}

// MARK: - Row Container (no @Environment — auth passed as closure)

private struct NotificationRowContainer: View {
    let group: GroupedNotification
    let client: XRPCClient
    let authContext: () async -> AuthContext?
    let onProfileTap: (String) -> Void
    let onGalleryTap: (String) -> Void
    let onStoryAuthorTap: (GrainStoryAuthor) -> Void
    let onStoryTap: (GrainStory) -> Void
    let onGroupTap: (GroupedNotification) -> Void

    var body: some View {
        if group.isGrouped {
            GroupedNotificationRow(
                group: group,
                onProfileTap: onProfileTap,
                onSubjectTap: { handleTap(group.notification) },
                onGroupTap: { onGroupTap(group) }
            )
        } else {
            SingleNotificationRow(
                notification: group.notification,
                onProfileTap: onProfileTap,
                onSubjectTap: { handleTap(group.notification) }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                handleTap(group.notification)
            }
            .swipeActions(edge: .leading) {
                Button {
                    onProfileTap(group.notification.author.did)
                } label: {
                    Label("Profile", systemImage: "person")
                }
            }
        }
    }

    private func handleTap(_ notification: GrainNotification) {
        if notification.reasonType == .follow {
            onProfileTap(notification.author.did)
        } else if notification.reasonType == .storyFavorite || notification.reasonType == .storyComment {
            if let storyUri = notification.storyUri {
                Task {
                    if let story = try? await client.getStory(uri: storyUri, auth: authContext()).story {
                        onStoryTap(story)
                    }
                }
            } else {
                onProfileTap(notification.author.did)
            }
        } else if let galleryUri = notification.galleryUri {
            onGalleryTap(galleryUri)
        }
    }
}

// MARK: - Reason Icon

private struct ReasonIcon: View {
    let reason: NotificationReason

    private var iconName: String {
        switch reason {
        case .galleryFavorite, .storyFavorite: "heart.fill"
        case .follow: "person.fill.badge.plus"
        case .galleryComment, .storyComment: "text.bubble.fill"
        case .reply: "arrowshape.turn.up.backward.fill"
        case .galleryCommentMention, .galleryMention: "at"
        case .unknown: "bell.fill"
        }
    }

    private var label: String {
        switch reason {
        case .galleryFavorite, .storyFavorite: "Liked"
        case .follow: "Followed"
        case .galleryComment, .storyComment: "Commented"
        case .reply: "Replied"
        case .galleryCommentMention, .galleryMention: "Mentioned"
        case .unknown: "Notification"
        }
    }

    private var iconColor: Color {
        switch reason {
        case .galleryFavorite, .storyFavorite: .heart
        default: .accentColor
        }
    }

    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(iconColor)
            .font(.system(size: 18))
            .frame(width: 20)
            .accessibilityLabel(label)
    }
}

// MARK: - Grouped Notification Row

private struct GroupedNotificationRow: View {
    let group: GroupedNotification
    var onProfileTap: ((String) -> Void)?
    var onSubjectTap: (() -> Void)?
    var onGroupTap: (() -> Void)?

    private var thumb: String? {
        group.notification.galleryThumb ?? group.notification.storyThumb
    }

    private var isStoryThumb: Bool {
        group.notification.galleryThumb == nil && group.notification.storyThumb != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ReasonIcon(reason: group.notification.reasonType)
                .frame(height: 38)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    OverlappingAvatarsView(
                        authors: Array(group.allAuthors.prefix(5)),
                        size: 38,
                        overlap: 8,
                        onProfileTap: onProfileTap
                    )
                    if group.authorCount > 5 {
                        Button {
                            onGroupTap?()
                        } label: {
                            Text("+\(group.authorCount - 5)")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 6)
                    }
                    Spacer(minLength: 0)
                }

                let name = group.notification.author.displayName ?? group.notification.author.handle
                let othersCount = group.authorCount - 1
                let others = othersCount == 1 ? "1 other" : "\(othersCount) others"
                Button {
                    onSubjectTap?()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Text(name).bold()) and \(others) \(reasonText) \(Text(DateFormatting.relativeTime(group.notification.createdAt)).foregroundStyle(.secondary))")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        if group.notification.reasonType == .galleryFavorite,
                           let title = group.notification.galleryTitle
                        {
                            Text(title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, thumb != nil ? 54 : 0)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            if let thumb {
                Button { onSubjectTap?() } label: {
                    CachedThumbnailView(url: thumb, size: 44, portrait: isStoryThumb)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reasonText: String {
        switch group.notification.reasonType {
        case .galleryFavorite: "favorited your gallery"
        case .storyFavorite: "favorited your story"
        case .follow: "followed you"
        default: ""
        }
    }
}

// MARK: - Single Notification Row

private struct SingleNotificationRow: View {
    let notification: GrainNotification
    var onProfileTap: ((String) -> Void)?
    var onSubjectTap: (() -> Void)?

    private var thumb: String? {
        notification.galleryThumb ?? notification.storyThumb
    }

    private var isStoryThumb: Bool {
        notification.galleryThumb == nil && notification.storyThumb != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ReasonIcon(reason: notification.reasonType)
                .frame(height: 38)

            VStack(alignment: .leading, spacing: 6) {
                AvatarView(url: notification.author.avatar, size: 38, animated: false)
                    .onTapGesture {
                        onProfileTap?(notification.author.did)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Text(notification.author.displayName ?? notification.author.handle).bold()) \(reasonText) \(Text(DateFormatting.relativeTime(notification.createdAt)).foregroundStyle(.secondary))")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if notification.reasonType == .galleryFavorite,
                       let title = notification.galleryTitle
                    {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let commentText = notification.commentText {
                        Text(commentText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding(.trailing, thumb != nil ? 54 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            if let thumb {
                Button { onSubjectTap?() } label: {
                    CachedThumbnailView(url: thumb, size: 44, portrait: isStoryThumb)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reasonText: String {
        switch notification.reasonType {
        case .galleryFavorite: "favorited your gallery"
        case .galleryComment: "commented on your gallery"
        case .galleryCommentMention: "mentioned you in a comment"
        case .galleryMention: "mentioned you in a gallery"
        case .storyFavorite: "favorited your story"
        case .storyComment: "commented on your story"
        case .reply: "replied to your comment"
        case .follow: "followed you"
        case .unknown: ""
        }
    }
}

// MARK: - Overlapping Avatars

private struct OverlappingAvatarsView: View {
    let authors: [GrainProfile]
    let size: CGFloat
    let overlap: CGFloat
    var onProfileTap: ((String) -> Void)?

    private var step: CGFloat {
        size - overlap
    }

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(authors.enumerated()), id: \.element.did) { i, author in
                Button {
                    onProfileTap?(author.did)
                } label: {
                    AvatarView(url: author.avatar, size: size, animated: false)
                }
                .buttonStyle(.plain)
                .zIndex(Double(authors.count - i))
            }
        }
        .fixedSize()
    }
}

// MARK: - Cached Thumbnail (sync cache read, no LazyImage)

private struct CachedThumbnailView: View {
    let url: String
    let size: CGFloat
    var portrait: Bool = false

    private var width: CGFloat {
        size
    }

    private var height: CGFloat {
        portrait ? size * 4 / 3 : size
    }

    private var imageURL: URL? {
        URL(string: url)
    }

    var body: some View {
        LazyImage(url: imageURL) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .processors([ImageProcessors.Resize(size: CGSize(width: width * UIScreen.main.scale, height: height * UIScreen.main.scale), contentMode: .aspectFill)])
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 6))
    }
}

// MARK: - Grouped Authors Detail View

private struct GroupedAuthorsView: View {
    let group: GroupedNotification
    let client: XRPCClient

    private var title: String {
        let count = group.authorCount
        switch group.notification.reasonType {
        case .galleryFavorite: return "\(count) Favorites"
        case .storyFavorite: return "\(count) Favorites"
        case .follow: return "\(count) Followers"
        default: return "\(count) People"
        }
    }

    var body: some View {
        List {
            ForEach(group.allAuthors, id: \.did) { author in
                NavigationLink {
                    ProfileView(client: client, did: author.did)
                } label: {
                    HStack(alignment: .center, spacing: 14) {
                        AvatarView(url: author.avatar, size: 50, animated: false)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                if let displayName = author.displayName, !displayName.isEmpty {
                                    Text(displayName)
                                        .font(.body.weight(.semibold))
                                        .lineLimit(1)
                                }
                                Text("@\(author.handle)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if let desc = author.description, !desc.isEmpty {
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
                .buttonStyle(.plain)
                .listRowSeparator(.visible)
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let client = XRPCClient.preview
    let vm = NotificationsViewModel(client: client)
    vm.notifications = PreviewData.notifications
    vm.grouped = GroupedNotification.group(vm.notifications)
    vm.unseenCount = 3
    return NotificationsView(client: client, viewModel: vm)
        .previewEnvironments()
        .grainPreview()
        .frame(maxHeight: .infinity, alignment: .top)
}

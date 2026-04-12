import Nuke
import SwiftUI

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
    }

    var body: some View {
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
                if viewModel.notifications.isEmpty {
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
        case .galleryComment, .storyComment: "bubble.left.fill"
        case .reply: "arrowshape.turn.up.left.fill"
        case .galleryCommentMention, .galleryMention: "at"
        case .unknown: "bell.fill"
        }
    }

    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(Color("AccentColor"))
            .font(.system(size: 14))
            .frame(width: 20)
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ReasonIcon(reason: group.notification.reasonType)
                .padding(.top, 4)

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
                        Text("\(Text(name).bold()) and \(others) \(reasonText) \(Text(DateFormatting.relativeTime(group.notification.createdAt)).foregroundStyle(.tertiary))")
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
                    CachedThumbnailView(url: thumb, height: 44)
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ReasonIcon(reason: notification.reasonType)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                AvatarView(url: notification.author.avatar, size: 34, animated: false)
                    .onTapGesture {
                        onProfileTap?(notification.author.did)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Text(notification.author.displayName ?? notification.author.handle).bold()) \(reasonText) \(Text(DateFormatting.relativeTime(notification.createdAt)).foregroundStyle(.tertiary))")
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
                    CachedThumbnailView(url: thumb, height: 44)
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

// MARK: - Overlapping Avatars (UIKit-backed, zero SwiftUI layout participation)

private struct OverlappingAvatarsView: UIViewRepresentable {
    let authors: [GrainProfile]
    let size: CGFloat
    let overlap: CGFloat
    var onProfileTap: ((String) -> Void)?

    private var totalWidth: CGFloat {
        guard !authors.isEmpty else { return 0 }
        return size + CGFloat(authors.count - 1) * (size - overlap)
    }

    func makeUIView(context _: Context) -> OverlappingAvatarsUIView {
        let view = OverlappingAvatarsUIView()
        view.onProfileTap = onProfileTap
        view.configure(authors: authors, size: size, overlap: overlap)
        return view
    }

    func updateUIView(_ uiView: OverlappingAvatarsUIView, context _: Context) {
        uiView.onProfileTap = onProfileTap
        uiView.configure(authors: authors, size: size, overlap: overlap)
    }

    func sizeThatFits(_: ProposedViewSize, uiView _: OverlappingAvatarsUIView, context _: Context) -> CGSize? {
        CGSize(width: totalWidth, height: size)
    }
}

final class OverlappingAvatarsUIView: UIView {
    var onProfileTap: ((String) -> Void)?
    private var avatarViews: [UIImageView] = []
    private var authorDids: [String] = []
    private var currentKey = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: OverlappingAvatarsUIView, _) in
            for iv in view.avatarViews {
                iv.layer.borderColor = UIColor.systemBackground.cgColor
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func configure(authors: [GrainProfile], size: CGFloat, overlap: CGFloat) {
        let key = authors.map(\.did).joined(separator: ",")
        guard key != currentKey else { return }
        currentKey = key
        authorDids = authors.map(\.did)

        // Remove old views
        avatarViews.forEach { $0.removeFromSuperview() }
        avatarViews.removeAll()

        let step = size - overlap

        for (i, author) in authors.enumerated() {
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.layer.cornerRadius = size / 2
            iv.layer.borderWidth = 2
            iv.layer.borderColor = UIColor.systemBackground.cgColor
            iv.backgroundColor = UIColor.gray.withAlphaComponent(0.3)
            iv.frame = CGRect(x: CGFloat(i) * step, y: 0, width: size, height: size)

            // Load from Nuke memory cache synchronously, or fetch async
            if let url = author.avatar, let imageURL = URL(string: url) {
                let request = ImageRequest(url: imageURL)
                if let cached = ImagePipeline.shared.cache.cachedImage(for: request)?.image {
                    iv.image = cached
                } else {
                    Task { @MainActor in
                        if let image = try? await ImagePipeline.shared.image(for: request) {
                            iv.image = image
                        }
                    }
                }
            }

            addSubview(iv)
            avatarViews.append(iv)
        }

        let totalWidth = size + CGFloat(authors.count - 1) * step
        frame.size = CGSize(width: totalWidth, height: size)
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        frame.size
    }

    override func hitTest(_ point: CGPoint, with _: UIEvent?) -> UIView? {
        // Claim hit for any touch inside an avatar circle
        for iv in avatarViews.reversed() {
            if iv.frame.contains(point) { return self }
        }
        return nil
    }

    override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        // Check avatars in reverse order (topmost first)
        for (i, iv) in avatarViews.enumerated().reversed() {
            if iv.frame.contains(location) {
                if i < authorDids.count {
                    onProfileTap?(authorDids[i])
                }
                return
            }
        }
    }
}

// MARK: - Cached Thumbnail (sync cache read, no LazyImage)

private struct CachedThumbnailView: View {
    let url: String
    let height: CGFloat

    @State private var asyncImage: UIImage?

    private var imageURL: URL? {
        URL(string: url)
    }

    private var resolvedImage: UIImage? {
        if let imageURL,
           let cached = ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: imageURL))?.image
        {
            return cached
        }
        return asyncImage
    }

    var body: some View {
        Group {
            if let image = resolvedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle().fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: 6))
        .onAppear { loadIfNeeded() }
    }

    private func loadIfNeeded() {
        guard let imageURL else { return }
        let request = ImageRequest(url: imageURL)
        if ImagePipeline.shared.cache.cachedImage(for: request) != nil { return }
        guard asyncImage == nil else { return }
        Task {
            if let image = try? await ImagePipeline.shared.image(for: request) {
                asyncImage = image
            }
        }
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
        .frame(maxHeight: .infinity, alignment: .top)
}

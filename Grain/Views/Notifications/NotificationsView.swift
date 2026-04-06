import NukeUI
import SwiftUI

struct NotificationsView: View {
    @Environment(AuthManager.self) private var auth
    var viewModel: NotificationsViewModel
    @State private var selectedGalleryUri: String?
    @State private var selectedProfileDid: String?
    @State private var cardStoryAuthor: GrainStoryAuthor?
    let client: XRPCClient

    init(client: XRPCClient, viewModel: NotificationsViewModel) {
        self.client = client
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.notifications) { notification in
                    NotificationRow(notification: notification, userDID: auth.userDID, onProfileTap: { did in
                        selectedProfileDid = did
                    }, onStoryTap: { author in
                        cardStoryAuthor = author
                    })
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if notification.reasonType == .follow {
                            selectedProfileDid = notification.author.did
                        } else if let galleryUri = notification.galleryUri {
                            selectedGalleryUri = galleryUri
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            selectedProfileDid = notification.author.did
                        } label: {
                            Label("Profile", systemImage: "person")
                        }
                    }
                    .onAppear {
                        if notification.id == viewModel.notifications.last?.id {
                            Task { await viewModel.loadMore(auth: auth.authContext()) }
                        }
                    }
                }

                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.loadInitial(auth: auth.authContext())
            }
            .navigationTitle("Notifications")
            .navigationDestination(item: $selectedGalleryUri) { uri in
                GalleryDetailView(client: client, galleryUri: uri)
            }
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
            .task(id: viewModel.unseenCount) {
                if viewModel.notifications.isEmpty || viewModel.unseenCount > 0 {
                    await viewModel.loadInitial(auth: auth.authContext())
                }
                await viewModel.markAsSeen(auth: auth.authContext())
            }
        }
    }
}

struct NotificationRow: View {
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @Environment(ViewedStoryStorage.self) private var viewedStories
    let notification: GrainNotification
    let userDID: String?
    var onProfileTap: ((String) -> Void)?
    var onStoryTap: ((GrainStoryAuthor) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StoryRingView(hasStory: storyStatusCache.hasStory(for: notification.author.did), viewed: notification.author.did != userDID && viewedStories.hasViewedAll(did: notification.author.did, storyStatusCache: storyStatusCache), size: 36) {
                AvatarView(url: notification.author.avatar, size: 36)
            }
            .onTapGesture {
                if let author = storyStatusCache.author(for: notification.author.did) {
                    onStoryTap?(author)
                } else {
                    onProfileTap?(notification.author.did)
                }
            }
            .onLongPressGesture {
                onProfileTap?(notification.author.did)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(Text(notification.author.displayName ?? notification.author.handle).font(.subheadline.bold())) \(Text(reasonText).font(.subheadline).foregroundStyle(.secondary))")

                if let galleryTitle = notification.galleryTitle {
                    Text(galleryTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let commentText = notification.commentText {
                    Text(commentText)
                        .font(.caption)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let thumb = notification.galleryThumb, let url = URL(string: thumb) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable()
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var reasonText: String {
        switch notification.reasonType {
        case .galleryFavorite: "favorited your gallery"
        case .galleryComment: "commented on your gallery"
        case .galleryCommentMention: "mentioned you in a comment"
        case .galleryMention: "mentioned you"
        case .reply: "replied to your comment"
        case .follow: "followed you"
        case .unknown: ""
        }
    }
}

#Preview {
    let client = XRPCClient(baseURL: AuthManager.serverURL)
    NotificationsView(
        client: client,
        viewModel: NotificationsViewModel(client: client)
    )
    .environment(AuthManager())
}

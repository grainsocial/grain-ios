import SwiftUI
import NukeUI

struct NotificationsView: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: NotificationsViewModel

    init(client: XRPCClient) {
        _viewModel = State(initialValue: NotificationsViewModel(client: client))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.notifications) { notification in
                    NotificationRow(notification: notification)
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
            .task {
                if viewModel.notifications.isEmpty {
                    await viewModel.loadInitial(auth: auth.authContext())
                }
            }
        }
    }
}

struct NotificationRow: View {
    let notification: GrainNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(url: notification.author.avatar, size: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(notification.author.displayName ?? notification.author.handle)
                        .font(.subheadline.bold())
                    Text(reasonText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

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

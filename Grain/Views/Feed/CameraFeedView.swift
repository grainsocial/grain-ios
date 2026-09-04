import SwiftUI

struct CameraFeedView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var galleries: [GrainGallery] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var isPinned = false
    @Environment(Router.self) private var router
    @State private var zoomState = ImageZoomState()
    @State private var modals = GalleryCardModals()

    let client: XRPCClient
    let camera: String

    private var feedId: String {
        "camera:\(camera)"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach($galleries) { $gallery in
                    galleryCard(gallery: $gallery)
                }

                if isLoading {
                    ProgressView()
                        .padding()
                }
            }
        }
        .gesture(
            // Rightward swipe outside the carousel pops the nav. Exclusive
            // .gesture so the child TabView in GalleryCardView claims swipes
            // on the image area first.
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let predicted = value.predictedEndTranslation.width
                    if dx > 80, abs(dy) < 60, predicted > 120 {
                        dismiss()
                    }
                }
        )
        .environment(zoomState)
        .modifier(ImageZoomOverlay(zoomState: zoomState))
        .navigationTitle(camera)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await togglePin() }
                    } label: {
                        Label(isPinned ? "Unpin feed" : "Pin feed",
                              systemImage: isPinned ? "pin.slash" : "pin")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                }
                .tint(.primary)
                .accessibilityLabel("More options")
            }
        }
        .task {
            guard !isPreview else { return }
            await checkPinned()
        }
        .galleryCardModals(
            client: client,
            modals: modals,
            onCommentCountChanged: { uri, count in
                if let idx = galleries.firstIndex(where: { $0.uri == uri }) {
                    galleries[idx].commentCount = count
                }
            },
            onDeleted: { uri in galleries.removeAll { $0.uri == uri } }
        )
        .task {
            guard !isPreview else {
                #if DEBUG
                    galleries = PreviewData.galleries
                #endif
                return
            }
            if galleries.isEmpty {
                await loadInitial()
            }
        }
    }

    @ViewBuilder
    private func galleryCard(gallery: Binding<GrainGallery>) -> some View {
        let item = gallery.wrappedValue
        let isOwner = item.creator.did == auth.userDID
        let reportAction: (() -> Void)? = !isOwner ? {
            modals.report = item
        } : nil
        let deleteAction: (() -> Void)? = isOwner ? {
            modals.confirmDelete(item.uri)
        } : nil
        GalleryCardView(gallery: gallery, client: client, onCommentTap: { modals.commentUri = item.uri }, onStoryTap: { author in modals.storyAuthor = author }, onReport: reportAction, onDelete: deleteAction)
            .onAppear {
                if item.id == galleries.last?.id {
                    Task { await loadMore() }
                }
            }
    }

    private func loadInitial() async {
        isLoading = true
        do {
            let response = try await client.getFeed(feed: "camera", camera: camera, auth: auth.authContext())
            galleries = response.items ?? []
            cursor = response.cursor
        } catch {}
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoading, let cursor else { return }
        isLoading = true
        do {
            let response = try await client.getFeed(feed: "camera", cursor: cursor, camera: camera, auth: auth.authContext())
            galleries.append(contentsOf: response.items ?? [])
            self.cursor = response.cursor
        } catch {}
        isLoading = false
    }

    private func checkPinned() async {
        do {
            let response = try await client.getPreferences(auth: auth.authContext())
            isPinned = response.preferences.pinnedFeeds?.contains(where: { $0.id == feedId }) ?? false
        } catch {}
    }

    private func togglePin() async {
        do {
            let response = try await client.getPreferences(auth: auth.authContext())
            var feeds = response.preferences.pinnedFeeds ?? PinnedFeed.defaults
            if isPinned {
                feeds.removeAll { $0.id == feedId }
            } else {
                feeds.append(PinnedFeed(id: feedId, label: camera, type: "camera", path: "/camera/\(camera)"))
            }
            try await client.putPinnedFeeds(feeds, auth: auth.authContext())
            isPinned.toggle()
        } catch {}
    }
}

#Preview {
    CameraFeedView(client: XRPCClient(baseURL: AuthManager.serverURL), camera: "Sony A7III")
        .environment(AuthManager())
        .environment(StoryStatusCache())
        .environment(ViewedStoryStorage())
        .environment(LabelDefinitionsCache())
}

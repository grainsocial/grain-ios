import SwiftUI

struct HashtagFeedView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var galleries: [GrainGallery] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var isPinned = false
    @State private var selectedUri: String?
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?
    @State private var selectedLocation: LocationDestination?
    @State private var zoomState = ImageZoomState()
    @State private var cardStoryAuthor: GrainStoryAuthor?
    @State private var commentSheetUri: String?
    @State private var reportGallery: GrainGallery?
    @State private var deleteGalleryUri: String?
    @State private var showDeleteConfirmation = false

    let client: XRPCClient
    let tag: String

    private var feedId: String {
        "hashtag:\(tag)"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array($galleries.enumerated()), id: \.element.id) { index, $gallery in
                    galleryCard(gallery: $gallery, index: index)
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
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await togglePin() }
                    } label: {
                        Label(isPinned ? "Unpin Feed" : "Pin Feed",
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
        .navigationDestination(item: $selectedUri) { uri in
            GalleryDetailView(client: client, galleryUri: uri)
        }
        .navigationDestination(item: $selectedProfileDid) { did in
            ProfileView(client: client, did: did)
        }
        .navigationDestination(item: $selectedHashtag) { tag in
            HashtagFeedView(client: client, tag: tag)
        }
        .navigationDestination(item: $selectedLocation) { loc in
            LocationFeedView(client: client, h3Index: loc.h3Index, locationName: loc.name)
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
        .sheet(isPresented: Binding(
            get: { commentSheetUri != nil },
            set: { if !$0 { commentSheetUri = nil } }
        )) {
            if let uri = commentSheetUri {
                CommentSheetView(
                    client: client,
                    galleryUri: uri,
                    onDismiss: { commentSheetUri = nil },
                    onProfileTap: { did in
                        commentSheetUri = nil
                        selectedProfileDid = did
                    },
                    onHashtagTap: { tag in
                        commentSheetUri = nil
                        selectedHashtag = tag
                    },
                    onStoryTap: { author in
                        commentSheetUri = nil
                        cardStoryAuthor = author
                    },
                    onCommentCountChanged: { count in
                        if let idx = galleries.firstIndex(where: { $0.uri == uri }) {
                            galleries[idx].commentCount = count
                        }
                    }
                )
            }
        }
        .sheet(item: $reportGallery) { gallery in
            ReportView(client: client, subjectUri: gallery.uri, subjectCid: gallery.cid)
        }
        .alert("Delete Gallery?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let uri = deleteGalleryUri {
                    Task {
                        guard let authContext = await auth.authContext() else { return }
                        let rkey = uri.split(separator: "/").last.map(String.init) ?? ""
                        try? await client.deleteRecord(collection: "social.grain.gallery", rkey: rkey, auth: authContext)
                        galleries.removeAll { $0.uri == uri }
                    }
                    deleteGalleryUri = nil
                }
            }
            Button("Cancel", role: .cancel) { deleteGalleryUri = nil }
        } message: {
            Text("This will permanently delete this gallery and all its photos.")
        }
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

    private func loadInitial() async {
        isLoading = true
        do {
            let response = try await client.getFeed(feed: "hashtag", tag: tag, auth: auth.authContext())
            galleries = response.items ?? []
            cursor = response.cursor
        } catch {}
        isLoading = false
    }

    @ViewBuilder
    private func galleryCard(gallery: Binding<GrainGallery>, index: Int) -> some View {
        let g = gallery.wrappedValue
        let isOwner = g.creator.did == auth.userDID
        GalleryCardView(
            gallery: gallery, client: client,
            onNavigate: { selectedUri = g.uri },
            onCommentTap: { commentSheetUri = g.uri },
            onProfileTap: { did in selectedProfileDid = did },
            onHashtagTap: { tag in selectedHashtag = tag },
            onLocationTap: { h3, name in selectedLocation = LocationDestination(h3Index: h3, name: name) },
            onStoryTap: { author in cardStoryAuthor = author },
            onReport: !isOwner ? { reportGallery = g } : nil,
            onDelete: isOwner ? { showDeleteConfirmation = true; deleteGalleryUri = g.uri } : nil
        )
        .onAppear {
            if index == galleries.count - 1 {
                Task { await loadMore() }
            }
        }
    }

    private func loadMore() async {
        guard !isLoading, let cursor else { return }
        isLoading = true
        do {
            let response = try await client.getFeed(feed: "hashtag", cursor: cursor, tag: tag, auth: auth.authContext())
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
                feeds.append(PinnedFeed(id: feedId, label: tag, type: "hashtag", path: "/hashtags/\(tag)"))
            }
            try await client.putPinnedFeeds(feeds, auth: auth.authContext())
            isPinned.toggle()
        } catch {}
    }
}

#Preview {
    HashtagFeedView(client: .preview, tag: "35mm")
        .previewEnvironments()
}

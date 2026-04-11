import SwiftUI

enum ProfileGalleryFeedSource: Hashable {
    case galleries
    case favorites
}

struct ProfileGallerySelection: Hashable {
    let uri: String
    let source: ProfileGalleryFeedSource
}

struct ProfileGalleryFeedView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ProfileDetailViewModel
    let client: XRPCClient
    let did: String
    let initialUri: String
    let source: ProfileGalleryFeedSource

    @State private var didExpand = false
    @State private var scrollAnchor: String?
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?
    @State private var selectedLocation: LocationDestination?
    @State private var zoomState = ImageZoomState()
    @State private var cardStoryAuthor: GrainStoryAuthor?
    @State private var commentSheetUri: String?
    @State private var reportGallery: GrainGallery?
    @State private var deleteGalleryUri: String?
    @State private var showDeleteConfirmation = false

    init(
        viewModel: ProfileDetailViewModel,
        client: XRPCClient,
        did: String,
        initialUri: String,
        source: ProfileGalleryFeedSource = .galleries
    ) {
        self.viewModel = viewModel
        self.client = client
        self.did = did
        self.initialUri = initialUri
        self.source = source
        _scrollAnchor = State(initialValue: initialUri)
    }

    private var items: [GrainGallery] {
        switch source {
        case .galleries: viewModel.galleries
        case .favorites: viewModel.favoriteGalleries
        }
    }

    private var itemsBinding: Binding<[GrainGallery]> {
        switch source {
        case .galleries: $viewModel.galleries
        case .favorites: $viewModel.favoriteGalleries
        }
    }

    private var hasMore: Bool {
        switch source {
        case .galleries: viewModel.hasMoreGalleries
        case .favorites: viewModel.hasMoreFavorites
        }
    }

    private var tappedIndex: Int {
        items.firstIndex(where: { $0.uri == initialUri }) ?? 0
    }

    private var renderStartIndex: Int {
        didExpand ? 0 : tappedIndex
    }

    private func loadMore() async {
        switch source {
        case .galleries:
            await viewModel.loadMoreGalleries(did: did, auth: auth.authContext())
        case .favorites:
            await viewModel.loadMoreFavorites(did: did, auth: auth.authContext())
        }
    }

    private func updateCommentCount(uri: String, count: Int) {
        switch source {
        case .galleries:
            if let idx = viewModel.galleries.firstIndex(where: { $0.uri == uri }) {
                viewModel.galleries[idx].commentCount = count
            }
        case .favorites:
            if let idx = viewModel.favoriteGalleries.firstIndex(where: { $0.uri == uri }) {
                viewModel.favoriteGalleries[idx].commentCount = count
            }
        }
    }

    private func removeAfterDelete(uri: String) {
        switch source {
        case .galleries:
            viewModel.galleries.removeAll { $0.uri == uri }
        case .favorites:
            viewModel.favoriteGalleries.removeAll { $0.uri == uri }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(itemsBinding.enumerated()), id: \.element.id) { index, $gallery in
                    if index >= renderStartIndex {
                        galleryCard(gallery: $gallery, index: index)
                            .id(gallery.uri)
                    }
                }

                if viewModel.isLoading, hasMore {
                    ProgressView()
                        .padding()
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollAnchor, anchor: .top)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.top, 24, for: .scrollContent)
        .gesture(
            // Rightward swipe anywhere outside the carousel pops the nav.
            // Using exclusive .gesture (not simultaneous) so the child TabView
            // in GalleryCardView claims swipes inside the image area first;
            // ours only fires for touches that miss the carousel.
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
        .navigationBarTitleDisplayMode(.inline)
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
                        updateCommentCount(uri: uri, count: count)
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
                        removeAfterDelete(uri: uri)
                    }
                    deleteGalleryUri = nil
                }
            }
            Button("Cancel", role: .cancel) { deleteGalleryUri = nil }
        } message: {
            Text("This will permanently delete this gallery and all its photos.")
        }
    }

    @ViewBuilder
    private func galleryCard(gallery: Binding<GrainGallery>, index: Int) -> some View {
        let g = gallery.wrappedValue
        let isOwner = g.creator.did == auth.userDID
        GalleryCardView(
            gallery: gallery, client: client,
            onNavigate: {},
            onCommentTap: { commentSheetUri = g.uri },
            onProfileTap: { did in selectedProfileDid = did },
            onHashtagTap: { tag in selectedHashtag = tag },
            onLocationTap: { h3, name in selectedLocation = LocationDestination(h3Index: h3, name: name) },
            onStoryTap: { author in cardStoryAuthor = author },
            onReport: !isOwner ? { reportGallery = g } : nil,
            onDelete: isOwner ? { showDeleteConfirmation = true; deleteGalleryUri = g.uri } : nil
        )
        .onAppear {
            if g.uri == initialUri, !didExpand {
                didExpand = true
            }
            if index == items.count - 1 {
                Task { await loadMore() }
            }
        }
    }
}

#Preview {
    ProfileGalleryFeedView(
        viewModel: {
            let vm = ProfileDetailViewModel(client: .preview)
            vm.galleries = PreviewData.galleries
            return vm
        }(),
        client: .preview,
        did: "did:plc:preview",
        initialUri: PreviewData.galleries.first?.uri ?? ""
    )
    .previewEnvironments()
}

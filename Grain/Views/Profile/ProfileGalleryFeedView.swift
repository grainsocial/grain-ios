import SwiftUI

struct ProfileGalleryFeedView: View {
    @Environment(AuthManager.self) private var auth
    @Bindable var viewModel: ProfileDetailViewModel
    let client: XRPCClient
    let did: String
    let initialUri: String

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

    init(viewModel: ProfileDetailViewModel, client: XRPCClient, did: String, initialUri: String) {
        self.viewModel = viewModel
        self.client = client
        self.did = did
        self.initialUri = initialUri
        _scrollAnchor = State(initialValue: initialUri)
    }

    private var tappedIndex: Int {
        viewModel.galleries.firstIndex(where: { $0.uri == initialUri }) ?? 0
    }

    private var renderStartIndex: Int {
        didExpand ? 0 : tappedIndex
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array($viewModel.galleries.enumerated()), id: \.element.id) { index, $gallery in
                    if index >= renderStartIndex {
                        galleryCard(gallery: $gallery, index: index)
                            .id(gallery.uri)
                    }
                }

                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollAnchor, anchor: .top)
        .contentMargins(.top, 16, for: .scrollContent)
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
                        if let idx = viewModel.galleries.firstIndex(where: { $0.uri == uri }) {
                            viewModel.galleries[idx].commentCount = count
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
                        viewModel.galleries.removeAll { $0.uri == uri }
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
            if index == viewModel.galleries.count - 1 {
                Task { await viewModel.loadMoreGalleries(did: did, auth: auth.authContext()) }
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

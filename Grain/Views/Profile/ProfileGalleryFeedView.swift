import SwiftUI

enum ProfileGalleryFeedSource: Hashable {
    case galleries
    case favorites
}

struct ProfileGallerySelection: Hashable {
    let uri: String
    let source: ProfileGalleryFeedSource
}

/// Owns the reads of `isLoading` / `hasMore` so they don't land in the body
/// holding the `LazyVStack`. Reading them up there made every page fetch
/// re-evaluate every instantiated card body — the same problem measured in the
/// main feed, where scoping it this way halved body evaluations per card.
struct ProfileFeedLoadingFooter: View {
    let viewModel: ProfileDetailViewModel
    let source: ProfileGalleryFeedSource

    private var hasMore: Bool {
        switch source {
        case .galleries: viewModel.hasMoreGalleries
        case .favorites: viewModel.hasMoreFavorites
        }
    }

    var body: some View {
        if viewModel.isLoading, hasMore {
            ProgressView()
                .padding()
        }
    }
}

struct ProfileGalleryFeedView: View {
    @Environment(AuthManager.self) private var auth
    @Bindable var viewModel: ProfileDetailViewModel
    let client: XRPCClient
    let did: String
    let initialUri: String
    let source: ProfileGalleryFeedSource

    @State private var didScroll = false
    @Environment(Router.self) private var router
    @State private var zoomState = ImageZoomState()
    @State private var modals = GalleryCardModals()

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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(itemsBinding.enumerated()), id: \.element.id) { index, $gallery in
                        galleryCard(gallery: $gallery, index: index)
                            .id(gallery.uri)
                    }

                    ProfileFeedLoadingFooter(viewModel: viewModel, source: source)
                }
            }
            .opacity(didScroll ? 1 : 0)
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(initialUri, anchor: .top)
                    didScroll = true
                }
            }
            .environment(zoomState)
            .modifier(ImageZoomOverlay(zoomState: zoomState))
            .navigationBarTitleDisplayMode(.inline)
            .galleryCardModals(
                client: client,
                modals: modals,
                onCommentCountChanged: { uri, count in updateCommentCount(uri: uri, count: count) },
                onDeleted: { uri in removeAfterDelete(uri: uri) }
            )
        } // ScrollViewReader
    }

    @ViewBuilder
    private func galleryCard(gallery: Binding<GrainGallery>, index: Int) -> some View {
        let item = gallery.wrappedValue
        let isOwner = item.creator.did == auth.userDID
        GalleryCardView(gallery: gallery, client: client, onCommentTap: { modals.commentUri = item.uri }, onStoryTap: { author in modals.storyAuthor = author }, onReport: !isOwner ? { modals.report = item } : nil, onDelete: isOwner ? { modals.confirmDelete(item.uri) } : nil)
            .onAppear {
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

import MapKit
import SwiftUI

struct LocationFeedView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var galleries: [GrainGallery] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var isPinned = false
    @Environment(Router.self) private var router
    @State private var zoomState = ImageZoomState()
    @State private var modals = GalleryCardModals()
    @State private var mapInteractive = false

    let client: XRPCClient
    let h3Index: String
    let locationName: String

    private var feedId: String {
        "location:\(h3Index)"
    }

    private var coordinate: CLLocationCoordinate2D? {
        LocationServices.h3ToCoordinate(h3Index)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let coord = coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coord,
                        latitudinalMeters: 20000,
                        longitudinalMeters: 20000
                    )))
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .mapControlVisibility(mapInteractive ? .automatic : .hidden)
                    .frame(height: mapInteractive ? 300 : 150)
                    .overlay {
                        if !mapInteractive {
                            Color.clear
                                .contentShape(Rectangle())
                                .accessibilityLabel("Expand map")
                                .accessibilityAddTraits(.isButton)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.25)) { mapInteractive = true }
                                }
                        }
                    }
                    .mask(
                        LinearGradient(
                            colors: mapInteractive ? [.black] : [.black, .black, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                ForEach($galleries) { $gallery in
                    let isOwner = gallery.creator.did == auth.userDID
                    let reportAction: (() -> Void)? = !isOwner ? {
                        modals.report = gallery
                    } : nil
                    let deleteAction: (() -> Void)? = isOwner ? {
                        modals.confirmDelete(gallery.uri)
                    } : nil
                    GalleryCardView(gallery: $gallery, client: client, onCommentTap: {
                        modals.commentUri = gallery.uri
                    }, onStoryTap: { author in
                        modals.storyAuthor = author
                    }, onReport: reportAction, onDelete: deleteAction, showsLocationLink: false)
                        .onAppear {
                            if gallery.id == galleries.last?.id {
                                Task { await loadMore() }
                            }
                        }
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
        .navigationTitle(locationName)
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

    private func loadInitial() async {
        isLoading = true
        do {
            let response = try await client.getFeed(feed: "location", location: h3Index, auth: auth.authContext())
            galleries = response.items ?? []
            cursor = response.cursor
        } catch {}
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoading, let cursor else { return }
        isLoading = true
        do {
            let response = try await client.getFeed(feed: "location", cursor: cursor, location: h3Index, auth: auth.authContext())
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
                feeds.append(PinnedFeed(id: feedId, label: locationName, type: "location", path: "/location/\(h3Index)"))
            }
            try await client.putPinnedFeeds(feeds, auth: auth.authContext())
            isPinned.toggle()
        } catch {}
    }
}

struct LocationDestination: Hashable, Identifiable {
    let h3Index: String
    let name: String
    var id: String {
        h3Index
    }
}

#Preview {
    LocationFeedView(
        client: .preview,
        h3Index: "8928308280fffff",
        locationName: "San Francisco"
    )
    .previewEnvironments()
}

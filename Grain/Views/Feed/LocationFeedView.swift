import MapKit
import SwiftUI

struct LocationFeedView: View {
    @Environment(AuthManager.self) private var auth
    @State private var galleries: [GrainGallery] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var isPinned = false
    @State private var selectedUri: String?
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?
    @State private var zoomState = ImageZoomState()
    @State private var cardStoryAuthor: GrainStoryAuthor?
    @State private var commentSheetUri: String?
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
                    GalleryCardView(gallery: $gallery, client: client, onNavigate: {
                        selectedUri = gallery.uri
                    }, onCommentTap: {
                        commentSheetUri = gallery.uri
                    }, onProfileTap: { did in
                        selectedProfileDid = did
                    }, onHashtagTap: { tag in
                        selectedHashtag = tag
                    }, onStoryTap: { author in
                        cardStoryAuthor = author
                    })
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
                        Label(isPinned ? "Unpin Feed" : "Pin Feed",
                              systemImage: isPinned ? "pin.slash" : "pin")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                }
                .tint(.primary)
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
        client: XRPCClient(baseURL: AuthManager.serverURL),
        h3Index: "8928308280fffff",
        locationName: "San Francisco"
    )
    .environment(AuthManager())
    .environment(StoryStatusCache())
    .environment(ViewedStoryStorage())
    .environment(LabelDefinitionsCache())
}

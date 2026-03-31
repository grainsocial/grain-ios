import SwiftUI

struct HashtagFeedView: View {
    @Environment(AuthManager.self) private var auth
    @State private var galleries: [GrainGallery] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var selectedUri: String?
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?

    let client: XRPCClient
    let tag: String

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach($galleries) { $gallery in
                    GalleryCardView(gallery: $gallery, client: client, onNavigate: {
                        selectedUri = gallery.uri
                    }, onProfileTap: { did in
                        selectedProfileDid = did
                    }, onHashtagTap: { tag in
                        selectedHashtag = tag
                    })
                    .onAppear {
                        if gallery.id == galleries.last?.id {
                            Task { await loadMore() }
                        }
                    }

                    Divider()
                }

                if isLoading {
                    ProgressView()
                        .padding()
                }
            }
        }
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedUri) { uri in
            GalleryDetailView(client: client, galleryUri: uri)
        }
        .navigationDestination(item: $selectedProfileDid) { did in
            ProfileView(client: client, did: did)
        }
        .navigationDestination(item: $selectedHashtag) { tag in
            HashtagFeedView(client: client, tag: tag)
        }
        .task {
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
}

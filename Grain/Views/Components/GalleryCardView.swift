import SwiftUI
import NukeUI
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "GalleryCard")

struct GalleryCardView: View {
    @Environment(AuthManager.self) private var auth
    @Binding var gallery: GrainGallery
    let client: XRPCClient
    var onNavigate: () -> Void = {}
    @State private var isFavoriting = false
    @State private var currentPage = 0
    @State private var showingAlt = false

    private var isFavorited: Bool {
        gallery.viewer?.fav != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — tappable for navigation
            HStack(spacing: 8) {
                AvatarView(url: gallery.creator.avatar, size: 32)

                VStack(alignment: .leading, spacing: 0) {
                    Text(gallery.creator.displayName ?? gallery.creator.handle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("@\(gallery.creator.handle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { onNavigate() }

            // Photo carousel — tappable for navigation
            if let photos = gallery.items, !photos.isEmpty {
                ZStack(alignment: .bottom) {
                    TabView(selection: $currentPage) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            LazyImage(url: URL(string: photo.fullsize)) { state in
                                if let image = state.image {
                                    image
                                        .resizable()
                                        .aspectRatio(photo.aspectRatio.ratio, contentMode: .fit)
                                } else {
                                    Rectangle()
                                        .fill(.quaternary)
                                        .aspectRatio(photo.aspectRatio.ratio, contentMode: .fit)
                                }
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .aspectRatio(photos[currentPage].aspectRatio.ratio, contentMode: .fit)

                    // Page indicator
                    if photos.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(0..<photos.count, id: \.self) { index in
                                Circle()
                                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.5))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // Alt text overlay — centered, tap to dismiss
                    if showingAlt, let alt = photos[currentPage].alt, !alt.isEmpty {
                        Color.black.opacity(0.6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingAlt = false
                                }
                            }
                        Text(alt)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    }

                    // ALT button — bottom right
                    if let alt = photos[currentPage].alt, !alt.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showingAlt.toggle()
                                    }
                                } label: {
                                    Text("ALT")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(8)
                        }
                    }
                }
                .onChange(of: currentPage) { showingAlt = false }
            }

            // Engagement row
            HStack(spacing: 16) {
                Button {
                    guard !isFavoriting else { return }
                    isFavoriting = true
                    Task {
                        await toggleFavorite()
                        isFavoriting = false
                    }
                } label: {
                    Label(
                        "\(gallery.favCount ?? 0)",
                        systemImage: isFavorited ? "heart.fill" : "heart"
                    )
                    .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(isFavorited ? .red : .secondary)

                Label("\(gallery.commentCount ?? 0)", systemImage: "bubble.right")
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Title & description — tappable for navigation
            VStack(alignment: .leading, spacing: 2) {
                Text(gallery.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if let description = gallery.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .onTapGesture { onNavigate() }
        }
    }

    private func toggleFavorite() async {
        guard let authContext = auth.authContext() else {
            logger.error("No auth context")
            return
        }
        if let favUri = gallery.viewer?.fav {
            gallery.viewer?.fav = nil
            gallery.favCount = max((gallery.favCount ?? 1) - 1, 0)

            let rkey = favUri.split(separator: "/").last.map(String.init) ?? ""
            do {
                try await client.deleteRecord(collection: "social.grain.favorite", rkey: rkey, auth: authContext)
            } catch {
                logger.error("Unfavorite failed: \(error)")
                gallery.viewer?.fav = favUri
                gallery.favCount = (gallery.favCount ?? 0) + 1
            }
        } else {
            let prevViewer = gallery.viewer
            let prevCount = gallery.favCount
            gallery.viewer = GalleryViewerState(fav: "pending")
            gallery.favCount = (gallery.favCount ?? 0) + 1

            let record = AnyCodable([
                "subject": gallery.uri,
                "createdAt": ISO8601DateFormatter().string(from: Date()),
            ])
            let repo = TokenStorage.userDID ?? ""
            do {
                let response = try await client.createRecord(collection: "social.grain.favorite", repo: repo, record: record, auth: authContext)
                gallery.viewer = GalleryViewerState(fav: response.uri)
            } catch {
                logger.error("Favorite failed: \(error)")
                gallery.viewer = prevViewer
                gallery.favCount = prevCount
            }
        }
    }
}

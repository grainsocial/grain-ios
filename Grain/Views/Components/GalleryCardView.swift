import NukeUI
import os
import SwiftUI

private let logger = Logger(subsystem: "social.grain.grain", category: "GalleryCard")

struct GalleryCardView: View {
    @Environment(AuthManager.self) private var auth
    @Binding var gallery: GrainGallery
    let client: XRPCClient
    var onNavigate: () -> Void = {}
    var onProfileTap: ((String) -> Void)?
    var onHashtagTap: ((String) -> Void)?
    @State private var isFavoriting = false
    @State private var currentPage = 0
    @State private var showingAlt = false
    @State private var isZoomed = false
    @State private var showZoomOverlay = false
    @State private var zoomScale: CGFloat = 1
    @State private var zoomAnchor: UnitPoint = .center
    @State private var zoomOffset: CGSize = .zero

    private var isFavorited: Bool {
        gallery.viewer?.fav != nil
    }

    private var galleryShareURL: URL {
        let rkey = gallery.uri.split(separator: "/").last.map(String.init) ?? ""
        return URL(string: "https://grain.social/profile/\(gallery.creator.did)/gallery/\(rkey)") ?? URL(string: "https://grain.social")!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — tappable for navigation
            HStack(spacing: 8) {
                AvatarView(url: gallery.creator.avatar, size: 32)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(gallery.creator.displayName ?? gallery.creator.handle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("@\(gallery.creator.handle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("· \(DateFormatting.relativeTime(gallery.createdAt ?? gallery.indexedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    if let locationName = gallery.location?.name ?? gallery.address?.locality {
                        Text(locationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { onProfileTap?(gallery.creator.did) }

            // Photo carousel — tappable for navigation
            if let photos = gallery.items, !photos.isEmpty {
                let hasPortrait = photos.contains { $0.aspectRatio.ratio < 1 }
                let hasMixedRatios = Set(photos.map { Int($0.aspectRatio.ratio * 100) }).count > 1
                let carouselRatio = hasMixedRatios
                    ? max(photos.map(\.aspectRatio.ratio).min() ?? 1, 0.56)
                    : photos[currentPage].aspectRatio.ratio

                GeometryReader { geo in
                    let height = geo.size.width / carouselRatio

                    ZStack(alignment: .bottom) {
                        TabView(selection: $currentPage) {
                            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                                ZoomableImage(
                                    url: photo.fullsize,
                                    aspectRatio: photo.aspectRatio.ratio,
                                    isZoomed: $isZoomed,
                                    showOverlay: $showZoomOverlay,
                                    zoomScale: $zoomScale,
                                    zoomAnchor: $zoomAnchor,
                                    zoomOffset: $zoomOffset
                                )
                                .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))

                    // Page indicator (abbreviated like web — max 5 visible dots)
                    if photos.count > 1 {
                        HStack(spacing: 5) {
                            let total = photos.count
                            let maxVisible = 5
                            let start = total <= maxVisible ? 0 : min(max(currentPage - 2, 0), total - maxVisible)
                            let end = total <= maxVisible ? total : start + maxVisible

                            ForEach(start..<end, id: \.self) { index in
                                let distance = abs(index - currentPage)
                                let currentIsLandscape = photos[currentPage].aspectRatio.ratio >= 1
                                let dotColor: Color = hasPortrait && currentIsLandscape ? .secondary : .white
                                Circle()
                                    .fill(dotColor.opacity(index == currentPage ? 1.0 : distance == 1 ? 0.5 : distance == 2 ? 0.3 : 0.2))
                                    .frame(
                                        width: distance <= 1 ? 6 : distance == 2 ? 4 : 3,
                                        height: distance <= 1 ? 6 : distance == 2 ? 4 : 3
                                    )
                                    .animation(.easeInOut(duration: 0.2), value: currentPage)
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
                    .frame(height: height)
                }
                .aspectRatio(carouselRatio, contentMode: .fit)
                .zIndex(isZoomed ? 1 : 0)
                .onChange(of: currentPage) {
                    showingAlt = false
                    isZoomed = false
                }
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
                    HStack(spacing: 5) {
                        Image(systemName: isFavorited ? "heart.fill" : "heart")
                            .font(.system(size: 22))
                        Text("\(gallery.favCount ?? 0)")
                    }
                }
                .foregroundStyle(isFavorited ? Color(red: 0.973, green: 0.443, blue: 0.443) : .secondary)

                Button {
                    onNavigate()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 20))
                        Text("\(gallery.commentCount ?? 0)")
                    }
                }
                .foregroundStyle(.secondary)

                ShareLink(item: galleryShareURL) {
                    Image(systemName: "paperplane")
                        .font(.system(size: 20))
                }
                .foregroundStyle(.secondary)

                Spacer()
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // EXIF info
            if let photos = gallery.items, !photos.isEmpty,
               let exif = photos[currentPage].exif,
               exif.hasDisplayableData {
                ExifInfoView(exif: exif)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            // Title & description
            VStack(alignment: .leading, spacing: 4) {
                Text(gallery.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture { onNavigate() }

                if let description = gallery.description, !description.isEmpty {
                    ExpandableDescriptionView(
                        text: description,
                        onMentionTap: onProfileTap,
                        onHashtagTap: onHashtagTap
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .overlay {
            if showZoomOverlay, let photos = gallery.items, photos.indices.contains(currentPage) {
                let photo = photos[currentPage]
                GeometryReader { geo in
                    LazyImage(url: URL(string: photo.fullsize)) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(photo.aspectRatio.ratio, contentMode: .fit)
                        }
                    }
                    .frame(width: geo.size.width)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .scaleEffect(zoomScale, anchor: zoomAnchor)
                    .offset(zoomOffset)
                }
                .allowsHitTesting(false)
            }
        }
        .onChange(of: isZoomed) {
            if isZoomed {
                showZoomOverlay = true
            }
        }
        .zIndex(showZoomOverlay ? 1 : 0)
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
                "createdAt": DateFormatting.nowISO(),
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

import Nuke
import os
import SwiftUI

private let logger = Logger(subsystem: "social.grain.grain", category: "GalleryCard")

// MARK: - Self-animating heart with heap-backed state

@Observable
@MainActor
final class HeartAnimationState: Identifiable {
    let id = UUID()
    let position: CGPoint
    let rotation: Double
    var heartScale: CGFloat = 0
    var ripple1Scale: CGFloat = 0.3
    var ripple1Opacity: Double = 0
    var ripple2Scale: CGFloat = 0.3
    var ripple2Opacity: Double = 0
    var ripple3Scale: CGFloat = 0.3
    var ripple3Opacity: Double = 0
    var isComplete = false

    init(position: CGPoint) {
        self.position = position
        rotation = Double.random(in: -20 ... 20)
    }

    func start() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            heartScale = 1
        }

        ripple1Opacity = 0.6
        withAnimation(.easeOut(duration: 0.35)) { ripple1Scale = 1.5 }
        withAnimation(.easeIn(duration: 0.3).delay(0.2)) { ripple1Opacity = 0 }

        ripple2Opacity = 0.4
        withAnimation(.easeOut(duration: 0.4).delay(0.05)) { ripple2Scale = 2.0 }
        withAnimation(.easeIn(duration: 0.3).delay(0.25)) { ripple2Opacity = 0 }

        ripple3Opacity = 0.25
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) { ripple3Scale = 2.6 }
        withAnimation(.easeIn(duration: 0.35).delay(0.3)) { ripple3Opacity = 0 }

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeInOut(duration: 0.2)) { heartScale = 1.6 }
            try? await Task.sleep(for: .milliseconds(400))
            isComplete = true
        }
    }
}

struct DoubleTapHeartView: View {
    let state: HeartAnimationState

    var body: some View {
        ZStack {
            Image(systemName: "heart")
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(Color.heart)
                .scaleEffect(state.ripple3Scale)
                .opacity(state.ripple3Opacity)
                .rotationEffect(.degrees(state.rotation * 0.6))

            Image(systemName: "heart")
                .font(.system(size: 80, weight: .ultraLight))
                .foregroundStyle(Color.heart)
                .scaleEffect(state.ripple2Scale)
                .opacity(state.ripple2Opacity)
                .rotationEffect(.degrees(state.rotation * 0.8))

            Image(systemName: "heart")
                .font(.system(size: 80, weight: .thin))
                .foregroundStyle(Color.heart)
                .scaleEffect(state.ripple1Scale)
                .opacity(state.ripple1Opacity)
                .rotationEffect(.degrees(state.rotation * 0.9))

            Image(systemName: "heart.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.heart)
                .shadow(color: .pink.opacity(0.4), radius: 12)
                .scaleEffect(state.heartScale)
                .opacity(state.heartScale > 1.2 ? 0 : 1)
                .rotationEffect(.degrees(state.rotation))
        }
        .position(x: state.position.x, y: state.position.y)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { state.start() }
    }
}

// MARK: - Subtle like-button particle burst

struct LikeParticleView: View {
    let index: Int

    /// Deterministic per slot — no random state stored in parent
    private static let configs: [(x: CGFloat, y: CGFloat, scale: CGFloat)] = [
        (x: -15, y: -30, scale: 0.85),
        (x: -4, y: -38, scale: 1.00),
        (x: 7, y: -32, scale: 0.90),
        (x: 17, y: -26, scale: 0.80),
        (x: 2, y: -43, scale: 0.95),
    ]

    @State private var scale: CGFloat = 0.3
    @State private var offset: CGSize = .zero
    @State private var opacity: Double = 0.9

    var body: some View {
        let cfg = Self.configs[index]
        Image(systemName: "heart.fill")
            .font(.system(size: 10))
            .foregroundStyle(Color.heart.opacity(0.9))
            .scaleEffect(scale)
            .offset(offset)
            .opacity(opacity)
            .onAppear {
                let delay = Double(index) * 0.07
                withAnimation(.easeOut(duration: 0.55).delay(delay)) {
                    scale = cfg.scale
                    offset = CGSize(width: cfg.x, height: cfg.y)
                }
                withAnimation(.easeIn(duration: 0.38).delay(delay + 0.32)) {
                    opacity = 0
                }
            }
    }
}

private struct PageIndicatorView: View {
    let photos: [GrainPhoto]
    let currentPage: Int
    let hasPortrait: Bool

    var body: some View {
        if photos.count > 1 {
            HStack(spacing: 5) {
                let total = photos.count
                let maxVisible = 5
                let start = total <= maxVisible ? 0 : min(max(currentPage - 2, 0), total - maxVisible)
                let end = total <= maxVisible ? total : start + maxVisible

                ForEach(start ..< end, id: \.self) { index in
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
    }
}

private struct CopiedToastView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.doc.fill")
                .font(.caption)
            Text("Link copied")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .transition(.scale.combined(with: .opacity))
    }
}

private extension View {
    /// Overlays a "Link copied" toast and drives its entrance/exit animation.
    /// Bundles the overlay and animation so they can't be accidentally separated.
    func copiedToast(isShowing: Bool) -> some View {
        overlay { if isShowing { CopiedToastView() } }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isShowing)
    }
}

struct GalleryCardView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @Environment(ViewedStoryStorage.self) private var viewedStories
    @Environment(LabelDefinitionsCache.self) private var labelDefsCache
    @Binding var gallery: GrainGallery
    let client: XRPCClient
    var onNavigate: () -> Void = {}
    var onCommentTap: (() -> Void)?
    var onProfileTap: ((String) -> Void)?
    var onHashtagTap: ((String) -> Void)?
    var onLocationTap: ((String, String) -> Void)?
    var onStoryTap: ((GrainStoryAuthor) -> Void)?
    var onReport: (() -> Void)?
    var onDelete: (() -> Void)?
    @State private var isFavoriting = false
    @State private var showCardActions = false
    @State private var likeParticleBursts: [UUID] = []
    @State private var currentPage = 0
    @State private var showingAlt = false
    @State private var hearts: [HeartAnimationState] = []
    @State private var showCopiedToast = false
    @State private var shareAnimating = false
    @State private var prefetcher = ImagePrefetcher()

    private var isFavorited: Bool {
        gallery.viewer?.fav != nil
    }

    private var labelResult: LabelResolution {
        resolveLabels(gallery.labels, definitions: labelDefsCache.definitions)
    }

    private var galleryShareURL: URL {
        let rkey = gallery.uri.split(separator: "/").last.map(String.init) ?? ""
        return URL(string: "https://grain.social/profile/\(gallery.creator.did)/gallery/\(rkey)") ?? URL(string: "https://grain.social")!
    }

    var body: some View {
        let lr = labelResult
        if lr.action == .hide || lr.action == .warnContent, !gallery.labelRevealed {
            VStack(spacing: 0) {
                ContentWarningOverlay(name: lr.name, action: lr.action) {
                    gallery.labelRevealed = true
                }
                .frame(height: 200)
            }
        } else {
            cardContent(lr: lr)
        }
    }

    private func cardContent(lr: LabelResolution) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            if let photos = gallery.items, !photos.isEmpty {
                photoCarousel(photos: photos, lr: lr)
            }
            engagementRow
            captionSection(lr: lr)
        }
        .copiedToast(isShowing: showCopiedToast)
    }

    private var cardHeader: some View {
        HStack(spacing: 8) {
            let hasStory = storyStatusCache.hasStory(for: gallery.creator.did)
            let allViewed = gallery.creator.did != auth.userDID && viewedStories.hasViewedAll(did: gallery.creator.did, storyStatusCache: storyStatusCache)
            StoryRingView(hasStory: hasStory, viewed: allViewed, size: 32) {
                AvatarView(url: gallery.creator.avatar, size: 32)
            }
            .onTapGesture {
                if let author = storyStatusCache.author(for: gallery.creator.did) {
                    onStoryTap?(author)
                } else {
                    onProfileTap?(gallery.creator.did)
                }
            }
            .onLongPressGesture {
                onProfileTap?(gallery.creator.did)
            }

            VStack(alignment: .leading, spacing: 3) {
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
                if let location = gallery.location, let locationName = location.name ?? gallery.address?.locality {
                    Text(locationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .onTapGesture {
                            onLocationTap?(location.value, locationName)
                        }
                }
            }

            Spacer()

            if onReport != nil || onDelete != nil {
                Button { showCardActions = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options")
                .highPriorityGesture(TapGesture().onEnded { showCardActions = true })
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onProfileTap?(gallery.creator.did) }
        .sheet(isPresented: $showCardActions) {
            GalleryActionsSheet(onReport: onReport, onDelete: onDelete)
                .presentationDetents([.height(200)])
        }
    }

    @ViewBuilder
    private func photoCarousel(photos: [GrainPhoto], lr: LabelResolution) -> some View {
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
                        ZStack {
                            ZoomableImage(
                                url: photo.fullsize,
                                thumbURL: photo.thumb,
                                aspectRatio: photo.aspectRatio.ratio,
                                onDoubleTap: { point in doubleTapLike(at: point) }
                            )

                            // Alt text overlay — always in the tree so opacity
                            // animates smoothly (conditional `if` inside TabView
                            // swallows transitions).
                            if let alt = photo.alt, !alt.isEmpty {
                                ZStack {
                                    Color.black.opacity(0.6)
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.2)) { showingAlt = false }
                                        }
                                    GeometryReader { geo in
                                        ScrollView {
                                            Text(alt)
                                                .font(.subheadline)
                                                .foregroundStyle(.white)
                                                .multilineTextAlignment(.center)
                                                .padding(20)
                                                .frame(maxWidth: .infinity)
                                                .frame(minHeight: geo.size.height)
                                        }
                                        .scrollBounceBehavior(.basedOnSize)
                                    }
                                }
                                .opacity(showingAlt && currentPage == index ? 1 : 0)
                                .allowsHitTesting(showingAlt && currentPage == index)
                                .animation(.easeInOut(duration: 0.2), value: showingAlt && currentPage == index)
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .overlay {
                    if lr.action == .warnMedia, !gallery.labelRevealed {
                        Rectangle().fill(Color(.secondarySystemBackground))
                    }
                }
                .allowsHitTesting(lr.action != .warnMedia || gallery.labelRevealed)

                PageIndicatorView(photos: photos, currentPage: currentPage, hasPortrait: hasPortrait)
                altButton(photos: photos)

                // Double-tap heart animations
                ForEach(hearts) { heart in
                    DoubleTapHeartView(state: heart)
                        .onChange(of: heart.isComplete) {
                            hearts.removeAll { $0.isComplete }
                        }
                }

                // Media warning overlay
                if lr.action == .warnMedia, !gallery.labelRevealed {
                    MediaWarningOverlay(name: lr.name) {
                        withAnimation { gallery.labelRevealed = true }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                let photo = currentPage < photos.count ? photos[currentPage] : nil
                if let alt = photo?.alt, !alt.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) { showingAlt.toggle() }
                }
            }
            .frame(height: height)
        }
        .aspectRatio(carouselRatio, contentMode: .fit)
        .onAppear {
            prefetchCarousel(photos: photos, page: 0)
        }
        .onChange(of: currentPage) {
            withAnimation(.easeInOut(duration: 0.2)) { showingAlt = false }
            prefetchCarousel(photos: photos, page: currentPage)
        }
        .onDisappear {
            prefetcher.stopPrefetching()
        }
    }

    @ViewBuilder
    private func altButton(photos: [GrainPhoto]) -> some View {
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
                    .accessibilityLabel(showingAlt ? "Hide alt text" : "Show alt text")
                }
                .padding(8)
            }
        }
    }

    private var engagementRow: some View {
        HStack(spacing: 16) {
            Button {
                guard !isFavoriting else { return }
                if !isFavorited { addParticleBurst() }
                triggerFavoriteToggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .contentTransition(.symbolEffect(.replace.downUp.byLayer, options: .nonRepeating))
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFavorited)
                    ZStack {
                        let count = gallery.favCount ?? 0
                        Text(count.compactCount.digitWidthProxy)
                            .hidden()
                        Text(count.compactCount)
                    }
                }
            }
            .foregroundStyle(isFavorited ? AnyShapeStyle(Color.heart) : AnyShapeStyle(.secondary))
            .accessibilityLabel(isFavorited ? "Unlike" : "Like")
            .accessibilityValue("\(gallery.favCount ?? 0) likes")
            .overlay(alignment: .leading) {
                ZStack {
                    ForEach(likeParticleBursts, id: \.self) { _ in
                        ForEach(0 ..< 5, id: \.self) { i in
                            LikeParticleView(index: i)
                        }
                    }
                }
                .offset(x: 11)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            Button {
                (onCommentTap ?? onNavigate)()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble")
                        .font(.system(size: 20))
                    Text((gallery.commentCount ?? 0).compactCount)
                }
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Comments")
            .accessibilityValue("\(gallery.commentCount ?? 0)")

            ShareLink(item: galleryShareURL) {
                Image(systemName: "paperplane")
                    .font(.system(size: 20))
                    .rotationEffect(.degrees(shareAnimating ? -15 : 0))
                    .animation(
                        shareAnimating
                            ? .easeInOut(duration: 0.08).repeatCount(5, autoreverses: true)
                            : .default,
                        value: shareAnimating
                    )
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Share gallery")
            .disabled(shareAnimating)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        UIPasteboard.general.url = galleryShareURL
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        shareAnimating = true
                        showCopiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            shareAnimating = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showCopiedToast = false
                        }
                    }
            )

            Spacer()
        }
        .font(.subheadline)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: gallery.favCount)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func captionSection(lr: LabelResolution) -> some View {
        // EXIF info — collapses when the current photo has no metadata,
        // expands smoothly when swiping to a photo that does.
        let allPhotos = gallery.items ?? []
        if allPhotos.contains(where: { $0.exif?.hasDisplayableData ?? false }) {
            let currentExif = allPhotos.indices.contains(currentPage)
                ? allPhotos[currentPage].exif : nil
            let hasCurrentExif = currentExif?.hasDisplayableData ?? false
            ExifInfoView(
                exif: currentExif?.displayData,
                reserveCameraRow: allPhotos.contains(where: { $0.exif?.cameraName != nil }),
                reserveLensRow: allPhotos.contains(where: { $0.exif?.lensName != nil })
            )
            .transaction { $0.animation = nil }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .frame(maxHeight: hasCurrentExif ? nil : 0, alignment: .top)
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: hasCurrentExif)
        }

        // Title & description
        VStack(alignment: .leading, spacing: 4) {
            Text(gallery.title ?? "")
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)

            if let description = gallery.description, !description.isEmpty {
                ExpandableDescriptionView(
                    text: description,
                    onMentionTap: onProfileTap,
                    onHashtagTap: onHashtagTap
                )
            }

            if lr.action == .badge {
                LabelBadge(name: lr.name)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func addParticleBurst() {
        let id = UUID()
        likeParticleBursts.append(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            likeParticleBursts.removeAll { $0 == id }
        }
    }

    private func prefetchCarousel(photos: [GrainPhoto], page: Int) {
        let input = photos.map { (thumb: $0.thumb, fullsize: $0.fullsize) }
        let plan = ImagePrefetchPlanning.carouselPrefetchRequests(photos: input, currentPage: page)
        prefetcher.startPrefetching(with: plan.all)
    }

    private func doubleTapLike(at point: CGPoint) {
        hearts.append(HeartAnimationState(position: point))
        addParticleBurst()
        guard !isFavorited, !isFavoriting else { return }
        triggerFavoriteToggle()
    }

    private func triggerFavoriteToggle() {
        isFavoriting = true
        Task {
            await toggleFavorite()
            isFavoriting = false
        }
    }

    private func toggleFavorite() async {
        guard let authContext = await auth.authContext() else {
            logger.error("No auth context")
            return
        }
        if let favUri = gallery.viewer?.fav {
            gallery.viewer?.fav = nil
            gallery.favCount = max((gallery.favCount ?? 1) - 1, 0)
            do {
                try await FavoriteService.delete(favoriteUri: favUri, client: client, auth: authContext)
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
            do {
                let response = try await FavoriteService.create(subject: gallery.uri, client: client, auth: authContext)
                gallery.viewer = GalleryViewerState(fav: response.uri)
            } catch {
                logger.error("Favorite failed: \(error)")
                gallery.viewer = prevViewer
                gallery.favCount = prevCount
            }
        }
    }
}

#Preview {
    @Previewable @State var gallery = PreviewData.gallery1
    ScrollView {
        GalleryCardView(
            gallery: $gallery,
            client: .preview
        )
        GalleryCardView(
            gallery: .constant(PreviewData.gallery2),
            client: .preview
        )
    }
    .previewEnvironments()
    .preferredColorScheme(.dark)
    .tint(Color.accentColor)
    .frame(maxHeight: .infinity, alignment: .top)
}

private struct GalleryActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onReport: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        List {
            if let onReport {
                Button {
                    dismiss()
                    onReport()
                } label: {
                    Label("Report", systemImage: "flag")
                        .foregroundStyle(.primary)
                }
            }
            if let onDelete {
                Button {
                    dismiss()
                    onDelete()
                } label: {
                    Label("Delete Gallery", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .tint(.primary)
    }
}

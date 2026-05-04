import NukeUI
import SwiftUI
import UIKit

extension View {
    /// Long-press context menu for gallery grid cells with a peek preview.
    /// `onOpen` mirrors the cell's tap action so the menu's "Open" item can
    /// commit the same navigation.
    func galleryPeekContextMenu(
        gallery: GrainGallery,
        labelDefinitions: [LabelDefinition],
        onOpen: @escaping () -> Void,
        onOpenProfile: (() -> Void)? = nil
    ) -> some View {
        let lr = resolveLabels(gallery.labels, definitions: labelDefinitions)
        let shareURL = galleryShareURL(for: gallery)
        let preview = GalleryPeekPreview(
            gallery: gallery,
            labelAction: lr.action,
            labelName: lr.name
        )
        return tint(Color.accentColor).contextMenu {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onOpen()
            } label: {
                Label("Open Gallery", systemImage: "arrow.up.right.square")
            }
            if let onOpenProfile {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onOpenProfile()
                } label: {
                    Label("Open Profile", systemImage: "person.circle")
                }
            }
            ShareLink(item: shareURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                sharePhotoAsImage(
                    gallery: gallery,
                    photoIndex: 0,
                    labelDefinitions: labelDefinitions
                )
            } label: {
                Label("Share as Image", systemImage: "photo.on.rectangle")
            }
            Button {
                UIPasteboard.general.url = shareURL
            } label: {
                Label("Copy Link", systemImage: "link")
            }
        } preview: {
            preview
        }
    }
}

private func galleryShareURL(for gallery: GrainGallery) -> URL {
    let rkey = gallery.uri.split(separator: "/").last.map(String.init) ?? ""
    let s = "https://grain.social/profile/\(gallery.creator.did)/gallery/\(rkey)"
    return URL(string: s) ?? URL(string: "https://grain.social")!
}

/// Compact peek preview of a gallery, shown inside a `.contextMenu(preview:)` overlay.
/// Renders the first photo at its true aspect ratio with a small metadata footer.
struct GalleryPeekPreview: View {
    let gallery: GrainGallery
    let labelAction: LabelAction
    let labelName: String

    private let maxWidth: CGFloat = 420

    private var maxHeight: CGFloat {
        dynamicPreviewMaxImageHeight()
    }

    private var firstPhoto: GrainPhoto? {
        gallery.items?.first
    }

    private var aspectRatio: Double {
        let r = firstPhoto?.aspectRatio.ratio ?? (3.0 / 4.0)
        return r > 0 ? r : (3.0 / 4.0)
    }

    private var imageSize: CGSize {
        let widthBoundHeight = maxWidth / aspectRatio
        if widthBoundHeight <= maxHeight {
            return CGSize(width: maxWidth, height: widthBoundHeight)
        }
        return CGSize(width: maxHeight * aspectRatio, height: maxHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageSection
            footer
        }
        .frame(width: imageSize.width)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var imageSection: some View {
        if labelAction >= .warnContent, !gallery.labelRevealed {
            warnedPlaceholder
        } else if let urlString = firstPhoto?.thumb, let url = URL(string: urlString) {
            ZStack {
                Rectangle().fill(.quaternary)
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
            .frame(width: imageSize.width, height: imageSize.height)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if (gallery.items?.count ?? 0) > 1 {
                    Image(systemName: "square.on.square.fill")
                        .font(.system(size: 14))
                        .rotationEffect(.degrees(180))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
        } else {
            Rectangle().fill(.quaternary)
                .frame(width: imageSize.width, height: imageSize.height)
        }
    }

    private var warnedPlaceholder: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .frame(width: imageSize.width, height: imageSize.height)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.title3)
                    Text(labelName)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AvatarView(url: gallery.creator.avatar, size: 24)
                Text(gallery.creator.displayName ?? "@\(gallery.creator.handle)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let title = gallery.title, !title.isEmpty {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            metaLine
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 26)
    }

    private var metaLine: some View {
        let count = gallery.items?.count ?? 0
        let favs = gallery.favCount ?? 0
        let comments = gallery.commentCount ?? 0
        return HStack(spacing: 14) {
            countChip(systemImage: "photo", value: count)
            countChip(systemImage: "heart", value: favs)
            countChip(systemImage: "bubble.right", value: comments)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private func countChip(systemImage: String, value: Int) -> some View {
    HStack(spacing: 3) {
        Image(systemName: systemImage)
        Text("\(value)")
    }
}

/// Stacked Syne wordmark + URL line. Both lines use primary color so they remain
/// readable on light or dark backgrounds.
struct GrainWordmark: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("grain")
                .font(.custom("Syne", size: 22).weight(.heavy))
                .foregroundStyle(Color.primary)
            Text("grain.social")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary)
        }
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: true, vertical: false)
    }
}

extension View {
    /// Long-press context menu for archived-story grid cells with a peek preview.
    func storyPeekContextMenu(
        story: GrainStory,
        labelDefinitions: [LabelDefinition],
        onOpen: @escaping () -> Void
    ) -> some View {
        let lr = resolveLabels(story.labels, definitions: labelDefinitions)
        let shareURL = storyShareURL(for: story)
        let preview = StoryPeekPreview(
            story: story,
            labelAction: lr.action,
            labelName: lr.name
        )
        let shareImage = StoryPeekPreview(
            story: story,
            labelAction: lr.action,
            labelName: lr.name,
            showsWordmark: true
        )
        return tint(Color.accentColor).contextMenu {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onOpen()
            } label: {
                Label("Open Story", systemImage: "arrow.up.right.square")
            }
            ShareLink(item: shareURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                presentPreviewImageShare(shareImage)
            } label: {
                Label("Share as Image", systemImage: "photo.on.rectangle")
            }
            Button {
                UIPasteboard.general.url = shareURL
            } label: {
                Label("Copy Link", systemImage: "link")
            }
        } preview: {
            preview
        }
    }
}

// MARK: - Render & share helpers

@MainActor
private func activeWindowScene() -> UIWindowScene? {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
        ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
}

@MainActor
func presentPreviewImageShare(_ view: some View) {
    let scene = activeWindowScene()
    let isDark = scene?.keyWindow?.traitCollection.userInterfaceStyle == .dark
    let scheme: ColorScheme = isDark ? .dark : .light
    let themed = view
        .environment(\.colorScheme, scheme)
        .background(Color(.systemBackground))
    let renderer = ImageRenderer(content: themed)
    renderer.scale = scene?.screen.scale ?? 3
    guard let image = renderer.uiImage else { return }
    let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
    var presenter = scene?.keyWindow?.rootViewController
    while let presented = presenter?.presentedViewController {
        presenter = presented
    }
    presenter?.present(activity, animated: true)
}

@MainActor
func dynamicPreviewMaxImageHeight() -> CGFloat {
    let screen = activeWindowScene()?.screen.bounds.height ?? 844
    let menuAndChromeReserve: CGFloat = 320
    let footerReserve: CGFloat = 110
    return max(220, screen - menuAndChromeReserve - footerReserve)
}

private func storyShareURL(for story: GrainStory) -> URL {
    let rkey = story.uri.split(separator: "/").last.map(String.init) ?? ""
    let s = "https://grain.social/profile/\(story.creator.did)/story/\(rkey)"
    return URL(string: s) ?? URL(string: "https://grain.social")!
}

/// Compact peek preview of an archived story.
struct StoryPeekPreview: View {
    let story: GrainStory
    let labelAction: LabelAction
    let labelName: String
    var showsWordmark: Bool = false

    private let maxWidth: CGFloat = 420

    private var maxHeight: CGFloat {
        dynamicPreviewMaxImageHeight()
    }

    private var aspectRatio: Double {
        let r = story.aspectRatio.ratio
        return r > 0 ? r : (3.0 / 4.0)
    }

    private var imageSize: CGSize {
        let widthBoundHeight = maxWidth / aspectRatio
        if widthBoundHeight <= maxHeight {
            return CGSize(width: maxWidth, height: widthBoundHeight)
        }
        return CGSize(width: maxHeight * aspectRatio, height: maxHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageSection
            footer
        }
        .frame(width: imageSize.width)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var imageSection: some View {
        if labelAction >= .warnContent {
            Rectangle()
                .fill(Color(.secondarySystemBackground))
                .frame(width: imageSize.width, height: imageSize.height)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.title3)
                        Text(labelName)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
        } else if let url = URL(string: story.thumb) {
            ZStack {
                Rectangle().fill(.quaternary)
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
            .frame(width: imageSize.width, height: imageSize.height)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if story.expired == true {
                    Text("Expired")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
            }
        } else {
            Rectangle().fill(.quaternary)
                .frame(width: imageSize.width, height: imageSize.height)
        }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    AvatarView(url: story.creator.avatar, size: 24)
                    Text(story.creator.displayName ?? "@\(story.creator.handle)")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 14) {
                    if let dateText = formattedDate {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                            Text(dateText)
                        }
                    }
                    if let loc = story.locationDisplay, !loc.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "location")
                            Text(loc).lineLimit(1)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if showsWordmark {
                Spacer(minLength: 0)
                GrainWordmark()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 34)
    }

    private var formattedDate: String? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: story.createdAt) ?? ISO8601DateFormatter().date(from: story.createdAt) else {
            return nil
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }
}

// MARK: - PhotoShareCard (single-photo share-as-image card)

/// Renders one photo from a gallery alongside its metadata as a shareable image.
/// Used as both the long-press peek preview and the `ImageRenderer` source so what
/// the user sees is what gets shared. Includes a stacked Syne wordmark + URL line
/// in the footer.
struct PhotoShareCard: View {
    let gallery: GrainGallery
    let photoIndex: Int
    let labelAction: LabelAction
    let labelName: String
    var showsGalleryBadge: Bool = true
    var showsWordmark: Bool = false

    private let cardWidth: CGFloat = 380

    private var maxImageHeight: CGFloat {
        dynamicPreviewMaxImageHeight()
    }

    private var photos: [GrainPhoto] {
        gallery.items ?? []
    }

    private var photo: GrainPhoto? {
        guard photoIndex >= 0, photoIndex < photos.count else { return photos.first }
        return photos[photoIndex]
    }

    private var aspectRatio: Double {
        let r = photo?.aspectRatio.ratio ?? (3.0 / 4.0)
        return r > 0 ? r : (3.0 / 4.0)
    }

    private var imageSize: CGSize {
        let widthBoundHeight = cardWidth / aspectRatio
        if widthBoundHeight <= maxImageHeight {
            return CGSize(width: cardWidth, height: widthBoundHeight)
        }
        return CGSize(width: maxImageHeight * aspectRatio, height: maxImageHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageSection
            footer
        }
        .frame(width: imageSize.width)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var imageSection: some View {
        if labelAction >= .warnContent, !gallery.labelRevealed {
            Rectangle()
                .fill(Color(.secondarySystemBackground))
                .frame(width: imageSize.width, height: imageSize.height)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "info.circle.fill").font(.title3)
                        Text(labelName).font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
        } else if let urlString = photo?.fullsize, let url = URL(string: urlString) {
            ZStack {
                Rectangle().fill(.quaternary)
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
            .frame(width: imageSize.width, height: imageSize.height)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if showsGalleryBadge, photos.count > 1 {
                    Image(systemName: "square.on.square.fill")
                        .font(.system(size: 14))
                        .rotationEffect(.degrees(180))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
        } else {
            Rectangle().fill(.quaternary)
                .frame(width: imageSize.width, height: imageSize.height)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    AvatarView(url: gallery.creator.avatar, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(gallery.creator.displayName ?? gallery.creator.handle)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if let dateText = formattedCreatedAt {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text(dateText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .layoutPriority(1)
                            }
                        }
                        Text("@\(gallery.creator.handle)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(height: 40)

                if showsWordmark {
                    Spacer(minLength: 0)
                    GrainWordmark()
                        .frame(height: 40, alignment: .top)
                }
            }

            if let title = gallery.title, !title.isEmpty {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if photos.count > 1 {
                HStack(spacing: 3) {
                    Image(systemName: "photo")
                    Text("\(photoIndex + 1)/\(photos.count)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 26)
    }

    private var formattedCreatedAt: String? {
        guard let iso = gallery.createdAt else { return nil }
        let isoF = ISO8601DateFormatter()
        isoF.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = isoF.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return nil
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}

private func shareCountChip(systemImage: String, text: String) -> some View {
    HStack(spacing: 3) {
        Image(systemName: systemImage)
        Text(text)
    }
}

@MainActor
func sharePhotoAsImage(
    gallery: GrainGallery,
    photoIndex: Int,
    labelDefinitions: [LabelDefinition]
) {
    let lr = resolveLabels(gallery.labels, definitions: labelDefinitions)
    let card = PhotoShareCard(
        gallery: gallery,
        photoIndex: photoIndex,
        labelAction: lr.action,
        labelName: lr.name,
        showsGalleryBadge: false,
        showsWordmark: true
    )
    presentPreviewImageShare(card)
}

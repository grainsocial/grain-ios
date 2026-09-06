import SwiftUI

/// One gallery as a tile in a grid — the explore page, a place's galleries.
///
/// The cover photo and nothing else but a mark for "there is more than one".
/// A tile is too small to carry a reveal affordance, so anything a label would
/// have covered stays covered here and opens revealed-or-not on the card
/// behind it.
struct GalleryThumbnailCell: View {
    @Environment(LabelDefinitionsCache.self) private var labelDefsCache
    @Environment(\.displayScale) private var displayScale

    let gallery: GrainGallery
    let cellSize: CGSize
    let action: () -> Void

    var body: some View {
        let resolution = resolveLabels(gallery.labels, definitions: labelDefsCache.definitions)
        Button(action: action) {
            Color.clear
                .overlay {
                    // A hidden tile never asks for the photo at all — the
                    // point of the label is that it shouldn't reach the device.
                    if let photo = gallery.items?.first, resolution.action < .hide {
                        ProfileGridThumbnail(
                            urlString: photo.thumb,
                            pixelSize: CGSize(width: cellSize.width * displayScale, height: cellSize.height * displayScale)
                        )
                    }
                }
                .clipped()
                .contentShape(Rectangle())
                .overlay {
                    if resolution.action >= .warnMedia {
                        Rectangle().fill(Color(.secondarySystemBackground))
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption2)
                            Text(resolution.name)
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if (gallery.items?.count ?? 0) > 1 {
                        Image(systemName: "square.on.square.fill")
                            .font(.system(size: 14))
                            .rotationEffect(.degrees(180))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(gallery.title ?? "Gallery")
    }
}

/// "1 photo", "1,234 photos".
func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count.formatted()) \(count == 1 ? singular : plural)"
}

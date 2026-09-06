import NukeUI
import SwiftUI

/// One entry in a browse index — a camera, a place.
///
/// A square with a mosaic of up to four photos behind the name and a count.
/// The mosaic is a sample of what is behind the tile rather than a feed in
/// its own right: the tile is for choosing, and the screen it opens is for
/// looking. Fewer than four photos stretch to fill rather than leaving holes,
/// so a place with one gallery doesn't read as a broken 2x2.
struct BrowseTile: View {
    let title: String
    let meta: String?
    let thumbs: [String]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color(.secondarySystemBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay { Mosaic(thumbs: Array(thumbs.prefix(4))) }
                .overlay(alignment: .bottomLeading) { label }
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(meta.map { "\(title), \($0)" } ?? title)
    }

    /// The name has to survive whatever photo is behind it, so the scrim is
    /// part of the tile. Deep and tall on purpose: a lot of what gets posted
    /// here is high-key film, and a shallow scrim leaves white on white.
    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
            if let meta {
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 34)
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.55), location: 0.55),
                    .init(color: .black.opacity(0.85), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

/// Up to four photos in a 2x2, with no gutter between them: the grid between
/// tiles has one, and matching it here made two adjacent tiles read as one
/// strip of four columns.
///
/// Two splits across, not down — a pair of full-width bands still reads as
/// one tile, where two tall slivers read as two. Three puts the first down the
/// left side and stacks the other two beside it.
private struct Mosaic: View {
    let thumbs: [String]

    var body: some View {
        switch thumbs.count {
        case 0:
            Color.clear
        case 1:
            photo(thumbs[0])
        case 2:
            VStack(spacing: 0) {
                photo(thumbs[0])
                photo(thumbs[1])
            }
        case 3:
            HStack(spacing: 0) {
                photo(thumbs[0])
                VStack(spacing: 0) {
                    photo(thumbs[1])
                    photo(thumbs[2])
                }
            }
        default:
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    photo(thumbs[0])
                    photo(thumbs[1])
                }
                HStack(spacing: 0) {
                    photo(thumbs[2])
                    photo(thumbs[3])
                }
            }
        }
    }

    private func photo(_ url: String) -> some View {
        Color.clear
            .overlay {
                LazyImage(url: URL(string: url)) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color(.secondarySystemBackground)
                    }
                }
            }
            .clipped()
    }
}

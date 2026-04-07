import SwiftUI

/// Shared photo cell. Drag is attached externally by the parent (custom SwiftUI
/// gesture, NOT system .draggable). The pill is a passive ALT indicator with
/// `.allowsHitTesting(false)` so touches always fall through to the cell's tap.
struct PhotoThumbnailCell: View {
    @Binding var item: PhotoItem
    /// Display mode controls both the cell frame and the image content mode.
    ///   • `.square(side)` — square cell, image is scaledToFill (cropped). Used by the
    ///     horizontal strip.
    ///   • `.slot(size)` — rectangular slot at fixed dimensions, image is scaledToFit
    ///     so its natural aspect is preserved (letterboxed within the slot). Used by
    ///     the grid where all slots are the same size and only the most-portrait photo
    ///     fills its slot exactly.
    var mode: Mode
    var isSelected: Bool = false
    /// Hide the X button. Currently always false in production — kept as a parameter
    /// for future use (e.g., the planned force-square toggle UI).
    var hideDelete: Bool = false
    let onTap: () -> Void
    let onDelete: () -> Void

    enum Mode: Equatable {
        case square(CGFloat)
        case slot(CGSize)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            imageContent
            // X button — always positioned at the top-right corner, slightly outside
            // the cell. It's the topmost child in the ZStack, so it sits above the
            // photo within this cell. When the parent applies zIndex(1) to a dragged
            // cell, this X rides along on top of the lifted photo.
            deleteButton
        }
        .modifier(CellFrameModifier(mode: mode))
        // Tap gesture at the OUTER body (not on the inner Image) so it sits at the
        // same level as the parent's reorder recognizer instead of competing as a
        // contested child. The X button (a child Button) still claims its own taps.
        .onTapGesture { onTap() }
    }

    private var imageContent: some View {
        // The outer ZStack's CellFrameModifier is the sole sizer — the image just
        // fills (square) or fits (slot) inside whatever size the parent ends up at.
        Image(uiImage: item.thumbnail)
            .resizable()
            .modifier(ImageContentModeModifier(mode: mode))
            .clipped()
            .overlay(alignment: .bottomTrailing) { altPill }
            .reorderableThumbnail(
                isDragging: false,
                isSelected: isSelected
            )
    }

    private var altPill: some View {
        let hasAlt = !item.alt.trimmingCharacters(in: .whitespaces).isEmpty
        return Text("ALT")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
            .opacity(hasAlt ? 1 : 0.5)
            .padding(5)
            .allowsHitTesting(false)
            .accessibilityLabel(hasAlt ? "Has alt text" : "No alt text")
    }

    /// X button at the cell's top-right corner. 44pt frame for HIG-compliant tap area.
    /// `.topTrailing` alignment of the parent ZStack puts the frame's top-right corner
    /// at the cell's top-right corner, which means the frame's center (where the visible
    /// icon sits) is 22pt INSIDE the cell along each axis. Offsetting by (+22, -22)
    /// translates the frame so its center now lands exactly ON the cell's corner —
    /// half the icon is inside the cell, half is outside, centered on the corner.
    /// Slightly overflows the cell, so parent containers should not clip aggressively.
    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white, Color.accentColor)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: 22, y: -22)
        .opacity(hideDelete ? 0 : 1)
        .animation(.snappy, value: hideDelete)
    }
}

/// Sizes the cell to either a square (strip) or a uniform slot (grid). The grid
/// computes slot dimensions ahead of time using the most-portrait photo's aspect, so
/// every slot is identical and the most-portrait photo fills its slot exactly.
private struct CellFrameModifier: ViewModifier {
    let mode: PhotoThumbnailCell.Mode

    func body(content: Content) -> some View {
        switch mode {
        case let .square(side):
            content.frame(width: side, height: side)
        case let .slot(size):
            content.frame(width: size.width, height: size.height)
        }
    }
}

/// Picks the right `contentMode` for the image based on the cell's mode. Square
/// cells crop (`.fill`); slot cells letterbox (`.fit`) so the photo's natural aspect
/// is preserved inside the uniform grid slot.
private struct ImageContentModeModifier: ViewModifier {
    let mode: PhotoThumbnailCell.Mode

    func body(content: Content) -> some View {
        switch mode {
        case .square:
            content.aspectRatio(contentMode: .fill)
        case .slot:
            content.aspectRatio(contentMode: .fit)
        }
    }
}

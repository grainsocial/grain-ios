import SwiftUI

/// Shared photo cell. Drag is attached externally by the parent (custom SwiftUI
/// gesture, NOT system .draggable). The pill is a passive ALT indicator with
/// `.allowsHitTesting(false)` so touches always fall through to the cell's tap.
struct PhotoThumbnailCell: View {
    @Binding var item: PhotoItem
    /// Display mode controls both the cell frame and the image content mode.
    ///   • `.square(side)` — square cell, image is scaledToFill (cropped). Used by the
    ///     horizontal strip.
    ///   • `.slot(height)` — rectangular slot at a fixed height; width comes from
    ///     the parent layout (e.g., LazyVGrid's flexible columns). The image is
    ///     scaledToFit so its natural aspect is preserved (letterboxed within the
    ///     slot). The grid pre-computes the slot height from the most-portrait photo
    ///     so every slot is identical and only that photo fills its slot exactly.
    var mode: Mode
    /// Photo's natural aspect ratio (W/H). Derived from `item.thumbnail` so the
    /// cell can size itself to the photo's natural proportions in grid mode
    /// without the parent having to precompute anything.
    private var naturalAspect: CGFloat {
        let w = item.thumbnail.size.width
        let h = item.thumbnail.size.height
        guard h > 0 else { return 1 }
        return w / h
    }

    var isSelected: Bool = false
    /// True when this specific cell is the one currently being dragged. Drives the
    /// pickup scale-up + opacity-fade + drop-shadow animation at the outer body
    /// level so the X button and any future matched-geometry overlay scale together
    /// with the photo.
    var isDragging: Bool = false
    /// Hide the X button. Currently always false in production — kept as a parameter
    /// for future use (e.g., the planned force-square toggle UI).
    var hideDelete: Bool = false
    /// Shared namespace for the future strip↔grid matched-geometry transition. When
    /// set, the image view is marked with `.matchedGeometryEffect(id: item.id, in: ns)`
    /// so it can animate between strip-cell and grid-slot bounds.
    var matchedNamespace: Namespace.ID?
    let onTap: () -> Void
    let onDelete: () -> Void

    enum Mode: Equatable {
        /// Strip: fixed square cell, image is scaledToFill (cropped), rounded
        /// corner radius so the thumbnail looks like a HIG tile.
        case square(CGFloat)
        /// Grid: cell takes the parent's column width and its natural-aspect
        /// height. Image is aspect-fit so the photo is rendered uncropped at its
        /// original proportions. No corner radius — raw rectangular photos.
        case grid
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
        .modifier(CellFrameModifier(mode: mode, aspect: naturalAspect))
        // Pickup animation is applied at the outer body, so the ZStack (image + X
        // button) scales together. Keeping the X tied to the photo's top-right
        // means it physically moves outward as the photo grows during pickup.
        .scaleEffect(isDragging ? 1.1 : 1)
        .opacity(isDragging ? 0.8 : 1)
        .shadow(
            color: isDragging ? .black.opacity(0.25) : .clear,
            radius: 10, y: 6
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isDragging)
        // Tap gesture at the OUTER body (not on the inner Image) so it sits at the
        // same level as the parent's reorder recognizer instead of competing as a
        // contested child. The X button (a child Button) still claims its own taps.
        .onTapGesture { onTap() }
    }

    private var imageContent: some View {
        // The outer ZStack's CellFrameModifier is the sole sizer — the image just
        // fills (square) or fits (slot) inside whatever size the parent ends up at.
        //
        // Square mode uses `.scaledToFill()` for now. TODO: when we wire the
        // strip↔grid matched-geometry transition, swap to explicit frames so the
        // inner photo view has stable, measurable bounds for the transition to
        // anchor on:
        //
        //     // photoAspect = thumbnail.width / thumbnail.height
        //     // if photoAspect >= 1 {
        //     //     photoHeight = side
        //     //     photoWidth  = side * photoAspect       // overflows horizontally
        //     // } else {
        //     //     photoWidth  = side
        //     //     photoHeight = side / photoAspect       // overflows vertically
        //     // }
        //     // Image(uiImage: item.thumbnail).resizable()
        //     //     .frame(width: photoWidth, height: photoHeight)   // inner view: matchedGeometryEffect target
        //     //     .frame(width: side, height: side)                // outer mask
        //     //     .clipped()
        //
        // Same visible result as `.scaledToFill()` — but the inner frame is a real
        // view that matched-geometry can animate between strip-size and grid-size.
        Image(uiImage: item.thumbnail)
            .resizable()
            .modifier(ImageContentModeModifier(mode: mode))
            .clipped()
            .modifier(MatchedPhotoModifier(id: item.id, namespace: matchedNamespace))
            .overlay(alignment: .bottomTrailing) { altPill }
            .reorderableThumbnail(isSelected: isSelected, cornerRadius: cornerRadius)
    }

    /// Corner radius for the photo clip / selection ring. Strip cells get the
    /// HIG-ish 8pt rounded-tile look; grid cells are flat rectangular photos with
    /// no rounding at all per the "raw photos, natural aspect" direction.
    private var cornerRadius: CGFloat {
        switch mode {
        case .square: 8
        case .grid: 0
        }
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

/// Sizes the cell. Square mode (strip) uses a fixed width and height. Grid mode
/// takes the parent LazyVGrid's column width and sets its height from the photo's
/// natural aspect ratio — each cell ends up at its photo's native proportions.
/// `.frame(maxWidth: .infinity)` lets the grid's flexible column drive width;
/// `.aspectRatio(aspect, .fit)` computes height from that width and the photo's
/// own W/H, so the cell's frame IS the photo's frame. No letterboxing, no crop.
private struct CellFrameModifier: ViewModifier {
    let mode: PhotoThumbnailCell.Mode
    let aspect: CGFloat

    func body(content: Content) -> some View {
        switch mode {
        case let .square(side):
            content.frame(width: side, height: side)
        case .grid:
            content
                .frame(maxWidth: .infinity)
                .aspectRatio(aspect, contentMode: .fit)
        }
    }
}

/// Picks the right `contentMode` for the image based on the cell's mode. Square
/// cells crop (`.fill`); grid cells fit (`.fit`), which — because the cell's frame
/// already matches the photo's aspect — means the photo fills its cell exactly
/// with no cropping and no letterboxing.
private struct ImageContentModeModifier: ViewModifier {
    let mode: PhotoThumbnailCell.Mode

    func body(content: Content) -> some View {
        switch mode {
        case .square:
            content.aspectRatio(contentMode: .fill)
        case .grid:
            content.aspectRatio(contentMode: .fit)
        }
    }
}

/// Conditionally applies `matchedGeometryEffect` when a namespace is provided.
/// The strip and grid both pass the SAME `Namespace.ID` for the SAME photo id,
/// so when we eventually animate between strip mode and grid mode the image
/// smoothly morphs between the two cell frames. Wrapped in a modifier so the
/// no-namespace case (previews, unit tests) skips it entirely.
private struct MatchedPhotoModifier: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

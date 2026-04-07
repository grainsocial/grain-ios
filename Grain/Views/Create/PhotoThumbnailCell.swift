import SwiftUI

/// Shared photo cell. Drag is attached externally by the parent (custom SwiftUI
/// gesture, NOT system .draggable). The pill is a passive ALT indicator with
/// `.allowsHitTesting(false)` so touches always fall through to the cell's tap.
struct PhotoThumbnailCell: View {
    @Binding var item: PhotoItem
    var mode: Mode
    var isSelected: Bool = false
    /// True when this specific cell is the one currently being dragged. Drives the
    /// pickup scale-up + opacity-fade + drop-shadow animation at the outer body
    /// level so the X button and any future matched-geometry overlay scale together
    /// with the photo.
    var isDragging: Bool = false
    /// Hide the X button. Currently always false in production — kept as a parameter
    /// for future use (e.g., the planned force-square toggle UI).
    var hideDelete: Bool = false
    /// Shared namespace for the future strip↔grid matched-geometry transition.
    var matchedNamespace: Namespace.ID?
    let onTap: () -> Void
    let onDelete: () -> Void

    enum Mode: Equatable {
        /// Strip: fixed square cell, image is scaledToFill into an explicit
        /// square frame, cropped to that frame, then rounded. The visible cell
        /// is ALWAYS a square regardless of the photo's aspect — center-crop.
        case square(CGFloat)
        /// Grid: cell takes its column width and its natural-aspect height.
        /// Image is aspect-fit inside a frame that matches the photo's aspect
        /// ratio exactly — no crop, no letterbox, no corner radius.
        case grid
    }

    /// Photo's natural aspect ratio (W/H) from `item.thumbnail`. Used only by
    /// grid mode to size its frame.
    private var naturalAspect: CGFloat {
        let w = item.thumbnail.size.width
        let h = item.thumbnail.size.height
        guard h > 0 else { return 1 }
        return w / h
    }

    var body: some View {
        cellContent
            // Pickup animation at the outer body so the whole ZStack (image +
            // X button + any future matched-geometry overlay) scales together.
            // Keeping the X tied to the photo's top-right means it physically
            // rides outward with the corner as the photo grows.
            .scaleEffect(isDragging ? 1.1 : 1)
            .opacity(isDragging ? 0.8 : 1)
            .shadow(
                color: isDragging ? .black.opacity(0.25) : .clear,
                radius: 10, y: 6
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isDragging)
            // Tap gesture at the OUTER body (sibling to the parent's reorder
            // recognizer instead of a contested child). The X button's own
            // Button still claims its own taps.
            .onTapGesture { onTap() }
    }

    /// Explicit per-mode rendering. No shared ViewModifier wrappers — each mode
    /// writes out its own frame and content mode so there's zero ambiguity about
    /// what sizes / clips / scales happen.
    @ViewBuilder
    private var cellContent: some View {
        switch mode {
        case let .square(side):
            ZStack(alignment: .topTrailing) {
                squarePhoto(side: side)
                deleteButton
            }
            .frame(width: side, height: side)
        case .grid:
            ZStack(alignment: .topTrailing) {
                gridPhoto
                deleteButton
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(naturalAspect, contentMode: .fit)
        }
    }

    /// Square cell for the strip. The chain is the canonical SwiftUI pattern
    /// for "crop an arbitrary-aspect photo into a fixed square tile":
    /// `.resizable().scaledToFill().frame(side, side).clipped()`. The inner
    /// frame + clipped() is what enforces the square — wrapping this in a view
    /// modifier was subtly losing the clip in some edge cases, so it's inline
    /// now.
    private func squarePhoto(side: CGFloat) -> some View {
        Image(uiImage: item.thumbnail)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .clipped()
            .modifier(MatchedPhotoModifier(id: item.id, namespace: matchedNamespace))
            .overlay(alignment: .bottomTrailing) { altPill }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2.5)
                    .opacity(isSelected ? 1 : 0)
            )
    }

    /// Grid cell. The surrounding `.aspectRatio(naturalAspect, .fit)` on the
    /// ZStack means the cell's frame IS the photo's frame — so `scaledToFit`
    /// here fills the frame exactly with no letterboxing and no crop. No
    /// corner radius: raw rectangular photos per the "natural aspect" direction.
    private var gridPhoto: some View {
        Image(uiImage: item.thumbnail)
            .resizable()
            .scaledToFit()
            .modifier(MatchedPhotoModifier(id: item.id, namespace: matchedNamespace))
            .overlay(alignment: .bottomTrailing) { altPill }
            .overlay(
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2.5)
                    .opacity(isSelected ? 1 : 0)
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

/// Conditionally applies `matchedGeometryEffect` when a namespace is provided.
/// Prep for the eventual strip↔grid transition — the strip and grid both pass
/// the SAME `Namespace.ID` for the SAME photo id, so the photo view can animate
/// between its strip-square and grid-slot bounds.
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

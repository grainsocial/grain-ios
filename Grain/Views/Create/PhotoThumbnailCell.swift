import SwiftUI

/// Shared photo cell used across all three editor modes (strip, grid, captions).
///
/// Layout model: three independently animatable pieces in a ZStack:
///
///   1. **Photo** — rendered at `geometry.photoSize` (natural-aspect rectangle
///      scaled by mode-specific rule: fill in preview, fit in reorder).
///   2. **Mask** — `maskSide x maskSide` square frame + `.clipped()`. The mask
///      animates between modes (72pt strip → column-width grid → 60pt captions).
///   3. **X button** — `.position(x: maskSide, y: 0)` so its center sits on the
///      mask's top-right corner. Follows the mask as it animates.
///
/// With the `AdaptivePhotoLayout` approach, the same cell instance persists
/// across mode switches. SwiftUI interpolates maskSide and position changes
/// automatically — no matchedGeometryEffect needed.
struct PhotoThumbnailCell: View {
    @Binding var item: PhotoItem
    var geometry: CellGeometry
    var isSelected: Bool = false
    var isDragging: Bool = false
    var hideDelete: Bool = false
    var deleteOpacity: CGFloat = 1
    var exifState: ExifState = .absent
    /// True during mode transitions. Gates per-property `.animation()` so
    /// selection/drag springs don't compete with the Layout transition.
    var isAnimatingMode: Bool = false
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Photo
            Image(uiImage: item.thumbnail)
                .resizable()
                .frame(width: geometry.photoSize.width, height: geometry.photoSize.height)
                .frame(width: geometry.maskSide, height: geometry.maskSide)
                .clipShape(RoundedRectangle(cornerRadius: geometry.maskCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: geometry.maskCornerRadius, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2.5 : 0)
                )
                .overlay(alignment: .bottomTrailing) {
                    altPill.opacity(hideDelete ? 0 : 1)
                }
                .overlay(alignment: .bottomLeading) {
                    ExifChip(state: exifState)
                        .padding(5)
                }

            // X button
            deleteButton
                .scaleEffect((hideDelete ? 0 : deleteOpacity) / (isDragging ? 1.1 : 1))
                .position(x: geometry.maskSide, y: 0)
                .allowsHitTesting(!hideDelete && deleteOpacity > 0)
        }
        .frame(width: geometry.maskSide, height: geometry.maskSide)
        .contentShape(Rectangle())
        .animation(
            isAnimatingMode ? nil : .easeInOut(duration: 0.2),
            value: isSelected
        )
        .scaleEffect(isDragging ? 1.1 : 1)
        .opacity(isDragging ? 0.8 : 1)
        .shadow(color: isDragging ? .black.opacity(0.25) : .clear, radius: 10, y: 6)
        .animation(isAnimatingMode ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: isDragging)
        .onTapGesture { onTap() }
    }

    @ViewBuilder private var altPill: some View {
        let hasAlt = !item.alt.trimmingCharacters(in: .whitespaces).isEmpty
        Text("ALT")
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

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white, Color.accentColor)
                .frame(width: 44, height: 44)
                .contentShape(Circle().scale(0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove photo")
    }
}

#Preview {
    let items = Array(PreviewData.photoItemsWithExif.prefix(3))
    HStack(spacing: 20) {
        PhotoThumbnailCell(
            item: .constant(items[0]),
            geometry: CellGeometry(mode: .preview, maskSide: 72, photoAspect: items[0].naturalAspect),
            isSelected: true,
            exifState: .active,
            onTap: {},
            onDelete: {}
        )
        PhotoThumbnailCell(
            item: .constant(items[1]),
            geometry: CellGeometry(mode: .preview, maskSide: 72, photoAspect: items[1].naturalAspect),
            isSelected: false,
            exifState: .inactive,
            onTap: {},
            onDelete: {}
        )
        PhotoThumbnailCell(
            item: .constant(items[2]),
            geometry: CellGeometry(mode: .reorder, maskSide: 110, photoAspect: items[2].naturalAspect),
            isSelected: false,
            exifState: .absent,
            onTap: {},
            onDelete: {}
        )
    }
    .padding(30)
    .grainPreview()
}

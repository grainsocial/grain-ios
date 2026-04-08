import os
import SwiftUI

private let thumbnailSignposter = OSSignposter(subsystem: "social.grain.grain", category: "Animation.Morph")

/// Shared photo cell. Drag is attached externally by the parent (custom SwiftUI
/// gesture, NOT system .draggable). The pill is a passive ALT indicator with
/// `.allowsHitTesting(false)` so touches always fall through to the cell's tap.
///
/// Layout model: each cell is structured as three independently animatable
/// pieces stacked in a ZStack:
///
///   1. **Photo** — rendered at `geometry.photoSize`, which is the photo's
///      natural-aspect rectangle scaled by the mode-specific rule (fill in
///      preview, fit in reorder).
///   2. **Mask** — a `geometry.maskSide × geometry.maskSide` square frame
///      wrapped around the photo via `.frame().clipped()`, centered on the
///      photo's center. The mask's side animates between modes; in `.preview`
///      it crops the photo to a center square, in `.reorder` it grows to
///      `geometry.maskSide` (the column-width square) which fully contains
///      the natural-aspect photo with letterboxing on the off-axis.
///   3. **X button** — positioned via `.position(x: maskSide, y: 0)` so its
///      *center* sits on the mask's top-right corner. The X follows the mask
///      (not the photo's intrinsic edges) so as the mask animates the X
///      glides along its corner. Hidden via `hideDelete` while the parent
///      strip↔grid morph is in flight.
///
/// `MatchedPhotoModifier` is applied to the **outer** ZStack (after the
/// `.frame(maskSide × maskSide)`) so SwiftUI's matched-geometry pairs the
/// whole cell — its position in the strip's HStack and its position in the
/// grid's LazyVGrid — across the morph. Putting it on the inner Image (the
/// previous mistake) only animated the inner image's bounds, not the cell's
/// position in its parent layout, which is why photos appeared in their new
/// spots without shifting.
struct PhotoThumbnailCell: View {
    @Binding var item: PhotoItem
    /// Bundle of layout values from the parent (mode + maskSide + photoAspect
    /// → photoSize, maskCornerRadius). The type prevents callers from passing
    /// a maskSide that doesn't match the cell's mode.
    var geometry: CellGeometry
    var isSelected: Bool = false
    /// True when this specific cell is the one currently being dragged. Drives
    /// the pickup scale-up + opacity-fade + drop-shadow animation at the outer
    /// body level so the X button and any matched-geometry overlay scale
    /// together with the photo.
    var isDragging: Bool = false
    /// Hide the X button. Currently always false in production — kept as a
    /// parameter for future use (e.g. a force-square toggle). The X used to
    /// be hidden during the strip↔grid morph, but the user reported the
    /// disappear/reappear was jarring, so it now stays visible and rides the
    /// cell's matched-geometry transition along with the photo.
    var hideDelete: Bool = false
    /// Opacity applied to the X button independently of `hideDelete`. Used by
    /// PhotoStrip to fade the delete button as its cell slides off the visible
    /// edge — only starts fading below 50% cell visibility so it's not
    /// aggressive on cells that are mostly on screen.
    var deleteOpacity: CGFloat = 1
    /// EXIF chip state for the bottom-leading corner overlay. Defaults to
    /// `.absent` so existing call sites that don't pass the parameter compile
    /// unchanged and render no chip.
    var exifState: ExifState = .absent
    /// Shared namespace for the strip↔grid matched-geometry transition.
    var matchedNamespace: Namespace.ID?
    /// When false, this cell is a matched-geometry DESTINATION ONLY — it
    /// won't contribute its own bounds as a source for paired views in other
    /// modes. Used by the captions list, whose rows can scroll off-screen and
    /// hand strip/grid destinations negative-y source frames (causing items
    /// to fly in "from above" during captions→strip/grid). Strip and grid
    /// stay as sources (the default) so strip→captions and grid→captions
    /// still morph correctly.
    var isMatchedSource: Bool = true
    /// True during strip↔grid↔captions mode morphs. Gates the per-property
    /// `.animation(.spring, value: isSelected/isDragging)` modifiers so they
    /// don't fire their own spring curve alongside the morph's `.smooth` —
    /// two different settling rates on the same view produced visible jitter
    /// as the morph came to rest.
    var isAnimatingMode: Bool = false
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. Photo — explicit frame at the rendered (natural-aspect)
            //    photoSize, then wrapped in the mask square. .clipped() crops
            //    to the outer (mask) frame. .frame() centers its child by
            //    default, so the photo's center sits on the mask's center,
            //    matching the spec ("center of mask and center of photo
            //    should align").
            Image(uiImage: item.thumbnail)
                .resizable()
                .frame(width: geometry.photoSize.width, height: geometry.photoSize.height)
                .frame(width: geometry.maskSide, height: geometry.maskSide)
                .clipShape(RoundedRectangle(cornerRadius: geometry.maskCornerRadius, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    altPill.opacity(hideDelete ? 0 : 1)
                }
                .overlay(alignment: .bottomLeading) {
                    // ExifChip visibility is driven purely by `exifState`:
                    // callers that don't want the chip pass `.absent`. This is
                    // decoupled from `hideDelete` so the captions list can
                    // render cells with hideDelete=true (no corner X, no
                    // altPill) while still showing the EXIF badge.
                    ExifChip(state: exifState)
                        .padding(5)
                }

            // 2. X button — positioned so its center sits exactly on the
            //    mask's top-right corner. The .position modifier sets the
            //    view's CENTER at the given point in the parent's coordinate
            //    space. With the parent ZStack at maskSide × maskSide, the
            //    point (maskSide, 0) IS the top-right corner. As maskSide
            //    animates, the position updates and SwiftUI interpolates it
            //    inside the same withAnimation that drives the morph.
            deleteButton
                // Divide by the parent cell's selection/drag scale so the X
                // button's apparent size is always `deleteOpacity`, independent
                // of whether the cell is selected or being dragged.
                .scaleEffect((hideDelete ? 0 : deleteOpacity) / (isDragging ? 1.1 : isSelected ? 1.12 : 1))
                .position(x: geometry.maskSide, y: 0)
                .allowsHitTesting(!hideDelete && deleteOpacity > 0)
        }
        .frame(width: geometry.maskSide, height: geometry.maskSide)
        // matched-geometry on the OUTER frame so SwiftUI pairs the cell's
        // POSITION (not just the inner image's bounds) across the strip↔grid
        // swap. This is the morph fix. `isSource` is plumbed through so the
        // captions list can opt out of providing source frames — see the
        // doc comment on `isMatchedSource`.
        .modifier(MatchedPhotoModifier(
            id: item.id,
            namespace: matchedNamespace,
            isSource: isMatchedSource
        ))
        // Selection: accent-color glow + directional lift. Suppressed while
        // dragging so the drag shadow reads cleanly without competing bloom.
        .shadow(color: isSelected && !isDragging ? Color.accentColor.opacity(0.9) : .clear, radius: 5)
        .shadow(color: isSelected && !isDragging ? Color.accentColor.opacity(0.45) : .clear, radius: 10)
        .shadow(color: isSelected && !isDragging ? .black.opacity(0.25) : .clear, radius: 8, x: 0, y: 5)
        .animation(
            isAnimatingMode ? nil
                : isSelected
                ? .spring(response: 0.3, dampingFraction: 0.8)
                : .spring(response: 0.3, dampingFraction: 1.0),
            value: isSelected
        )
        // Scale anchored to the X button (topTrailing corner) so the X stays
        // fixed during selection/drag — no position jitter on the X. The offset
        // compensates for the topTrailing expansion so the photo content appears
        // to stay visually centered rather than drifting left and down.
        .scaleEffect(isDragging ? 1.1 : isSelected ? 1.12 : 1, anchor: .topTrailing)
        .offset(
            x: ((isDragging ? 1.1 : isSelected ? 1.12 : 1.0) - 1.0) * geometry.maskSide / 2,
            y: -((isDragging ? 1.1 : isSelected ? 1.12 : 1.0) - 1.0) * geometry.maskSide / 2
        )
        .opacity(isDragging ? 0.8 : 1)
        .shadow(color: isDragging ? .black.opacity(0.25) : .clear, radius: 10, y: 6)
        .animation(isAnimatingMode ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: isDragging)
        // Tap gesture at the OUTER body (sibling to the parent's reorder
        // recognizer instead of a contested child). The X button's own
        // Button still claims its own taps.
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

    /// X button at the cell's top-right corner. 44pt frame for HIG-compliant
    /// tap area. The .position modifier in `body` puts this view's CENTER on
    /// the mask's top-right corner — half the icon visually overlaps the mask,
    /// half overflows outside it. ZStack does NOT clip its children, so the
    /// outer half stays visible into the parent layout's spacing.
    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white, Color.accentColor)
                .frame(width: 44, height: 44)
                .contentShape(Circle().scale(0.7))
        }
        .buttonStyle(.plain)
    }
}

/// Conditionally applies `matchedGeometryEffect` when a namespace is provided.
/// All three modes (strip, grid, captions) pass the SAME `Namespace.ID` for
/// the SAME photo id, so the cell's outer frame can morph between any two
/// modes. Applied to the cell's OUTER frame in `PhotoThumbnailCell.body`,
/// not to the inner image — that's the difference between "inner image
/// bounds wiggle" and "whole cell shifts across the layout swap".
///
/// `isSource` is surfaced here because the captions list needs to opt OUT
/// of providing source frames. Captions rows live in a tall scrollable list
/// and can sit above or below the viewport when the form is scrolled. At
/// mode-swap time, matched-geometry reads the unmounting source's global
/// frame — if that frame is off-viewport (negative y or below-viewport y),
/// strip/grid destinations animate *from* that off-screen position,
/// producing the "items fly in from above" bug. Marking captions cells as
/// destination-only prevents that: strip/grid remain sources (the default),
/// so strip→captions and grid→captions still morph, but captions→strip and
/// captions→grid skip the broken source-frame capture and just settle at
/// their natural destination bounds.
struct MatchedPhotoModifier: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?
    var isSource: Bool = true

    func body(content: Content) -> some View {
        if let namespace {
            content
                .matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
                .modifier(CellGlobalFrameReporter(id: id, passthrough: false))
                .onAppear { thumbnailSignposter.emitEvent("MatchedApplied") }
        } else {
            content
                .modifier(CellGlobalFrameReporter(id: id, passthrough: true))
                .onAppear { thumbnailSignposter.emitEvent("MatchedPassthrough") }
        }
    }
}

/// Diagnostic modifier that emits a `CellGlobalFrame` signpost whenever the
/// cell's global frame changes. Correlate these events with `MorphAnimation`
/// intervals in Instruments (subsystem `social.grain.grain`, category
/// `Animation.Morph`) to verify that matched-geometry captured stable
/// destination frames: if a cell's frame keeps changing AFTER the morph
/// completion signpost fires, something downstream is still moving it.
///
/// `.onGeometryChange` samples after layout settles and does NOT participate
/// in the layout pass, so attaching it is safe — it won't perturb the thing
/// it's measuring. This is deliberately NOT #if DEBUG-gated: OSSignposter is
/// production-safe and the events are only materialized when an Instruments
/// trace is actively recording.
private struct CellGlobalFrameReporter: ViewModifier {
    let id: UUID
    let passthrough: Bool

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                thumbnailSignposter.emitEvent(
                    "CellGlobalFrame",
                    "id=\(id.uuidString.prefix(8)),x=\(Int(frame.minX.rounded())),y=\(Int(frame.minY.rounded())),w=\(Int(frame.width.rounded())),h=\(Int(frame.height.rounded())),passthrough=\(passthrough ? 1 : 0)"
                )
            }
    }
}

#Preview {
    let items = Array(PreviewData.photoItemsWithExif.prefix(3))
    HStack(spacing: 20) {
        // Strip/preview mode — selected, EXIF active
        PhotoThumbnailCell(
            item: .constant(items[0]),
            geometry: CellGeometry(mode: .preview, maskSide: 72, photoAspect: items[0].naturalAspect),
            isSelected: true,
            exifState: .active,
            onTap: {},
            onDelete: {}
        )
        // Strip/preview mode — unselected, EXIF inactive
        PhotoThumbnailCell(
            item: .constant(items[1]),
            geometry: CellGeometry(mode: .preview, maskSide: 72, photoAspect: items[1].naturalAspect),
            isSelected: false,
            exifState: .inactive,
            onTap: {},
            onDelete: {}
        )
        // Reorder (grid) mode — larger mask, no EXIF
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

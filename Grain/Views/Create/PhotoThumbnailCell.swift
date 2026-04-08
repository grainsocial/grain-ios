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
    /// EXIF chip state for the bottom-leading corner overlay. Defaults to
    /// `.absent` so existing call sites that don't pass the parameter compile
    /// unchanged and render no chip.
    var exifState: ExifState = .absent
    var cameraName: String?
    /// Shared namespace for the strip↔grid matched-geometry transition.
    var matchedNamespace: Namespace.ID?
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
                    ExifChip(state: exifState, cameraName: cameraName, compact: true)
                        .padding(5)
                        .opacity(hideDelete ? 0 : 1)
                }
                .overlay {
                    // Selection ring. RoundedRectangle(.continuous) gives
                    // squircle corners whose stroke weight is visually even
                    // around the whole ring. Frame expanded by lw so .stroke's
                    // inner edge lands on the image boundary. Corner radius
                    // bumped by lw/2 so the inner arc matches the clip.
                    let lw: CGFloat = 3.0
                    RoundedRectangle(
                        cornerRadius: geometry.maskCornerRadius + lw / 2,
                        style: .continuous
                    )
                    .trim(from: 0, to: isSelected ? 1 : 0)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    .frame(width: geometry.maskSide + lw, height: geometry.maskSide + lw)
                    .animation(.easeInOut(duration: 0.25), value: isSelected)
                    .drawingGroup()
                }

            // 2. X button — positioned so its center sits exactly on the
            //    mask's top-right corner. The .position modifier sets the
            //    view's CENTER at the given point in the parent's coordinate
            //    space. With the parent ZStack at maskSide × maskSide, the
            //    point (maskSide, 0) IS the top-right corner. As maskSide
            //    animates, the position updates and SwiftUI interpolates it
            //    inside the same withAnimation that drives the morph.
            deleteButton
                .position(x: geometry.maskSide, y: 0)
                .opacity(hideDelete ? 0 : 1)
                .allowsHitTesting(!hideDelete)
        }
        .frame(width: geometry.maskSide, height: geometry.maskSide)
        // matched-geometry on the OUTER frame so SwiftUI pairs the cell's
        // POSITION (not just the inner image's bounds) across the strip↔grid
        // swap. This is the morph fix. The editor swaps strip and grid via
        // if/else so at most one source exists per id at any moment — no
        // isSource plumbing needed.
        .modifier(MatchedPhotoModifier(
            id: item.id,
            namespace: matchedNamespace
        ))
        // Pickup animation at the outer body so the whole cell (photo + X)
        // scales together. Keeps the X tied to the cell so it physically
        // rides outward as the photo grows.
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
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Conditionally applies `matchedGeometryEffect` when a namespace is provided.
/// The strip and grid both pass the SAME `Namespace.ID` for the SAME photo id,
/// so the cell's outer frame can morph between its strip-square position and
/// its grid-slot position. Applied to the cell's OUTER frame in
/// `PhotoThumbnailCell.body`, not to the inner image — that's the difference
/// between "inner image bounds wiggle" and "whole cell shifts across the
/// layout swap".
///
/// We rely on the editor swapping strip and grid via `if/else` (NOT a ZStack
/// with both subtrees mounted), which means at most one matched view exists
/// per id at any moment — so `isSource` defaults to `true` and no plumbing
/// is needed. SwiftUI snapshots the source's bounds at unmount time and
/// animates the destination from those bounds to its natural bounds inside
/// the same `withAnimation` that drives the swap.
struct MatchedPhotoModifier: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content
                .matchedGeometryEffect(id: id, in: namespace)
                .onAppear { thumbnailSignposter.emitEvent("MatchedApplied") }
        } else {
            content
                .onAppear { thumbnailSignposter.emitEvent("MatchedPassthrough") }
        }
    }
}

import os
import SwiftUI

private let stripSignposter = OSSignposter(subsystem: "social.grain.grain", category: "Animation.Strip")

// MARK: - Wallet-style removal transition

private struct WalletRemoveModifier: ViewModifier {
    let isRemoving: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(isRemoving ? 0.5 : 1, anchor: .center)
            .offset(y: isRemoving ? -20 : 0)
            .opacity(isRemoving ? 0 : 1)
    }
}

private extension AnyTransition {
    static var walletRemove: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.85).combined(with: .opacity),
            removal: .modifier(
                active: WalletRemoveModifier(isRemoving: true),
                identity: WalletRemoveModifier(isRemoving: false)
            )
        )
    }
}

// MARK: - PhotoStrip

/// Read-only horizontal strip of square photo thumbnails. Tap a cell to select,
/// tap its X to delete. The strip has no reorder gesture — reordering lives
/// exclusively in the grid ("Reorder" mode) to keep the two modes distinct per
/// HIG modality guidance. Because the strip has no drag state, it doesn't need
/// to expose an `isReordering` binding or lock its scroll via ScrollPanLocker.
struct PhotoStrip: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    /// Shared matched-geometry namespace for the photo view inside each cell.
    var matchedNamespace: Namespace.ID?
    /// True for the duration of the strip↔grid mode swap.
    var isAnimatingMode: Bool = false
    var sendExif: Bool = true
    var onTapped: ((UUID) -> Void)?

    /// Drives `.scrollPosition(id:)` so the ScrollView initializes at the
    /// selected photo on first render — before matchedGeometryEffect captures
    /// destination frames. Using `State(initialValue:)` set in `init` means
    /// the scroll offset is already correct on the very first layout pass,
    /// which is the only pass that matters for the matched-geometry animation.
    /// `onAppear` + `proxy.scrollTo` fires AFTER layout/preference-capture,
    /// too late to affect the animation's destination positions.
    @State private var scrollID: UUID?

    private let thumbSize: CGFloat = 72
    private let spacing: CGFloat = 20
    private let verticalPadding: CGFloat = 22
    private let horizontalPadding: CGFloat = 24

    init(
        items: Binding<[PhotoItem]>,
        selectedPhotoID: Binding<UUID?>,
        matchedNamespace: Namespace.ID? = nil,
        isAnimatingMode: Bool = false,
        sendExif: Bool = true,
        onTapped: ((UUID) -> Void)? = nil
    ) {
        _items = items
        _selectedPhotoID = selectedPhotoID
        // Pre-seed scroll position to the currently-selected photo so the
        // strip mounts already centered on it. When the strip is the morph
        // destination (grid/captions → preview), this means
        // matchedGeometryEffect captures destination cell frames at their
        // FINAL resting positions on the first layout pass — no two-phase
        // morph-then-scroll snap after the animation completes. Reading
        // the binding's wrappedValue in init is safe: @State is only
        // initialized once, and subsequent changes to selectedPhotoID are
        // handled by the .onChange(of: selectedPhotoID) handler below.
        _scrollID = State(initialValue: selectedPhotoID.wrappedValue)
        self.matchedNamespace = matchedNamespace
        self.isAnimatingMode = isAnimatingMode
        self.sendExif = sendExif
        self.onTapped = onTapped
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                // ForEach($items) for safe per-id Bindings — avoids the
                // pre-existing `items[0]` crash when items is briefly empty
                // mid-delete.
                ForEach($items) { $item in
                    let id = item.id
                    let exifState: ExifState = {
                        guard item.exifSummary != nil else { return .absent }
                        return sendExif ? .active : .inactive
                    }()
                    PhotoThumbnailCell(
                        item: $item,
                        geometry: CellGeometry(
                            mode: .preview,
                            maskSide: thumbSize,
                            photoAspect: item.naturalAspect
                        ),
                        isSelected: selectedPhotoID == id,
                        exifState: exifState,
                        matchedNamespace: matchedNamespace,
                        onTap: {
                            onTapped?(id)
                            // Drive scrollID directly here with animation so the
                            // scroll is smooth on tap. onChange fires afterwards
                            // but scrollID is already the new value → no-op.
                            // onChange does NOT inherit a parent transaction, so
                            // we can't rely on it for animation — drive the
                            // source directly instead.
                            stripSignposter.emitEvent("ScrollTap", "scrollWasNil=\(scrollID == nil),animatingMode=\(isAnimatingMode)")
                            withAnimation(.snappy) {
                                scrollID = id
                                selectedPhotoID = id
                            }
                        },
                        onDelete: { handleDelete(itemID: id) }
                    )
                    .id(id)
                    // During mode transitions matched-geometry drives the
                    // morph; walletRemove's scale(0.85) insertion and
                    // scale(0.5)+offset removal compete with matched-geometry
                    // and distort the perceived screen-space origin/destination
                    // of each cell. Gating on isAnimatingMode suppresses
                    // walletRemove inside mode morphs but preserves it for
                    // real deletions (where isAnimatingMode is false).
                    .transition(isAnimatingMode ? .identity : .walletRemove)
                }
            }
            .padding(.vertical, verticalPadding)
            // Horizontal space lives in contentMargins (not HStack padding) so
            // the scroll view enforces it as a hard boundary — the first and last
            // photos can never be dragged flush to the edge. With plain .padding
            // the leading gap is part of the content; UIScrollView will happily
            // scroll past it to contentOffset = horizontalPadding, eating the
            // margin. contentMargins maps to UIScrollView.contentInset, which
            // clamps the natural rest position to the margin.
        }
        // scrollPosition(id:) initializes the scroll offset to the selected
        // photo before the first layout pass, so matched-geometry captures
        // destination frames at the correct positions. This replaces the old
        // onAppear + proxy.scrollTo approach, which fired too late (after
        // preference-key propagation) to influence the animation's targets.
        .scrollPosition(id: $scrollID, anchor: .center)
        .contentMargins(.trailing, horizontalPadding / 8, for: .scrollContent)
        .scrollClipDisabled()
        .frame(height: thumbSize + verticalPadding * 2)
        // Diagnostic: fires whenever UIScrollView's content offset or
        // content size changes. In Instruments (subsystem
        // social.grain.grain, category Animation.Strip) you can correlate
        // these events against MorphAnimation intervals — if offset/size
        // are still changing AFTER a MorphAnimation has ended, the strip's
        // UIScrollView is doing async layout catchup and matched-geometry
        // destinations were captured too early.
        .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, geo in
            stripSignposter.emitEvent(
                "ScrollGeometry",
                "offsetX=\(Int(geo.contentOffset.x.rounded())),offsetY=\(Int(geo.contentOffset.y.rounded())),contentW=\(Int(geo.contentSize.width.rounded())),containerW=\(Int(geo.containerSize.width.rounded()))"
            )
        }
        .onChange(of: isAnimatingMode) { _, animating in
            guard animating else { return }
            // Strip is about to unmount into grid/captions mode. FORCE a
            // synchronous scroll-to-start (no withAnimation) so every cell
            // sits at a correct POSITIVE-x global position when matched-
            // geometry captures the morph source frames. Without this, a
            // user-scrolled strip has items 1-3 at NEGATIVE x coordinates
            // (still rendered because of scrollClipDisabled), so matched-
            // geometry snapshots their source positions as off-screen-left.
            //
            // The POST-morph scroll branch that used to live here has been
            // removed: the strip's init now pre-seeds scrollID from
            // selectedPhotoID, so when the strip mounts fresh as the morph
            // destination it is already centered on the selected photo. No
            // second-phase scroll snap is needed.
            stripSignposter.emitEvent("ScrollPreMorphReset", "items=\(items.count)")
            scrollID = items.first?.id
        }
        .onChange(of: selectedPhotoID) { _, newID in
            // Skip during mode transitions — the TabView inside the carousel
            // can briefly reset selectedPhotoID on mount, which would fire a
            // spurious scroll-to-center mid-morph.
            guard !isAnimatingMode else { return }
            // Skip if scrollID already matches — tap and delete drive scrollID
            // directly with .snappy before this onChange fires. Setting the
            // same value here without animation cancels the in-flight spring
            // even though @State does value equality: scrollPosition(id:)'s
            // Binding.set flushes to UIScrollView regardless, resetting the
            // animation to an instant jump.
            guard scrollID != newID else { return }
            // Carousel-swipe fallback: no animation so the strip snaps
            // instantly as the page settles (spring-on-spring feels wrong).
            stripSignposter.emitEvent("ScrollCarouselFallback", "newIDNil=\(newID == nil),animatingMode=\(isAnimatingMode)")
            scrollID = newID
        }
    }

    // MARK: - Delete logic

    /// When deleting the selected photo: prefer the previous index, fall back
    /// to next, fall back to nil. When deleting a non-selected photo: leave
    /// selection unchanged.
    private func handleDelete(itemID: UUID) {
        let prevScrollID = scrollID
        let state = stripSignposter.beginInterval("ScrollDelete", id: stripSignposter.makeSignpostID(), "isSelected=\(selectedPhotoID == itemID),animatingMode=\(isAnimatingMode)")
        if selectedPhotoID == itemID,
           let removedIdx = items.firstIndex(where: { $0.id == itemID })
        {
            let newID: UUID? = removedIdx > 0
                ? items[removedIdx - 1].id
                : removedIdx < items.count - 1 ? items[removedIdx + 1].id : nil
            selectedPhotoID = newID
            // Drive scrollID directly (same pattern as onTap) so the strip
            // scrolls to the adjacent photo before the removal animation plays.
            withAnimation(.snappy) { scrollID = newID }
        }
        withAnimation(.smooth) {
            items.removeAll { $0.id == itemID }
        }
        stripSignposter.endInterval("ScrollDelete", state, "scrollChanged=\(scrollID != prevScrollID)")
    }
}

#Preview {
    @Previewable @State var state: [PhotoItem] = Array(PreviewData.photoItems.prefix(5))
    @Previewable @State var selected: UUID?
    PhotoStrip(items: $state, selectedPhotoID: $selected)
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { selected = state.last?.id }
        .grainPreview()
}

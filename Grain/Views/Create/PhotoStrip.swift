import SwiftUI

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
        // Start at scroll offset 0 (nil) so the strip always mounts with
        // photos 1-3 visible at positive x coordinates. matchedGeometryEffect
        // captures destination frames on the first layout pass — if the scroll
        // were pre-set to a later photo, photos 1-3 would be at negative x
        // (off-screen left) and their morph would start from the wrong position.
        // After isAnimatingMode drops to false the onChange below scrolls to
        // the selected photo, keeping the two-phase motion (morph → then scroll).
        _scrollID = State(initialValue: nil)
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
                        cameraName: item.exifSummary?.camera,
                        matchedNamespace: matchedNamespace,
                        onTap: {
                            onTapped?(id)
                            // Drive scrollID directly here with animation so the
                            // scroll is smooth on tap. onChange fires afterwards
                            // but scrollID is already the new value → no-op.
                            // onChange does NOT inherit a parent transaction, so
                            // we can't rely on it for animation — drive the
                            // source directly instead.
                            withAnimation(.snappy) {
                                scrollID = id
                                selectedPhotoID = id
                            }
                        },
                        onDelete: { handleDelete(itemID: id) }
                    )
                    .id(id)
                    .transition(.walletRemove)
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
        .contentMargins(.leading, horizontalPadding - 22, for: .scrollContent)
        .contentMargins(.trailing, horizontalPadding + 2, for: .scrollContent)
        .scrollClipDisabled()
        .frame(height: thumbSize + verticalPadding * 2)
        .onChange(of: isAnimatingMode) { _, animating in
            // When the strip↔grid morph finishes, scroll to the selected photo.
            // The strip intentionally mounts at offset 0 (scrollID = nil) so
            // that photos 1-3 are at correct global positions when matched-
            // geometry captures destination frames. This deferred scroll is the
            // second phase: after cells land in their strip positions, the strip
            // smoothly pans to bring the selected photo into view.
            guard !animating, let id = selectedPhotoID else { return }
            withAnimation(.snappy) { scrollID = id }
        }
        .onChange(of: selectedPhotoID) { _, newID in
            // Skip during mode transitions — the TabView inside the carousel
            // can briefly reset selectedPhotoID on mount, which would fire a
            // spurious scroll-to-center mid-morph.
            guard !isAnimatingMode else { return }
            // No animation — this path is the carousel-swipe fallback only.
            // Tap and delete drive scrollID directly with .snappy so they
            // don't land here needing animation. Instant scroll on swipe
            // avoids a spring conflicting with TabView's page-settle.
            scrollID = newID
        }
    }

    // MARK: - Delete logic

    /// When deleting the selected photo: prefer the previous index, fall back
    /// to next, fall back to nil. When deleting a non-selected photo: leave
    /// selection unchanged.
    private func handleDelete(itemID: UUID) {
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
    }
}

#Preview {
    @Previewable @State var state: [PhotoItem] = PreviewData.photoItems
    @Previewable @State var selected: UUID?
    PhotoStrip(items: $state, selectedPhotoID: $selected)
        .padding()
        .onAppear { selected = state.first?.id }
        .preferredColorScheme(.dark)
}

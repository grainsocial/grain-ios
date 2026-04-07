import SwiftUI

/// 3-column LazyVGrid using the same custom SwiftUI gesture as the strip (works in
/// Form rows where system .draggable doesn't). Drag math is 2D — the dragged cell
/// follows the finger via .offset, and during the drag we compute the proposed slot
/// LIVE from the finger's translation, shifting siblings to make room. Items[] is
/// mutated exactly once on release.
struct ReorderablePhotoGrid: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    /// Hoisted up to CreateGalleryView so the Form can apply .scrollDisabled when
    /// a cell is picked up. Set to true in beginDrag, false in resetDragState.
    /// Deliberately gated on the picked-up state, NOT on the 0.18s arming window —
    /// we don't want scroll to hitch during the "maybe a tap" period.
    @Binding var isReordering: Bool
    /// Shared matched-geometry namespace for the photo view inside each cell.
    /// Passed down so strip and grid renderings of the same photo share geometry
    /// IDs — prep for the future strip↔grid transition.
    var matchedNamespace: Namespace.ID?
    /// True for the duration of the strip↔grid mode swap. Currently unused
    /// at the cell level (X buttons stay visible during the morph so they
    /// can ride the matched-geometry transition with the cell, per user
    /// feedback that the disappear/reappear was jarring). Kept on the API
    /// for the editor's convenience and in case future work needs it back.
    var isAnimatingMode: Bool = false

    @State private var draggedID: UUID?
    @State private var dragStartIndex: Int?
    @State private var dragCurrentIndex: Int?
    @State private var dragOffset: CGSize = .zero
    @State private var containerWidth: CGFloat = 320

    private let columnCount: Int = 3
    /// Bumped to give the X button overflow room. Each cell's X is offset (14, -14)
    /// outside the cell — the spacing here makes that overflow visible.
    private let spacing: CGFloat = 28
    private let outerPadding: CGFloat = 16

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: spacing, alignment: .center),
            count: columnCount
        )
    }

    /// Side length of each grid cell. With the new mask architecture, every
    /// grid cell is a uniform square of column width — the photo letterboxes
    /// inside the square at its natural aspect, with the mask sized to fully
    /// contain the photo. Uniform squares simplify drag math (no more
    /// per-row averaging) and remove a class of jitter that variable-height
    /// LazyVGrid rows used to introduce when items reordered across rows.
    private var cellSide: CGFloat {
        let total = max(0, containerWidth - outerPadding * 2 - spacing * CGFloat(columnCount - 1))
        return total / CGFloat(columnCount)
    }

    /// Stride between adjacent slots: one cell side plus the inter-cell
    /// spacing. Same value for both axes since cells are uniform squares.
    private var stride: CGSize {
        CGSize(width: cellSide + spacing, height: cellSide + spacing)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            // ForEach($items) gives us a Binding<PhotoItem> per-id directly, with no
            // unsafe `items[0]` fallback. Necessary because the previous bindingFor
            // helper crashes when items briefly becomes empty during a delete.
            ForEach($items) { $item in
                let id = item.id
                PhotoThumbnailCell(
                    item: $item,
                    geometry: CellGeometry(
                        mode: .reorder,
                        maskSide: cellSide,
                        photoAspect: aspect(of: item)
                    ),
                    isSelected: selectedPhotoID == id,
                    isDragging: draggedID == id,
                    matchedNamespace: matchedNamespace,
                    onTap: {
                        guard draggedID != id else { return }
                        selectedPhotoID = id
                    },
                    onDelete: { handleDelete(itemID: id) }
                )
                .id(id)
                // .zIndex BEFORE the offset/geometryGroup so the picked-up
                // cell wins z-order against ALL other cells (including those
                // drawn after it in the LazyVGrid's row-order pass), not just
                // siblings within its current row. The big number is
                // intentional — LazyVGrid's row-order draw can stack later
                // rows on top, and `.zIndex(1)` was getting beaten by a few
                // implicit row-level stacks.
                .zIndex(draggedID == id ? 1000 : 0)
                .offset(slotShift(for: item))
                .geometryGroup()
                // UIKit-backed long-press-drag (see ReorderRecognizer). The
                // SwiftUI .simultaneousGesture(LongPress.sequenced(Drag)) we used
                // before silently broke vertical Form scroll AND inner taps on
                // real hardware.
                .gesture(
                    ReorderRecognizer { phase, translation in
                        handleReorder(phase: phase, translation: translation, itemID: id)
                    }
                )
            }
        }
        .padding(.horizontal, outerPadding)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { containerWidth = $0 }
    }

    /// Per-cell visual offset during a drag. The dragged cell follows the finger;
    /// siblings between dragStartIndex and dragCurrentIndex shift one slot in the
    /// opposite direction (in flattened 1D order, mapped back to 2D). Cells crossing
    /// row boundaries wrap visually to the next/previous row's start/end.
    private func slotShift(for item: PhotoItem) -> CGSize {
        guard let draggedID,
              let start = dragStartIndex,
              let current = dragCurrentIndex,
              let index = items.firstIndex(where: { $0.id == item.id })
        else { return .zero }

        if item.id == draggedID {
            return dragOffset
        }

        let slotShift: Int
        if current > start, index > start, index <= current {
            slotShift = -1
        } else if current < start, index >= current, index < start {
            slotShift = 1
        } else {
            return .zero
        }

        // Convert 1D slot delta to (col, row) delta in the grid layout. Wrapping at
        // row boundaries gives a visual jump (cell flies from end-of-row to
        // start-of-next-row), which matches the underlying flattened-order semantics.
        let oldRow = index / columnCount
        let oldCol = index % columnCount
        let newIdx = index + slotShift
        let newRow = newIdx / columnCount
        let newCol = newIdx % columnCount
        let xDelta = CGFloat(newCol - oldCol) * stride.width
        let yDelta = CGFloat(newRow - oldRow) * stride.height
        return CGSize(width: xDelta, height: yDelta)
    }

    private func handleReorder(
        phase: ReorderRecognizer.Phase,
        translation: CGSize,
        itemID: UUID
    ) {
        switch phase {
        case .began:
            beginDrag(itemID: itemID)
        case .changed:
            handleDragChanged(translation: translation)
        case .ended, .cancelled:
            handleDragEnded()
        }
    }

    private func beginDrag(itemID: UUID) {
        guard draggedID == nil,
              let idx = items.firstIndex(where: { $0.id == itemID })
        else { return }
        draggedID = itemID
        dragStartIndex = idx
        dragCurrentIndex = idx
        isReordering = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func handleDragChanged(translation: CGSize) {
        guard let start = dragStartIndex, stride.width > 0, stride.height > 0 else { return }
        dragOffset = translation

        // Compute the proposed target index from the finger's translation in row/col
        // units. Each (cellSide + spacing) is one column step; with uniform
        // square cells the row stride is the same value.
        let colDelta = Int((dragOffset.width / stride.width).rounded())
        let rowDelta = Int((dragOffset.height / stride.height).rounded())

        let startRow = start / columnCount
        let startCol = start % columnCount
        let proposedRow = max(0, startRow + rowDelta)
        let proposedCol = max(0, min(columnCount - 1, startCol + colDelta))
        let rawProposed = proposedRow * columnCount + proposedCol
        let proposed = max(0, min(items.count - 1, rawProposed))

        if proposed != dragCurrentIndex {
            // Longer spring than .snappy so siblings glide into place visibly.
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                dragCurrentIndex = proposed
            }
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func handleDragEnded() {
        guard let start = dragStartIndex,
              let current = dragCurrentIndex
        else {
            resetDragState()
            return
        }

        withAnimation(.snappy) {
            if start != current {
                items.move(
                    fromOffsets: IndexSet(integer: start),
                    toOffset: current > start ? current + 1 : current
                )
            }
            dragOffset = .zero
            dragStartIndex = nil
            dragCurrentIndex = nil
            isReordering = false
        } completion: {
            // Defer z-index reset so the picked-up cell stays on top for the
            // full snap-back animation instead of dipping behind siblings.
            draggedID = nil
        }
    }

    private func resetDragState() {
        draggedID = nil
        dragStartIndex = nil
        dragCurrentIndex = nil
        isReordering = false
    }

    /// Photo's natural aspect (w/h) used to build CellGeometry. Mirrors the
    /// `naturalAspect` calc in PhotoStrip.
    private func aspect(of item: PhotoItem) -> CGFloat {
        let w = item.thumbnail.size.width
        let h = item.thumbnail.size.height
        guard h > 0 else { return 1 }
        return w / h
    }

    private func handleDelete(itemID: UUID) {
        if selectedPhotoID == itemID,
           let removedIdx = items.firstIndex(where: { $0.id == itemID })
        {
            if removedIdx > 0 {
                selectedPhotoID = items[removedIdx - 1].id
            } else if removedIdx < items.count - 1 {
                selectedPhotoID = items[removedIdx + 1].id
            } else {
                selectedPhotoID = nil
            }
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            items.removeAll { $0.id == itemID }
        }
    }
}

#Preview {
    @Previewable @State var state: [PhotoItem] = PreviewData.photoItems
    @Previewable @State var selected: UUID?
    @Previewable @State var reordering = false
    ScrollView {
        ReorderablePhotoGrid(
            items: $state,
            selectedPhotoID: $selected,
            isReordering: $reordering
        )
    }
    .onAppear { selected = state.first?.id }
    .preferredColorScheme(.dark)
}

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

    @State private var draggedID: UUID?
    @State private var dragStartIndex: Int?
    @State private var dragCurrentIndex: Int?
    @State private var dragOffset: CGSize = .zero
    @State private var containerWidth: CGFloat = 0

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

    private var cellWidth: CGFloat {
        let total = max(0, containerWidth - outerPadding * 2 - spacing * CGFloat(columnCount - 1))
        return total / CGFloat(columnCount)
    }

    /// Each cell sizes itself to its photo's natural aspect at column width, so
    /// rows have variable heights. For the drag-stride calculation we need a
    /// single "how far is the next row?" number — we use the average actual row
    /// height (sum of each row's max cell height, divided by row count). Close
    /// enough for reorder snapping without per-row hit-testing state. Not exact
    /// for heterogeneous galleries; good enough to feel right until we iterate.
    private var averageRowHeight: CGFloat {
        guard cellWidth > 0, !items.isEmpty else { return cellWidth }
        var rowHeights: [CGFloat] = []
        var i = 0
        while i < items.count {
            let rowEnd = min(i + columnCount, items.count)
            var rowMax: CGFloat = 0
            for j in i ..< rowEnd {
                let w = items[j].thumbnail.size.width
                let h = items[j].thumbnail.size.height
                guard h > 0, w > 0 else { continue }
                let cellH = cellWidth * h / w
                rowMax = max(rowMax, cellH)
            }
            if rowMax > 0 {
                rowHeights.append(rowMax)
            }
            i = rowEnd
        }
        guard !rowHeights.isEmpty else { return cellWidth }
        return rowHeights.reduce(0, +) / CGFloat(rowHeights.count)
    }

    private var stride: CGSize {
        CGSize(width: cellWidth + spacing, height: averageRowHeight + spacing)
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
                    mode: .grid,
                    isSelected: selectedPhotoID == id,
                    isDragging: draggedID == id,
                    // All Xs always visible — z-order on the dragged cell handles
                    // the "X is below the picked-up photo" effect via covering.
                    hideDelete: false,
                    matchedNamespace: matchedNamespace,
                    onTap: {
                        guard draggedID != id else { return }
                        selectedPhotoID = id
                    },
                    onDelete: { handleDelete(itemID: id) }
                )
                .id(id)
                .offset(slotShift(for: item))
                .geometryGroup()
                .zIndex(draggedID == id ? 1 : 0)
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
        .padding(.vertical, 12)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in containerWidth = newValue }
            }
        )
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
        // units. Each (cellWidth + spacing) is one column step; each
        // (cellHeight + spacing) is one row step.
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

        if start != current {
            withAnimation(.snappy) {
                items.move(
                    fromOffsets: IndexSet(integer: start),
                    toOffset: current > start ? current + 1 : current
                )
            }
        }

        withAnimation(.snappy) {
            dragOffset = .zero
        }
        resetDragState()
    }

    private func resetDragState() {
        draggedID = nil
        dragStartIndex = nil
        dragCurrentIndex = nil
        isReordering = false
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
        items.removeAll { $0.id == itemID }
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

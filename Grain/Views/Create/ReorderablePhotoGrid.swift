import SwiftUI

/// 3-column LazyVGrid using the same custom SwiftUI gesture as the strip (works in
/// Form rows where system .draggable doesn't). Drag math is 2D — the dragged cell
/// follows the finger via .offset, and during the drag we compute the proposed slot
/// LIVE from the finger's translation, shifting siblings to make room. Items[] is
/// mutated exactly once on release.
struct ReorderablePhotoGrid: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?

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

    /// Slot height is driven by the *most-portrait* photo in the gallery (the one
    /// with the smallest W/H ratio). At slot width, that photo's natural-aspect height
    /// is `cellWidth / minAspect`, which becomes the slot height for every cell.
    /// Effect: the most portrait photo fills its slot exactly; every other photo is
    /// aspect-fit (letterboxed top/bottom) inside the same uniform slot. This mirrors
    /// the carousel's per-photo size scaled down by `cellWidth / carouselWidth`, since
    /// the grid container width ≈ the carousel width.
    private var cellHeight: CGFloat {
        let aspects = items.map { item -> CGFloat in
            let w = item.thumbnail.size.width
            let h = item.thumbnail.size.height
            return h > 0 ? w / h : 1
        }
        let minAspect = aspects.min() ?? 1
        // Clamp the minimum aspect so we don't end up with absurdly tall slots when
        // someone uploads an extreme panorama portrait. 0.5 (2:4 vertical) is a sane
        // floor — taller than that and we just letterbox the offender.
        let safeMinAspect = max(minAspect, 0.5)
        return cellWidth / safeMinAspect
    }

    private var stride: CGSize {
        CGSize(width: cellWidth + spacing, height: cellHeight + spacing)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(items) { item in
                PhotoThumbnailCell(
                    item: bindingFor(itemID: item.id),
                    mode: .slot(CGSize(width: cellWidth, height: cellHeight)),
                    isSelected: selectedPhotoID == item.id,
                    // All Xs always visible — z-order on the dragged cell handles
                    // the "X is below the picked-up photo" effect via covering.
                    hideDelete: false,
                    onTap: {
                        guard draggedID == nil else { return }
                        selectedPhotoID = item.id
                    },
                    onDelete: { handleDelete(item: item) }
                )
                .id(item.id)
                .offset(slotShift(for: item))
                .geometryGroup()
                .zIndex(draggedID == item.id ? 1 : 0)
                // UIKit-backed long-press-drag (see ReorderRecognizer). The
                // SwiftUI .simultaneousGesture(LongPress.sequenced(Drag)) we used
                // before silently broke vertical Form scroll AND inner taps on
                // real hardware.
                .gesture(
                    ReorderRecognizer { phase, translation in
                        handleReorder(phase: phase, translation: translation, item: item)
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
        item: PhotoItem
    ) {
        switch phase {
        case .began:
            beginDrag(item: item)
        case .changed:
            handleDragChanged(translation: translation)
        case .ended, .cancelled:
            handleDragEnded()
        }
    }

    private func beginDrag(item: PhotoItem) {
        guard draggedID == nil,
              let idx = items.firstIndex(where: { $0.id == item.id })
        else { return }
        draggedID = item.id
        dragStartIndex = idx
        dragCurrentIndex = idx
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
    }

    private func handleDelete(item: PhotoItem) {
        let removedID = item.id
        if selectedPhotoID == removedID,
           let removedIdx = items.firstIndex(where: { $0.id == removedID })
        {
            if removedIdx > 0 {
                selectedPhotoID = items[removedIdx - 1].id
            } else if removedIdx < items.count - 1 {
                selectedPhotoID = items[removedIdx + 1].id
            } else {
                selectedPhotoID = nil
            }
        }
        items.removeAll { $0.id == removedID }
    }

    private func bindingFor(itemID: UUID) -> Binding<PhotoItem> {
        Binding(
            get: { items.first(where: { $0.id == itemID }) ?? items[0] },
            set: { newValue in
                if let idx = items.firstIndex(where: { $0.id == itemID }) {
                    items[idx] = newValue
                }
            }
        )
    }
}

#Preview {
    @Previewable @State var state: [PhotoItem] = PreviewData.photoItems
    @Previewable @State var selected: UUID?
    ScrollView {
        ReorderablePhotoGrid(items: $state, selectedPhotoID: $selected)
    }
    .onAppear { selected = state.first?.id }
    .preferredColorScheme(.dark)
}

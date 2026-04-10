import SwiftUI
import UIKit

// MARK: - Reorder drag state

/// Manages drag-to-reorder state for the photo grid. Extracted from
/// ReorderablePhotoGrid so the state is owned by PhotoEditor and the
/// AdaptivePhotoLayout can read it for cell displacement.
@Observable
@MainActor
final class ReorderDragState {
    var draggedID: UUID?
    var dragStartIndex: Int?
    var dragCurrentIndex: Int?
    var dragOffset: CGSize = .zero

    @ObservationIgnored var impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    @ObservationIgnored var selectionGenerator = UISelectionFeedbackGenerator()

    var isDragging: Bool {
        draggedID != nil
    }

    func beginDrag(itemID: UUID, at index: Int) {
        guard draggedID == nil else { return }
        draggedID = itemID
        dragStartIndex = index
        dragCurrentIndex = index
        impactGenerator.prepare()
        selectionGenerator.prepare()
        impactGenerator.impactOccurred()
    }

    func handleDragChanged(
        translation: CGSize,
        itemCount: Int,
        columnCount: Int,
        stride: CGSize
    ) {
        guard let start = dragStartIndex,
              stride.width > 0, stride.height > 0
        else { return }
        dragOffset = translation

        let colDelta = Int((dragOffset.width / stride.width).rounded())
        let rowDelta = Int((dragOffset.height / stride.height).rounded())

        let startRow = start / columnCount
        let startCol = start % columnCount
        let proposedRow = max(0, startRow + rowDelta)
        let proposedCol = max(0, min(columnCount - 1, startCol + colDelta))
        let rawProposed = proposedRow * columnCount + proposedCol
        let proposed = max(0, min(itemCount - 1, rawProposed))

        if proposed != dragCurrentIndex {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                dragCurrentIndex = proposed
            }
            selectionGenerator.selectionChanged()
        }
    }

    func reset() {
        draggedID = nil
        dragStartIndex = nil
        dragCurrentIndex = nil
        dragOffset = .zero
    }
}

// MARK: - Drag placement snapshot

/// Lightweight value snapshot of drag state for the Layout. Using a struct
/// (not the @Observable directly) keeps the Layout as pure value-type math.
struct ReorderDragPlacement: Equatable {
    let draggedIndex: Int
    let currentIndex: Int
    let dragOffset: CGSize
}

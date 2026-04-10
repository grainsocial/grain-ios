import SwiftUI
import UIKit

// MARK: - Reorder drag state

/// Manages drag-to-reorder state for the photo grid. Extracted from
/// ReorderablePhotoGrid so the state is owned by GalleryEditor and the
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

    /// Updates `dragOffset` and returns the proposed slot index if it changed.
    /// The caller is responsible for wrapping `dragCurrentIndex` assignment in
    /// `withAnimation` — calling `withAnimation` from inside @Observable methods
    /// doesn't reliably propagate animation transactions to the Layout after the
    /// first update, causing subsequent slot changes to snap instead of animate.
    @discardableResult
    func handleDragChanged(
        translation: CGSize,
        itemCount: Int,
        columnCount: Int,
        stride: CGSize
    ) -> Int? {
        guard let start = dragStartIndex,
              stride.width > 0, stride.height > 0
        else { return nil }
        dragOffset = translation

        let colDelta = Int((translation.width / stride.width).rounded())
        let rowDelta = Int((translation.height / stride.height).rounded())

        let startRow = start / columnCount
        let startCol = start % columnCount
        let proposedRow = max(0, startRow + rowDelta)
        let proposedCol = max(0, min(columnCount - 1, startCol + colDelta))
        let rawProposed = proposedRow * columnCount + proposedCol
        let proposed = max(0, min(itemCount - 1, rawProposed))

        guard proposed != dragCurrentIndex else { return nil }
        return proposed
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
///
/// `dragOffset` is intentionally excluded — it is applied as a view-level
/// `.offset` modifier on the dragged cell, not through the Layout. This keeps
/// the Layout parameter clean: it only changes when `currentIndex` changes
/// (inside `withAnimation`), so SwiftUI can animate sibling displacements
/// without the immediate dragOffset update contaminating the transaction.
struct ReorderDragPlacement: Equatable {
    let draggedIndex: Int
    let currentIndex: Int
}

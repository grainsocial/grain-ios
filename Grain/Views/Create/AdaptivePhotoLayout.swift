import SwiftUI

// MARK: - Layout value key

/// Each cell tags itself with its array index so the Layout knows
/// which subview to place at which position.
struct PhotoIndexKey: LayoutValueKey {
    static let defaultValue: Int = 0
}

// MARK: - Adaptive photo layout

/// Single Layout that places photo cells in three modes: horizontal strip,
/// 3-column grid, or vertical captions list. When `mode` changes inside
/// `withAnimation`, SwiftUI interpolates each subview's position/size from
/// old to new — no matchedGeometryEffect, no conditional view swaps.
struct AdaptivePhotoLayout: Layout {
    var mode: EditorMode
    var containerWidth: CGFloat
    var stripScrollOffset: CGFloat = 0
    var dragPlacement: ReorderDragPlacement?

    // Strip — values must match StripScrollState.thumbSize / .spacing
    private let stripThumbSize: CGFloat = 72
    private let stripSpacing: CGFloat = 20
    private let stripVerticalPadding: CGFloat = 22

    // Grid
    private let gridColumnCount = 3
    private let gridSpacing: CGFloat = 4
    private let gridOuterPadding: CGFloat = 16
    private let gridTopPadding: CGFloat = 22
    private let gridBottomPadding: CGFloat = 12

    // Captions
    private let captionsHorizontalPadding: CGFloat = 16
    private let captionsVerticalPadding: CGFloat = 10

    private var gridCellSide: CGFloat {
        let total = max(0, containerWidth - gridOuterPadding * 2 - gridSpacing * CGFloat(gridColumnCount - 1))
        return max(1, total / CGFloat(gridColumnCount))
    }

    private var gridStride: CGFloat {
        gridCellSide + gridSpacing
    }

    // MARK: - Layout protocol

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        let width = proposal.width ?? containerWidth
        guard !subviews.isEmpty else { return CGSize(width: width, height: 0) }

        switch mode {
        case .preview:
            return CGSize(width: width, height: stripThumbSize + stripVerticalPadding * 2)

        case .reorder:
            let rows = Int(ceil(Double(subviews.count) / Double(gridColumnCount)))
            let height = CGFloat(rows) * gridCellSide
                + CGFloat(max(0, rows - 1)) * gridSpacing
                + gridTopPadding + gridBottomPadding
            return CGSize(width: width, height: height)

        case .captions:
            var height: CGFloat = 0
            let rowWidth = max(0, width - captionsHorizontalPadding * 2)
            let rowProposal = ProposedViewSize(width: rowWidth, height: nil)
            for subview in subviews {
                let size = subview.sizeThatFits(rowProposal)
                height += size.height + captionsVerticalPadding * 2
            }
            return CGSize(width: width, height: height)
        }
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        switch mode {
        case .preview: placeAsStrip(in: bounds, subviews: subviews)
        case .reorder: placeAsGrid(in: bounds, subviews: subviews)
        case .captions: placeAsCaptions(in: bounds, subviews: subviews)
        }
    }

    // MARK: - Strip placement

    private func placeAsStrip(in bounds: CGRect, subviews: Subviews) {
        let proposal = ProposedViewSize(width: stripThumbSize, height: stripThumbSize)
        let centerY = bounds.midY
        for subview in subviews {
            let index = subview[PhotoIndexKey.self]
            let x = bounds.minX + stripScrollOffset
                + CGFloat(index) * (stripThumbSize + stripSpacing)
                + stripThumbSize / 2
            subview.place(at: CGPoint(x: x, y: centerY), anchor: .center, proposal: proposal)
        }
    }

    // MARK: - Grid placement

    private func placeAsGrid(in bounds: CGRect, subviews: Subviews) {
        let proposal = ProposedViewSize(width: gridCellSide, height: gridCellSide)
        for subview in subviews {
            let index = subview[PhotoIndexKey.self]
            let col = index % gridColumnCount
            let row = index / gridColumnCount

            var offsetX: CGFloat = 0
            var offsetY: CGFloat = 0

            if let drag = dragPlacement {
                if index == drag.draggedIndex {
                    offsetX = drag.dragOffset.width
                    offsetY = drag.dragOffset.height
                } else {
                    let slotDelta: Int = if drag.currentIndex > drag.draggedIndex,
                                            index > drag.draggedIndex, index <= drag.currentIndex
                    {
                        -1
                    } else if drag.currentIndex < drag.draggedIndex,
                              index >= drag.currentIndex, index < drag.draggedIndex
                    {
                        1
                    } else {
                        0
                    }

                    if slotDelta != 0 {
                        let newIdx = index + slotDelta
                        let newRow = newIdx / gridColumnCount
                        let newCol = newIdx % gridColumnCount
                        offsetX = CGFloat(newCol - col) * gridStride
                        offsetY = CGFloat(newRow - row) * gridStride
                    }
                }
            }

            let x = bounds.minX + gridOuterPadding
                + CGFloat(col) * gridStride + gridCellSide / 2 + offsetX
            let y = bounds.minY + gridTopPadding
                + CGFloat(row) * gridStride + gridCellSide / 2 + offsetY
            subview.place(at: CGPoint(x: x, y: y), anchor: .center, proposal: proposal)
        }
    }

    // MARK: - Captions placement

    private func placeAsCaptions(in bounds: CGRect, subviews: Subviews) {
        var y = bounds.minY
        let rowWidth = max(0, bounds.width - captionsHorizontalPadding * 2)
        let rowProposal = ProposedViewSize(width: rowWidth, height: nil)
        for subview in subviews {
            let size = subview.sizeThatFits(rowProposal)
            y += captionsVerticalPadding
            subview.place(
                at: CGPoint(x: bounds.minX + captionsHorizontalPadding, y: y),
                anchor: .topLeading,
                proposal: rowProposal
            )
            y += size.height + captionsVerticalPadding
        }
    }
}

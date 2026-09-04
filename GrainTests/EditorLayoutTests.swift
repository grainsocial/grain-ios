@testable import Grain
import SwiftUI
import XCTest

/// The gallery editor morphs one set of cells between a strip, a grid and a
/// captions list, and drag-to-reorder shuffles slots underneath that. All three
/// layouts and the slot maths are value types, so they can be checked directly
/// rather than by eye.
@MainActor
final class EditorLayoutTests: XCTestCase {
    private let width: CGFloat = 402

    /// 402 - 2*16 outer padding - 2*4 spacing, over three columns.
    private var gridCellSide: CGFloat {
        (402 - 32 - 8) / 3
    }

    /// Height `AdaptivePhotoLayout` reports for `count` cells in `mode`.
    private func layoutHeight(mode: EditorMode, count: Int) -> CGFloat {
        let layout = AdaptivePhotoLayout(mode: mode, containerWidth: width)
        let view = layout {
            ForEach(0 ..< count, id: \.self) { index in
                Color.gray
                    .frame(height: 40)
                    .layoutValue(key: PhotoIndexKey.self, value: index)
            }
        }
        return UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            .height
    }

    // MARK: - AdaptivePhotoLayout sizing

    /// The strip is one row of 72pt thumbs however many photos there are —
    /// that fixed height is what stops the form jumping as photos are added.
    func testTheStripIsOneFixedHeightRowRegardlessOfCount() {
        let expected: CGFloat = 72 + 22 * 2
        XCTAssertEqual(layoutHeight(mode: .preview, count: 1), expected, accuracy: 0.5)
        XCTAssertEqual(layoutHeight(mode: .preview, count: 9), expected, accuracy: 0.5)
    }

    func testTheGridGrowsARowAtATime() {
        let oneRow = layoutHeight(mode: .reorder, count: 3)
        let twoRows = layoutHeight(mode: .reorder, count: 4)
        let stillTwoRows = layoutHeight(mode: .reorder, count: 6)

        XCTAssertEqual(twoRows, stillTwoRows, accuracy: 0.5, "Four and six photos are both two rows")
        XCTAssertEqual(twoRows - oneRow, gridCellSide + 4, accuracy: 0.5, "A new row should cost a cell plus its spacing")
    }

    func testTheGridIsACellPlusItsPaddingForASingleRow() {
        // One row of cells, 22pt above and 12pt below.
        XCTAssertEqual(layoutHeight(mode: .reorder, count: 2), gridCellSide + 34, accuracy: 0.5)
    }

    func testTheCaptionsListStacksEveryRow() {
        let one = layoutHeight(mode: .captions, count: 1)
        let three = layoutHeight(mode: .captions, count: 3)

        XCTAssertEqual(three, one * 3, accuracy: 0.5, "Captions rows should simply stack")
        // 40pt of content plus 10pt above and below.
        XCTAssertEqual(one, 60, accuracy: 0.5)
    }

    /// Every mode is asked to size before there is anything to show.
    func testAnEmptyEditorHasNoHeightInAnyMode() {
        for mode in EditorMode.allCases {
            XCTAssertEqual(layoutHeight(mode: mode, count: 0), 0, accuracy: 0.5, "\(mode.label) sized a non-empty box")
        }
    }

    /// Switching modes is an animated interpolation between two layouts, so the
    /// three have to disagree — otherwise nothing moves.
    func testTheThreeModesReportDifferentHeights() {
        let heights = EditorMode.allCases.map { layoutHeight(mode: $0, count: 5) }
        XCTAssertEqual(Set(heights.map { Int($0.rounded()) }).count, 3, "Two modes size identically: \(heights)")
    }

    // MARK: - EditorMode

    func testEveryModeHasALabel() {
        XCTAssertEqual(EditorMode.preview.label, "Preview")
        XCTAssertEqual(EditorMode.reorder.label, "Reorder")
        XCTAssertEqual(EditorMode.captions.label, "Alt text")
        XCTAssertEqual(EditorMode.allCases.count, 3)
    }

    // MARK: - CellGeometry

    /// In the strip and the captions list the photo fills the square mask and
    /// overflows on its long edge; in the grid it fits inside instead.
    func testAWidePhotoOverflowsTheMaskInTheStripAndFitsItInTheGrid() {
        let wide: CGFloat = 3.0 / 2.0

        let strip = CellGeometry(mode: .preview, maskSide: 72, photoAspect: wide).photoSize
        XCTAssertEqual(strip.height, 72, accuracy: 0.01)
        XCTAssertGreaterThan(strip.width, 72)

        let grid = CellGeometry(mode: .reorder, maskSide: 72, photoAspect: wide).photoSize
        XCTAssertEqual(grid.width, 72, accuracy: 0.01)
        XCTAssertLessThan(grid.height, 72)
    }

    func testATallPhotoMirrorsTheWideCase() {
        let tall: CGFloat = 2.0 / 3.0

        let strip = CellGeometry(mode: .preview, maskSide: 72, photoAspect: tall).photoSize
        XCTAssertEqual(strip.width, 72, accuracy: 0.01)
        XCTAssertGreaterThan(strip.height, 72)

        let grid = CellGeometry(mode: .reorder, maskSide: 72, photoAspect: tall).photoSize
        XCTAssertEqual(grid.height, 72, accuracy: 0.01)
        XCTAssertLessThan(grid.width, 72)
    }

    func testASquarePhotoIsTheMaskInEveryMode() {
        for mode in EditorMode.allCases {
            let size = CellGeometry(mode: mode, maskSide: 72, photoAspect: 1).photoSize
            XCTAssertEqual(size.width, 72, accuracy: 0.01, "\(mode.label) stretched a square photo")
            XCTAssertEqual(size.height, 72, accuracy: 0.01, "\(mode.label) stretched a square photo")
        }
    }

    func testCaptionsUseTheSameFillAsTheStrip() {
        let wide: CGFloat = 3.0 / 2.0
        XCTAssertEqual(
            CellGeometry(mode: .captions, maskSide: 60, photoAspect: wide).photoSize,
            CellGeometry(mode: .preview, maskSide: 60, photoAspect: wide).photoSize
        )
    }

    /// The grid is edge-to-edge, so its cells square off while the others stay
    /// rounded.
    func testOnlyTheGridSquaresOffItsCorners() {
        XCTAssertEqual(CellGeometry(mode: .reorder, maskSide: 72, photoAspect: 1).maskCornerRadius, 0)
        XCTAssertEqual(CellGeometry(mode: .preview, maskSide: 72, photoAspect: 1).maskCornerRadius, 8)
        XCTAssertEqual(CellGeometry(mode: .captions, maskSide: 60, photoAspect: 1).maskCornerRadius, 8)
    }

    // MARK: - ReorderDragState

    private func draggingState(from index: Int) -> ReorderDragState {
        let state = ReorderDragState()
        state.beginDrag(itemID: UUID(), at: index)
        return state
    }

    private let cellStride = CGSize(width: 124, height: 124)

    func testBeginningADragRecordsWhereItStarted() {
        let state = draggingState(from: 2)

        XCTAssertTrue(state.isDragging)
        XCTAssertEqual(state.dragStartIndex, 2)
        XCTAssertEqual(state.dragCurrentIndex, 2)
    }

    /// A second gesture arriving mid-drag must not retarget the one in flight.
    func testASecondDragIsIgnoredWhileOneIsRunning() {
        let state = draggingState(from: 2)
        state.beginDrag(itemID: UUID(), at: 5)

        XCTAssertEqual(state.dragStartIndex, 2)
    }

    func testResettingClearsEverything() {
        let state = draggingState(from: 2)
        state.handleDragChanged(translation: CGSize(width: 124, height: 0), itemCount: 9, columnCount: 3, stride: cellStride)

        state.reset()

        XCTAssertFalse(state.isDragging)
        XCTAssertNil(state.dragStartIndex)
        XCTAssertNil(state.dragCurrentIndex)
        XCTAssertEqual(state.dragOffset, .zero)
    }

    func testDraggingOneCellRightProposesTheNextSlot() {
        let state = draggingState(from: 0)

        let proposed = state.handleDragChanged(
            translation: CGSize(width: 124, height: 0), itemCount: 9, columnCount: 3, stride: cellStride
        )

        XCTAssertEqual(proposed, 1)
        XCTAssertEqual(state.dragOffset.width, 124, accuracy: 0.01)
    }

    func testDraggingOneRowDownProposesTheSlotBelow() {
        let state = draggingState(from: 1)

        let proposed = state.handleDragChanged(
            translation: CGSize(width: 0, height: 124), itemCount: 9, columnCount: 3, stride: cellStride
        )

        XCTAssertEqual(proposed, 4)
    }

    /// A cell has to travel past the halfway point before the slot flips, or
    /// the grid reshuffles under the finger on every pixel of movement.
    func testASmallMovementProposesNothing() {
        let state = draggingState(from: 0)

        XCTAssertNil(state.handleDragChanged(
            translation: CGSize(width: 40, height: 0), itemCount: 9, columnCount: 3, stride: cellStride
        ))
    }

    /// Dragging off the left of column one must stay in column one rather than
    /// wrapping onto the previous row.
    func testDraggingPastTheLeftEdgeStaysInTheFirstColumn() {
        let state = draggingState(from: 3)

        let proposed = state.handleDragChanged(
            translation: CGSize(width: -500, height: 0), itemCount: 9, columnCount: 3, stride: cellStride
        )

        XCTAssertNil(proposed, "Clamping should leave the cell where it already is")
    }

    func testDraggingPastTheEndClampsToTheLastSlot() {
        let state = draggingState(from: 0)

        let proposed = state.handleDragChanged(
            translation: CGSize(width: 500, height: 900), itemCount: 5, columnCount: 3, stride: cellStride
        )

        XCTAssertEqual(proposed, 4)
    }

    func testDraggingPastTheTopClampsToTheFirstRow() {
        let state = draggingState(from: 4)

        let proposed = state.handleDragChanged(
            translation: CGSize(width: 0, height: -900), itemCount: 9, columnCount: 3, stride: cellStride
        )

        XCTAssertEqual(proposed, 1)
    }

    /// Called from a layout that may not have measured yet.
    func testADegenerateStrideProposesNothing() {
        let state = draggingState(from: 0)

        XCTAssertNil(state.handleDragChanged(
            translation: CGSize(width: 124, height: 0), itemCount: 9, columnCount: 3, stride: .zero
        ))
    }

    func testNoProposalWithoutADragInFlight() {
        let state = ReorderDragState()

        XCTAssertNil(state.handleDragChanged(
            translation: CGSize(width: 124, height: 0), itemCount: 9, columnCount: 3, stride: cellStride
        ))
        XCTAssertFalse(state.isDragging)
    }

    // MARK: - ReorderDragPlacement

    func testPlacementsCompareByBothIndices() {
        XCTAssertEqual(
            ReorderDragPlacement(draggedIndex: 1, currentIndex: 3),
            ReorderDragPlacement(draggedIndex: 1, currentIndex: 3)
        )
        XCTAssertNotEqual(
            ReorderDragPlacement(draggedIndex: 1, currentIndex: 3),
            ReorderDragPlacement(draggedIndex: 1, currentIndex: 4)
        )
    }
}

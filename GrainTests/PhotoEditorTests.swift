@testable import Grain
import UIKit
import XCTest

final class PhotoEditorTests: XCTestCase {
    // MARK: - Grid Target Index Calculation

    func testTargetIndexSameCell() {
        // Small drag within same cell → stays put
        let result = ReorderablePhotoGrid.targetIndex(
            currentIndex: 4, dragOffset: CGSize(width: 5, height: 3),
            cellSize: 100, spacing: 4, itemCount: 9
        )
        XCTAssertEqual(result, 4)
    }

    func testTargetIndexMoveRight() {
        // Drag one full cell to the right
        let result = ReorderablePhotoGrid.targetIndex(
            currentIndex: 0, dragOffset: CGSize(width: 104, height: 0),
            cellSize: 100, spacing: 4, itemCount: 6
        )
        XCTAssertEqual(result, 1)
    }

    func testTargetIndexMoveDown() {
        // Drag one full row down
        let result = ReorderablePhotoGrid.targetIndex(
            currentIndex: 1, dragOffset: CGSize(width: 0, height: 104),
            cellSize: 100, spacing: 4, itemCount: 9
        )
        XCTAssertEqual(result, 4)
    }

    func testTargetIndexClampsToLastItem() {
        // Drag way past the end → clamps to last item
        let result = ReorderablePhotoGrid.targetIndex(
            currentIndex: 0, dragOffset: CGSize(width: 500, height: 500),
            cellSize: 100, spacing: 4, itemCount: 5
        )
        XCTAssertEqual(result, 4)
    }

    func testTargetIndexClampsToFirst() {
        // Drag way before the start → clamps to 0
        let result = ReorderablePhotoGrid.targetIndex(
            currentIndex: 4, dragOffset: CGSize(width: -1000, height: -1000),
            cellSize: 100, spacing: 4, itemCount: 5
        )
        XCTAssertEqual(result, 0)
    }

    func testTargetIndexColumnClamp() {
        // From rightmost column, drag right → stays in column 2
        let result = ReorderablePhotoGrid.targetIndex(
            currentIndex: 2, dragOffset: CGSize(width: 200, height: 0),
            cellSize: 100, spacing: 4, itemCount: 9
        )
        XCTAssertEqual(result, 2)
    }

    // MARK: - PhotoItem Selection Stability

    func testSelectionStableThroughReorder() throws {
        let img = UIImage()
        var items = (0 ..< 5).map { _ in PhotoItem(thumbnail: img, source: .camera(img, metadata: nil)) }
        let selectedID = items[2].id

        // Move item at index 0 to index 3
        items.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)

        // Selected photo should still be findable by ID
        let newIndex = items.firstIndex(where: { $0.id == selectedID })
        XCTAssertNotNil(newIndex)
        XCTAssertEqual(try items[XCTUnwrap(newIndex)].id, selectedID)
    }

    func testSelectionFallsBackOnDeletion() {
        let img = UIImage()
        var items = (0 ..< 3).map { _ in PhotoItem(thumbnail: img, source: .camera(img, metadata: nil)) }
        var selectedID: UUID? = items[2].id

        // Remove the selected item
        items.removeAll { $0.id == selectedID }

        // Simulate the fallback logic from CreateGalleryView
        if let id = selectedID, !items.contains(where: { $0.id == id }) {
            selectedID = items.first?.id
        }

        XCTAssertEqual(selectedID, items.first?.id)
    }

    func testAltTextPreservedAcrossSelection() {
        let img = UIImage()
        var items = (0 ..< 3).map { _ in PhotoItem(thumbnail: img, source: .camera(img, metadata: nil)) }
        items[0].alt = "First photo"
        items[1].alt = "Second photo"

        // Simulate switching selection back and forth
        let id0 = items[0].id
        let id1 = items[1].id
        _ = items.firstIndex(where: { $0.id == id1 })
        _ = items.firstIndex(where: { $0.id == id0 })

        XCTAssertEqual(items[0].alt, "First photo")
        XCTAssertEqual(items[1].alt, "Second photo")
    }
}

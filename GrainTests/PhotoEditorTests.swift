@testable import Grain
import UIKit
import XCTest

final class PhotoEditorTests: XCTestCase {
    // MARK: - PhotoItem Selection Stability

    func testSelectionStableThroughReorder() throws {
        let img = UIImage()
        var items = (0 ..< 5).map { _ in PhotoItem(thumbnail: img, carouselPreview: img, source: .camera(img, metadata: nil)) }
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
        var items = (0 ..< 3).map { _ in PhotoItem(thumbnail: img, carouselPreview: img, source: .camera(img, metadata: nil)) }
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
        var items = (0 ..< 3).map { _ in PhotoItem(thumbnail: img, carouselPreview: img, source: .camera(img, metadata: nil)) }
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

@testable import Grain
import SwiftUI
import XCTest

/// Which cells a grid has built and not yet torn down.
@MainActor
private final class Built {
    var ids: Set<Int> = []
}

private struct Square: Identifiable {
    let id: Int
}

private let items = (0 ..< 300).map(Square.init)

/// The profile's arrangement: a vertical scroll view, a header, then a
/// horizontal pager holding the grid.
private struct Paged: View {
    let built: Built
    var anchor: UnitPoint?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.blue.frame(height: 300)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        WindowedGrid(items: items, scrollSpace: "outer") { item, _ in
                            Color.red
                                .onAppear { built.ids.insert(item.id) }
                                .onDisappear { built.ids.remove(item.id) }
                        }
                        .containerRelativeFrame(.horizontal)
                        .id(0)
                        Color.green.containerRelativeFrame(.horizontal).id(1)
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
            }
        }
        .coordinateSpace(.named("outer"))
        .defaultScrollAnchor(anchor)
    }
}

/// A grid reporting the height it was laid out at.
private struct Measured: View {
    let count: Int
    let onHeight: (CGFloat) -> Void

    var body: some View {
        ScrollView {
            WindowedGrid(items: Array(items.prefix(count)), scrollSpace: "outer") { _, _ in Color.red }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
        }
        .coordinateSpace(.named("outer"))
    }
}

@MainActor
final class WindowedGridTests: XCTestCase {
    private let width = ViewRender.canvas.width

    /// Rows a viewport of the canvas can show, at three columns of 3:4 cells.
    private var rowsPerViewport: Int {
        let layout = WindowedGrid<Square, Color>.Layout(count: 300, columns: 3, spacing: 2, aspectRatio: 3.0 / 4.0, width: width)
        return Int((ViewRender.canvas.height / layout.rowPitch).rounded(.up))
    }

    func testBuildsOnlyTheRowsNearTheViewportInsideAPager() {
        let built = Built()
        ViewRender.render(Paged(built: built), settle: 0.3)

        XCTAssertTrue(built.ids.contains(0), "the first row is on screen")
        XCTAssertFalse(built.ids.contains(299), "the last row is far below the fold")
        // The visible band plus one viewport of overscan on each side; the
        // header pushes the grid down, so it can only be less than that.
        XCTAssertLessThanOrEqual(built.ids.count, (rowsPerViewport * 2 + 1) * 3)
    }

    func testFollowsTheScrollOffset() {
        let built = Built()
        ViewRender.render(Paged(built: built, anchor: .bottom), settle: 0.3)

        XCTAssertTrue(built.ids.contains(299), "opened at the bottom, the last row is on screen")
        XCTAssertFalse(built.ids.contains(0), "the first row, built before the anchor applied, has been torn down")
    }

    func testMeasuresTheHeightOfTheFullGrid() {
        var height: CGFloat = 0
        ViewRender.render(Measured(count: 10) { height = $0 }, settle: 0.2)

        let layout = WindowedGrid<Square, Color>.Layout(count: 10, columns: 3, spacing: 2, aspectRatio: 3.0 / 4.0, width: width)
        XCTAssertEqual(layout.rowCount, 4)
        XCTAssertEqual(height, layout.height, accuracy: 1)
        XCTAssertEqual(layout.height, 4 * layout.cellSize.height + 3 * 2, accuracy: 0.001)
    }

    func testAnEmptyGridHasNoHeight() {
        var height: CGFloat = -1
        ViewRender.render(Measured(count: 0) { height = $0 }, settle: 0.1)
        XCTAssertEqual(height, 0)
    }

    func testLayoutRowWindowClampsToTheGrid() {
        let layout = WindowedGrid<Square, Color>.Layout(count: 30, columns: 3, spacing: 2, aspectRatio: 3.0 / 4.0, width: 402)
        XCTAssertEqual(layout.rowCount, 10)
        // Grid top at the viewport top: the first rows, plus a viewport below.
        let atTop = layout.rows(visibleFrom: 0, viewportHeight: layout.rowPitch * 2)
        XCTAssertEqual(atTop, 0 ..< 4)
        // Scrolled far past the end: nothing.
        XCTAssertTrue(layout.rows(visibleFrom: -layout.height - 5000, viewportHeight: 800).isEmpty)
        // Far above: nothing.
        XCTAssertTrue(layout.rows(visibleFrom: 5000, viewportHeight: 800).isEmpty)
        // Mid-way: a window straddling the visible band.
        let mid = layout.rows(visibleFrom: -layout.rowPitch * 5, viewportHeight: layout.rowPitch)
        XCTAssertEqual(mid, 4 ..< 7)
    }
}

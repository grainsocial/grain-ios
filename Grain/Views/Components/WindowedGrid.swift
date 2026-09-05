import SwiftUI

/// A fixed-aspect grid that only builds the rows near the visible part of
/// the scroll view it sits in.
///
/// `LazyVGrid` is lazy only along the axis of the *nearest* scroll view. The
/// profile's tabs put each grid inside a horizontal pager inside the vertical
/// scroll view, and there every cell was built at once: a profile with three
/// hundred galleries decoded three hundred thumbnails on open, and the last
/// cell's `onAppear` paged through the rest of the history straight away.
///
/// This grid does the bookkeeping itself. Every cell is the same size, so
/// which row a scroll offset lands on is arithmetic. It renders the rows
/// within a viewport of the visible band and pads above and below, and the
/// padding keeps the total height exactly what the full grid would measure.
/// The viewport is read through the named coordinate space of the scroll
/// view that actually scrolls, which nesting can't hide.
struct WindowedGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    /// Name given to the vertically scrolling ancestor with `coordinateSpace(.named:)`.
    let scrollSpace: String
    var columns = 3
    var spacing: CGFloat = 2
    /// Width divided by height of every cell.
    var aspectRatio: CGFloat = 3.0 / 4.0
    /// Builds one cell. The size is what the cell will be laid out at, for
    /// callers that want to size an image request to it.
    @ViewBuilder let cell: (Item, CGSize) -> Cell

    @State private var window = Window()

    /// The rows worth building, and the width they were computed for.
    struct Window: Equatable {
        var width: CGFloat = 0
        var rows: Range<Int> = 0 ..< 0
    }

    /// Where every row of a grid of `count` items lands, for a given width.
    struct Layout: Equatable {
        let count: Int
        let columns: Int
        let spacing: CGFloat
        let cellSize: CGSize
        let rowCount: Int

        init(count: Int, columns: Int, spacing: CGFloat, aspectRatio: CGFloat, width: CGFloat) {
            self.count = count
            self.columns = max(columns, 1)
            self.spacing = spacing
            let cellWidth = max((width - spacing * CGFloat(self.columns - 1)) / CGFloat(self.columns), 0)
            cellSize = CGSize(width: cellWidth, height: cellWidth / aspectRatio)
            rowCount = count > 0 ? (count + self.columns - 1) / self.columns : 0
        }

        /// Distance from one row's top to the next row's top.
        var rowPitch: CGFloat {
            cellSize.height + spacing
        }

        /// Height of the whole grid, padding included.
        var height: CGFloat {
            rowCount > 0 ? CGFloat(rowCount) * rowPitch - spacing : 0
        }

        /// The rows within `overscan` viewports of the visible band. `minY` is
        /// the grid's top edge relative to the viewport's top edge.
        func rows(visibleFrom minY: CGFloat, viewportHeight: CGFloat, overscan: CGFloat = 1) -> Range<Int> {
            guard rowCount > 0, rowPitch > 0 else { return 0 ..< 0 }
            let top = -minY - viewportHeight * overscan
            let bottom = -minY + viewportHeight * (1 + overscan)
            let lower = min(max(Int((top / rowPitch).rounded(.down)), 0), rowCount)
            let upper = min(max(Int((bottom / rowPitch).rounded(.up)), lower), rowCount)
            return lower ..< upper
        }
    }

    var body: some View {
        let layout = Layout(count: items.count, columns: columns, spacing: spacing, aspectRatio: aspectRatio, width: window.width)
        let rows = window.rows.clamped(to: 0 ..< layout.rowCount)

        Group {
            if rows.isEmpty {
                Color.clear.frame(height: layout.height)
            } else {
                VStack(spacing: spacing) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(itemsInRow(row, layout: layout)) { item in
                                cell(item, layout.cellSize)
                                    .frame(width: layout.cellSize.width, height: layout.cellSize.height)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, CGFloat(rows.lowerBound) * layout.rowPitch)
                .padding(.bottom, CGFloat(layout.rowCount - rows.upperBound) * layout.rowPitch)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: Window.self) { proxy in
            let width = proxy.size.width
            let layout = Layout(count: items.count, columns: columns, spacing: spacing, aspectRatio: aspectRatio, width: width)
            let space = NamedCoordinateSpace.named(scrollSpace)
            guard let viewport = proxy.bounds(of: space) else {
                // No such scroll view above us: build everything, as a plain
                // grid would, rather than guess at what's visible.
                return Window(width: width, rows: 0 ..< layout.rowCount)
            }
            let minY = proxy.frame(in: space).minY
            return Window(width: width, rows: layout.rows(visibleFrom: minY, viewportHeight: viewport.height))
        } action: { newWindow in
            window = newWindow
        }
    }

    private func itemsInRow(_ row: Int, layout: Layout) -> ArraySlice<Item> {
        let start = row * layout.columns
        let end = min(start + layout.columns, items.count)
        guard start < end else { return [] }
        return items[start ..< end]
    }
}

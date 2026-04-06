import SwiftUI

struct ReorderablePhotoGrid: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?

    @State private var draggingID: UUID?
    @State private var dragOffset: CGSize = .zero

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
    private let spacing: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let cellSize = (geo.size.width - spacing * 2) / 3
            let step = cellSize + spacing
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(items) { item in
                    cellView(item: item, cellSize: cellSize, isDragging: false)
                        // Hide the in-grid copy while dragging; it still holds layout space
                        .opacity(draggingID == item.id ? 0 : 1)
                        .simultaneousGesture(TapGesture().onEnded {
                            guard draggingID == nil else { return }
                            selectedPhotoID = item.id
                        })
                        .gesture(
                            LongPressGesture(minimumDuration: 0.2)
                                .sequenced(before: DragGesture())
                                .onChanged { value in
                                    switch value {
                                    case .second(true, let drag):
                                        if draggingID == nil {
                                            draggingID = item.id
                                        }
                                        if let drag {
                                            dragOffset = drag.translation
                                            reorderIfNeeded(cellSize: cellSize)
                                        }
                                    default:
                                        break
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                                        draggingID = nil
                                        dragOffset = .zero
                                    }
                                }
                        )
                }
            }
            // Dragged item rendered above the grid so it's unconditionally on top
            .overlay(alignment: .topLeading) {
                if let draggingID,
                   let item = items.first(where: { $0.id == draggingID }),
                   let idx = items.firstIndex(where: { $0.id == draggingID })
                {
                    let col = CGFloat(idx % 3)
                    let row = CGFloat(idx / 3)
                    cellView(item: item, cellSize: cellSize, isDragging: true)
                        .offset(
                            x: col * step + dragOffset.width,
                            y: row * step + dragOffset.height
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private func cellView(item: PhotoItem, cellSize: CGFloat, isDragging: Bool) -> some View {
        Image(uiImage: item.thumbnail)
            .resizable()
            .scaledToFill()
            .frame(width: cellSize, height: cellSize)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                let hasAlt = !item.alt.trimmingCharacters(in: .whitespaces).isEmpty
                Image(systemName: hasAlt ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 20))
                    .foregroundStyle(hasAlt ? .white : .white.opacity(0.5))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .padding(4)
            }
            .reorderableThumbnail(
                isDragging: isDragging,
                isSelected: item.id == selectedPhotoID,
                cornerRadius: 6
            )
    }

    /// Aspect ratio so GeometryReader doesn't collapse: cols / rows.
    private var aspectRatio: CGFloat {
        let rows = max(1, ceil(CGFloat(items.count) / 3))
        return 3 / rows
    }

    static func targetIndex(
        currentIndex: Int,
        dragOffset: CGSize,
        cellSize: CGFloat,
        spacing: CGFloat,
        itemCount: Int
    ) -> Int {
        let step = cellSize + spacing
        let colSteps = Int((dragOffset.width / step).rounded())
        let rowSteps = Int((dragOffset.height / step).rounded())

        let currentCol = currentIndex % 3
        let currentRow = currentIndex / 3

        let targetCol = max(0, min(2, currentCol + colSteps))
        let targetRow = max(0, currentRow + rowSteps)
        return max(0, min(itemCount - 1, targetRow * 3 + targetCol))
    }

    private func reorderIfNeeded(cellSize: CGFloat) {
        guard let draggingID,
              let currentIndex = items.firstIndex(where: { $0.id == draggingID })
        else { return }

        let target = Self.targetIndex(
            currentIndex: currentIndex,
            dragOffset: dragOffset,
            cellSize: cellSize,
            spacing: spacing,
            itemCount: items.count
        )

        if target != currentIndex {
            let colDelta = (target % 3) - (currentIndex % 3)
            let rowDelta = (target / 3) - (currentIndex / 3)
            let step = cellSize + spacing

            withAnimation(.spring(response: 0.45, dampingFraction: 0.7, blendDuration: 0)) {
                items.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: target > currentIndex ? target + 1 : target)
            }

            dragOffset.width -= CGFloat(colDelta) * step
            dragOffset.height -= CGFloat(rowDelta) * step
        }
    }
}

#Preview {
    @Previewable @State var state: [PhotoItem] = ([UIColor.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemPurple] as [UIColor]).map { color in
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 100, height: 100)))
        }
        return PhotoItem(thumbnail: thumb, source: .camera(thumb))
    }
    @Previewable @State var selected: UUID?
    ReorderablePhotoGrid(items: $state, selectedPhotoID: $selected)
        .padding()
}

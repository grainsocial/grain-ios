import SwiftUI

/// Visual treatment for a draggable, selectable thumbnail in a reorderable collection.
struct ReorderableThumbnail: ViewModifier {
    let isDragging: Bool
    let isSelected: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.accentColor, lineWidth: 2.5)
                    .opacity(isSelected ? 1 : 0)
            )
            .scaleEffect(isDragging ? 1.13 : 1)
            .shadow(
                color: isDragging ? .black.opacity(0.25) : .clear,
                radius: 8, y: 4
            )
            .opacity(isDragging ? 0.92 : 1)
            .zIndex(isDragging ? 1 : 0)
    }
}

extension View {
    func reorderableThumbnail(isDragging: Bool, isSelected: Bool, cornerRadius: CGFloat = 8) -> some View {
        modifier(ReorderableThumbnail(isDragging: isDragging, isSelected: isSelected, cornerRadius: cornerRadius))
    }
}

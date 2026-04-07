import SwiftUI

/// Visual treatment for a selectable thumbnail in a reorderable collection.
/// Only covers the rounded corner clip + selection ring; the pickup animation
/// (scale, opacity, shadow) lives at PhotoThumbnailCell's outer body so the X
/// button scales together with the photo.
struct ReorderableThumbnail: ViewModifier {
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
    }
}

extension View {
    func reorderableThumbnail(isSelected: Bool, cornerRadius: CGFloat = 8) -> some View {
        modifier(ReorderableThumbnail(isSelected: isSelected, cornerRadius: cornerRadius))
    }
}

#Preview {
    HStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 72, height: 72)
            .reorderableThumbnail(isSelected: false)
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 72, height: 72)
            .reorderableThumbnail(isSelected: true)
    }
    .padding()
}

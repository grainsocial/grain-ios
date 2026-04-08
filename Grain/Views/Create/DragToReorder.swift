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
    // Show a row of thumbnails with varied colors simulating real photos,
    // plus a larger card size, to exercise both the unselected and selected
    // ring states at a glance.
    let thumbnailColors: [Color] = [.indigo, .teal, .orange, .pink]
    VStack(spacing: 20) {
        // Standard 72pt strip (unselected, selected, unselected, unselected)
        HStack(spacing: 8) {
            ForEach(Array(thumbnailColors.enumerated()), id: \.offset) { idx, color in
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.55))
                    .frame(width: 72, height: 72)
                    .reorderableThumbnail(isSelected: idx == 1)
            }
        }

        // Larger card size — exercises the cornerRadius parameter
        HStack(spacing: 12) {
            ForEach(Array(thumbnailColors.prefix(3).enumerated()), id: \.offset) { idx, color in
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.55))
                    .frame(width: 100, height: 100)
                    .reorderableThumbnail(isSelected: idx == 0, cornerRadius: 12)
            }
        }
    }
    .padding()
    .background(Color(.systemBackground))
    .preferredColorScheme(.dark)
    .tint(Color("AccentColor"))
}

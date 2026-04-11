import NukeUI
import SwiftUI

struct AvatarView: View {
    let url: String?
    var size: CGFloat = 32
    /// Set to false to suppress all NukeUI transitions — use when the avatar is inside
    /// an animated parent (e.g. story parallax pane) so it snaps atomically.
    var animated: Bool = true

    /// Retains the last successfully loaded image so URL changes don't flash gray.
    @State private var lastUIImage: UIImage?

    var body: some View {
        if let url, let imageURL = URL(string: url) {
            LazyImage(url: imageURL) { state in
                if let uiImage = state.imageContainer?.image {
                    Image(uiImage: uiImage)
                        .resizable()
                        .transition(animated ? .opacity : .identity)
                        .onAppear { lastUIImage = uiImage }
                } else if let prev = lastUIImage {
                    // Show previous image while new URL loads — no gray flash
                    Image(uiImage: prev)
                        .resizable()
                        .transition(.identity)
                } else {
                    fallback
                        .transition(animated ? .opacity : .identity)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            fallback
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(Color.gray.opacity(0.3))
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.45))
                .foregroundStyle(Color.gray.opacity(0.6))
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        // Fallback state — no URL, all three canonical sizes side by side
        VStack(spacing: 8) {
            Text("Fallback (nil URL)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 20) {
                AvatarView(url: nil, size: 32)
                AvatarView(url: nil, size: 48)
                AvatarView(url: nil, size: 80)
            }
        }

        Divider()

        // Bad URL — exercises the loading-failed → fallback path
        VStack(spacing: 8) {
            Text("Bad URL (load failure fallback)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 20) {
                AvatarView(url: "https://invalid.example/avatar.jpg", size: 32)
                AvatarView(url: "https://invalid.example/avatar.jpg", size: 48)
                AvatarView(url: "https://invalid.example/avatar.jpg", size: 80)
            }
        }
    }
    .padding()
    .background(Color(.systemBackground))
    .grainPreview()
}

import NukeUI
import SwiftUI

struct AvatarView: View {
    let url: String?
    var size: CGFloat = 32
    /// Set to false to suppress all NukeUI transitions — use when the avatar is inside
    /// an animated parent (e.g. story parallax pane) so it snaps atomically.
    var animated: Bool = true

    private var imageURL: URL? {
        guard let url else { return nil }
        return URL(string: url)
    }

    var body: some View {
        LazyImage(url: imageURL) { state in
            if let image = state.image {
                image
                    .resizable()
            } else {
                fallback
            }
        }
        .animation(animated ? .default : nil, value: imageURL)
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(Color(.systemGray4))
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.45))
                .foregroundStyle(Color(.systemGray2))
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    VStack(spacing: 24) {
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

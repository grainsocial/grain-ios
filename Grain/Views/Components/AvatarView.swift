import Nuke
import NukeUI
import SwiftUI

struct AvatarView: View {
    let url: String?
    var size: CGFloat = 32
    /// Set to false to suppress all NukeUI transitions — use when the avatar is inside
    /// an animated parent (e.g. story parallax pane) so it snaps atomically.
    var animated: Bool = true

    /// Only set for async cache misses — cache hits are read synchronously in body.
    @State private var asyncImage: UIImage?

    private var imageURL: URL? {
        guard let url else { return nil }
        return URL(string: url)
    }

    private static let placeholder = UIImage()

    var body: some View {
        Image(uiImage: resolvedImage ?? Self.placeholder)
            .resizable()
            .frame(width: size, height: size)
            .background {
                fallback
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .onAppear { loadIfNeeded() }
    }

    /// Synchronous image resolution — checks memory cache first, then falls back to async-loaded image.
    private var resolvedImage: UIImage? {
        if let imageURL {
            if let cached = ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: imageURL))?.image {
                return cached
            }
        }
        return asyncImage
    }

    private func loadIfNeeded() {
        guard let imageURL else { return }
        let request = ImageRequest(url: imageURL)
        // If in memory cache, no state change needed — resolvedImage picks it up
        if ImagePipeline.shared.cache.cachedImage(for: request) != nil { return }
        // Only go async for true cache misses
        guard asyncImage == nil else { return }
        Task {
            if let image = try? await ImagePipeline.shared.image(for: request) {
                asyncImage = image
            }
        }
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

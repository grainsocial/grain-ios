import SwiftUI
import NukeUI

struct AvatarView: View {
    let url: String?
    var size: CGFloat = 32

    var body: some View {
        if let url, let imageURL = URL(string: url) {
            LazyImage(url: imageURL) { state in
                if let image = state.image {
                    image.resizable()
                } else {
                    fallback
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
            Circle().fill(.quaternary)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.45))
                .foregroundStyle(.tertiary)
        }
    }
}

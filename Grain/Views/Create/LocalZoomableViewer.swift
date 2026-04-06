import SwiftUI

struct LocalZoomableViewer: View {
    let image: UIImage

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale, anchor: .center)
            .offset(offset)
            .simultaneousGesture(magnification)
            .simultaneousGesture(
                DragGesture(minimumDistance: scale > 1 ? 0 : .infinity)
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                        if scale <= 1.05 {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
            )
            .onChange(of: image) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                    scale = 1
                    lastScale = 1
                    offset = .zero
                    lastOffset = .zero
                }
            }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1, lastScale * value)
            }
            .onEnded { value in
                let final = max(1, lastScale * value)
                if final < 1.05 {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                        scale = 1
                        offset = .zero
                        lastOffset = .zero
                    }
                }
                lastScale = scale
            }
    }
}

#Preview {
    LocalZoomableViewer(image: UIImage(named: "login-bg") ?? UIImage(systemName: "photo")!)
}

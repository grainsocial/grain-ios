import NukeUI
import SwiftUI

// MARK: - Shared zoom state

@Observable
@MainActor
final class ImageZoomState {
    var isActive = false
    var showOverlay = false
    var scale: CGFloat = 1
    var anchor: UnitPoint = .center
    var offset: CGSize = .zero
    var imageURL: String = ""
    var aspectRatio: CGFloat = 1
    var sourceFrame: CGRect = .zero
}

// MARK: - Overlay rendered above ScrollView

struct ImageZoomOverlay: ViewModifier {
    let zoomState: ImageZoomState
    let coordinateSpace: String

    func body(content: Content) -> some View {
        content
            .overlay {
                if zoomState.showOverlay {
                    GeometryReader { geo in
                        let containerOrigin = geo.frame(in: .named(coordinateSpace)).origin
                        let localX = zoomState.sourceFrame.midX - containerOrigin.x
                        let localY = zoomState.sourceFrame.midY - containerOrigin.y

                        LazyImage(url: URL(string: zoomState.imageURL)) { state in
                            if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(zoomState.aspectRatio, contentMode: .fit)
                            }
                        }
                        .frame(
                            width: zoomState.sourceFrame.width,
                            height: zoomState.sourceFrame.height
                        )
                        .scaleEffect(zoomState.scale, anchor: zoomState.anchor)
                        .offset(zoomState.offset)
                        .position(x: localX, y: localY)
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - UIKit gesture handler

struct PinchZoomOverlay: UIViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var anchor: UnitPoint
    @Binding var offset: CGSize
    @Binding var isActive: Bool
    var onEnded: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PinchZoomOverlay
        var startScale: CGFloat = 1

        init(_ parent: PinchZoomOverlay) {
            self.parent = parent
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            let dominated = otherGestureRecognizer.view is UIScrollView
            return !dominated
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                startScale = parent.scale
                let loc = gesture.location(in: gesture.view)
                let size = gesture.view?.bounds.size ?? CGSize(width: 1, height: 1)
                parent.anchor = UnitPoint(
                    x: loc.x / max(size.width, 1),
                    y: loc.y / max(size.height, 1)
                )
                parent.isActive = true
            case .changed:
                parent.scale = max(startScale * gesture.scale, 1)
            case .ended, .cancelled:
                startScale = parent.scale
                parent.onEnded()
            default:
                break
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .changed:
                guard parent.scale > 1 else { return }
                let t = gesture.translation(in: gesture.view)
                parent.offset = CGSize(width: t.x, height: t.y)
            case .ended, .cancelled:
                parent.onEnded()
            default:
                break
            }
        }
    }
}

// MARK: - ZoomableImage

struct ZoomableImage: View {
    let url: String
    let aspectRatio: CGFloat
    let coordinateSpace: String
    @Environment(ImageZoomState.self) private var zoomState

    @State private var snapBackTask: Task<Void, Never>?
    @State private var localScale: CGFloat = 1
    @State private var localAnchor: UnitPoint = .center
    @State private var localOffset: CGSize = .zero
    @State private var localActive = false

    var body: some View {
        LazyImage(url: URL(string: url)) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: .fit)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(aspectRatio, contentMode: .fit)
            }
        }
        .opacity(zoomState.showOverlay && zoomState.imageURL == url ? 0 : 1)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onChange(of: localActive) {
                        if localActive {
                            let frame = geo.frame(in: .named(coordinateSpace))
                            zoomState.sourceFrame = frame
                            zoomState.imageURL = url
                            zoomState.aspectRatio = aspectRatio
                            zoomState.showOverlay = true
                        }
                    }
                    .onChange(of: localScale) {
                        zoomState.scale = localScale
                        zoomState.anchor = localAnchor
                        zoomState.offset = localOffset
                    }
                    .onChange(of: localOffset) {
                        zoomState.offset = localOffset
                    }
            }
        }
        .overlay {
            PinchZoomOverlay(
                scale: $localScale,
                anchor: $localAnchor,
                offset: $localOffset,
                isActive: $localActive,
                onEnded: {
                    scheduleSnapBack()
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: url) {
            resetZoom()
        }
    }

    private func scheduleSnapBack() {
        snapBackTask?.cancel()
        snapBackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(112))
            guard !Task.isCancelled else { return }
            resetZoom()
        }
    }

    private func resetZoom() {
        snapBackTask?.cancel()
        localActive = false
        zoomState.isActive = false
        withAnimation(.easeOut(duration: 0.1)) {
            localScale = 1
            localOffset = .zero
            zoomState.scale = 1
            zoomState.offset = .zero
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            zoomState.showOverlay = false
        }
    }
}

import NukeUI
import SwiftUI

// MARK: - Shared zoom state

@Observable
@MainActor
final class ImageZoomState {
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
    let zoomState: ImageZoomState
    var onBegan: (UnitPoint) -> Void
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
            let state = parent.zoomState
            switch gesture.state {
            case .began:
                startScale = state.scale
                let loc = gesture.location(in: gesture.view)
                let size = gesture.view?.bounds.size ?? CGSize(width: 1, height: 1)
                let anchor = UnitPoint(
                    x: loc.x / max(size.width, 1),
                    y: loc.y / max(size.height, 1)
                )
                state.anchor = anchor
                parent.onBegan(anchor)
            case .changed:
                state.scale = max(startScale * gesture.scale, 1)
            case .ended, .cancelled:
                startScale = state.scale
                parent.onEnded()
            default:
                break
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .changed:
                guard parent.zoomState.scale > 1 else { return }
                let t = gesture.translation(in: gesture.view)
                parent.zoomState.offset = CGSize(width: t.x, height: t.y)
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
        .overlay {
            GeometryReader { geo in
                Color.clear.onAppear {}
                    .preference(key: FrameKey.self, value: geo.frame(in: .named(coordinateSpace)))
            }
        }
        .overlay {
            PinchZoomOverlay(
                zoomState: zoomState,
                onBegan: { anchor in
                    zoomState.imageURL = url
                    zoomState.aspectRatio = aspectRatio
                    zoomState.anchor = anchor
                    zoomState.showOverlay = true
                },
                onEnded: { scheduleSnapBack() }
            )
        }
        .onPreferenceChange(FrameKey.self) { frame in
            if zoomState.showOverlay && zoomState.imageURL == url {
                zoomState.sourceFrame = frame
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: url) { resetZoom() }
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
        withAnimation(.easeOut(duration: 0.1)) {
            zoomState.scale = 1
            zoomState.offset = .zero
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            zoomState.showOverlay = false
        }
    }
}

// MARK: - Preference key for frame tracking

private struct FrameKey: @preconcurrency PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

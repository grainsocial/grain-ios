import NukeUI
import SwiftUI

// MARK: - UIKit gesture handler for proper pinch + pan

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
            // Allow pinch + pan to work together
            // But don't interfere with scroll view or tab view gestures
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
    @Binding var isZoomed: Bool
    @Binding var showOverlay: Bool
    @Binding var zoomScale: CGFloat
    @Binding var zoomAnchor: UnitPoint
    @Binding var zoomOffset: CGSize

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
        .opacity(showOverlay ? 0 : 1)
        .overlay {
            PinchZoomOverlay(
                scale: $zoomScale,
                anchor: $zoomAnchor,
                offset: $zoomOffset,
                isActive: $isZoomed,
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
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            resetZoom()
        }
    }

    private func resetZoom() {
        snapBackTask?.cancel()
        isZoomed = false
        withAnimation(.easeOut(duration: 0.2)) {
            zoomScale = 1
            zoomOffset = .zero
        }
        // Keep overlay visible during snap-back animation, then hide
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            showOverlay = false
        }
    }
}

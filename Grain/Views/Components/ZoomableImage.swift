import Nuke
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
    var localImage: UIImage?
    var aspectRatio: CGFloat = 1
    var sourceFrame: CGRect = .zero
}

// MARK: - Overlay rendered above ScrollView

struct ImageZoomOverlay: ViewModifier {
    let zoomState: ImageZoomState

    func body(content: Content) -> some View {
        content
            .overlay {
                if zoomState.showOverlay {
                    GeometryReader { geo in
                        let overlayGlobal = geo.frame(in: .global).origin
                        let localX = zoomState.sourceFrame.midX - overlayGlobal.x
                        let localY = zoomState.sourceFrame.midY - overlayGlobal.y

                        Group {
                            if let local = zoomState.localImage {
                                Image(uiImage: local)
                                    .resizable()
                                    .aspectRatio(zoomState.aspectRatio, contentMode: .fit)
                            } else {
                                LazyImage(url: URL(string: zoomState.imageURL)) { state in
                                    if let image = state.image {
                                        image
                                            .resizable()
                                            .aspectRatio(zoomState.aspectRatio, contentMode: .fit)
                                    }
                                }
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
    var onBegan: (UnitPoint, CGRect) -> Void
    var onEnded: () -> Void
    var onDoubleTap: ((CGPoint) -> Void)?

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

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        return view
    }

    func updateUIView(_: UIView, context: Context) {
        context.coordinator.parent = self
    }

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

        @MainActor func gestureRecognizer(
            _: UIGestureRecognizer,
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
                let globalFrame = gesture.view?.convert(gesture.view?.bounds ?? .zero, to: nil) ?? .zero
                parent.onBegan(anchor, globalFrame)
            case .changed:
                state.scale = max(startScale * gesture.scale, 1)
            case .ended, .cancelled, .failed:
                // .failed is essential — without it a pinch interrupted by another
                // recognizer (e.g. parent ScrollView claiming the gesture) leaves
                // the zoom state stuck and the snap-back never fires.
                startScale = state.scale
                parent.onEnded()
            default:
                break
            }
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            let loc = gesture.location(in: gesture.view)
            parent.onDoubleTap?(loc)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .changed:
                guard parent.zoomState.scale > 1 else { return }
                let translation = gesture.translation(in: gesture.view)
                parent.zoomState.offset = CGSize(width: translation.x, height: translation.y)
            case .ended, .cancelled, .failed:
                // Include .failed so that an interrupted pan (e.g. a third finger
                // touched down, or a sibling recognizer claimed the gesture) still
                // triggers the snap-back instead of leaving the offset frozen.
                parent.onEnded()
            default:
                break
            }
        }
    }
}

// MARK: - ZoomableImage

struct ZoomableImage: View {
    enum Source {
        case url(String, thumbURL: String? = nil)
        case local(UIImage)
    }

    let source: Source
    let aspectRatio: CGFloat
    /// Higher-resolution image to show in the zoom overlay. When nil, the
    /// overlay falls back to the same image used for normal display. Pass a
    /// lazily-loaded hi-res version here so the normal display path uses a
    /// lighter image while zoom gets more detail if it's ready.
    var zoomImage: UIImage?
    var onDoubleTap: ((CGPoint) -> Void)?
    @Environment(ImageZoomState.self) private var zoomState: ImageZoomState?

    @State private var snapBackTask: Task<Void, Never>?
    @State private var resetTask: Task<Void, Never>?
    /// Per-instance flag flipped on in `onBegan` and off in `resetZoom`. We use this
    /// instead of comparing `zoomState.localImage === source` because the rendered
    /// image instance can change mid-lifetime (e.g. PhotoEditor's preview cache
    /// swaps a low-res thumbnail for the high-res preview), which would defeat
    /// identity-based equality and leave the base image visible behind the overlay.
    @State private var isZoomingMe = false

    init(url: String, thumbURL: String? = nil, aspectRatio: CGFloat, onDoubleTap: ((CGPoint) -> Void)? = nil) {
        source = .url(url, thumbURL: thumbURL)
        self.aspectRatio = aspectRatio
        self.onDoubleTap = onDoubleTap
    }

    init(localImage: UIImage, aspectRatio: CGFloat, zoomImage: UIImage? = nil, onDoubleTap: ((CGPoint) -> Void)? = nil) {
        source = .local(localImage)
        self.aspectRatio = aspectRatio
        self.zoomImage = zoomImage
        self.onDoubleTap = onDoubleTap
    }

    private var sourceID: String {
        switch source {
        case let .url(url, _): "url:\(url)"
        case let .local(image): "local:\(ObjectIdentifier(image).hashValue)"
        }
    }

    private var isCurrentlyZoomed: Bool {
        guard let zoomState, zoomState.showOverlay else { return false }
        switch source {
        case let .url(url, _):
            return zoomState.imageURL == url
        case .local:
            // Identity (`===`) comparison fails when the rendered UIImage instance
            // changes during the same view lifetime — e.g. when PhotoEditor's
            // preview cache swaps a 150pt thumbnail for the 1500pt preview.
            // The per-instance flag is set in onBegan and cleared in resetZoom,
            // so it tracks the gesture session rather than image identity.
            return isZoomingMe
        }
    }

    var body: some View {
        // PinchZoomOverlay is a ZStack sibling (not an overlay on the image) so the
        // UIView fills the full carousel slot — black-bar areas are tappable and
        // UIKit coordinates already map to the carousel ZStack space with no correction.
        ZStack {
            sourceView
                .opacity(isCurrentlyZoomed ? 0 : 1)

            if let zoomState {
                PinchZoomOverlay(
                    zoomState: zoomState,
                    onBegan: { anchor, frame in
                        switch source {
                        case let .url(url, _):
                            zoomState.imageURL = url
                            zoomState.localImage = nil
                        case let .local(image):
                            zoomState.imageURL = ""
                            // Prefer zoomImage (hi-res) if available; fall back to
                            // the carousel preview already in memory.
                            zoomState.localImage = zoomImage ?? image
                        }
                        zoomState.aspectRatio = aspectRatio
                        zoomState.anchor = anchor
                        zoomState.sourceFrame = frame
                        zoomState.showOverlay = true
                        isZoomingMe = true
                    },
                    onEnded: { scheduleSnapBack() },
                    onDoubleTap: onDoubleTap
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: sourceID) { resetZoom() }
        .onDisappear {
            snapBackTask?.cancel()
            resetTask?.cancel()
        }
    }

    @ViewBuilder
    private var sourceView: some View {
        switch source {
        case let .url(url, thumbURL):
            LazyImage(request: ImageRequest(url: URL(string: url), priority: .veryHigh)) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(aspectRatio, contentMode: .fit)
                } else if let thumbURL {
                    LazyImage(url: URL(string: thumbURL)) { thumbState in
                        if let thumb = thumbState.image {
                            thumb
                                .resizable()
                                .aspectRatio(aspectRatio, contentMode: .fit)
                                .blur(radius: 20)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(.quaternary)
                                .aspectRatio(aspectRatio, contentMode: .fit)
                        }
                    }
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(aspectRatio, contentMode: .fit)
                }
            }
        case let .local(image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(aspectRatio, contentMode: .fit)
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
        guard let zoomState else { return }
        snapBackTask?.cancel()
        withAnimation(.easeOut(duration: 0.1)) {
            zoomState.scale = 1
            zoomState.offset = .zero
        }
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            zoomState.showOverlay = false
            isZoomingMe = false
        }
    }
}

#Preview {
    // Use a solid color rendered into a UIImage so zoom state is exercisable
    // without a network dependency. The 4:3 gradient stands in for a real photo.
    let size = CGSize(width: 400, height: 300)
    let renderer = UIGraphicsImageRenderer(size: size)
    let sampleImage = renderer.image { ctx in
        let colors = [UIColor.systemIndigo.cgColor, UIColor.systemTeal.cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors as CFArray,
                                  locations: [0, 1])!
        ctx.cgContext.drawLinearGradient(gradient,
                                         start: .zero,
                                         end: CGPoint(x: size.width, y: size.height),
                                         options: [])
    }

    ZoomableImage(localImage: sampleImage, aspectRatio: 4 / 3)
        .environment(ImageZoomState())
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .grainPreview()
}

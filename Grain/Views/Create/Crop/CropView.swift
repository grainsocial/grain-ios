import SwiftUI

/// Full-screen crop tool. Presented as `.fullScreenCover` from both story
/// and gallery create flows.
///
/// Takes the original image + an optional previous crop result (for re-entry).
/// Returns a `CropResult` on done.
struct CropView: View {
    let image: UIImage
    let existingCrop: CropResult?
    let onDone: (CropResult) -> Void
    let onCancel: () -> Void

    @State private var state = CropState()
    /// The image after rotation is applied (for display).
    @State private var displayImage: UIImage
    @State private var hasInitialized = false

    init(
        image: UIImage,
        existingCrop: CropResult? = nil,
        onDone: @escaping (CropResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.image = image
        self.existingCrop = existingCrop
        self.onDone = onDone
        self.onCancel = onCancel

        let normalized = ImageCropper.normalizeOrientation(image)
        if let crop = existingCrop {
            _displayImage = State(initialValue: ImageCropper.rotate(normalized, degrees: crop.rotation))
        } else {
            _displayImage = State(initialValue: normalized)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Image area fills the full geo — controls float on top
                imageArea(in: geo)

                // Floating controls
                VStack(spacing: 0) {
                    toolbar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    Spacer()

                    AspectRatioBar(state: state)
                        .padding(.bottom, 8)

                    rotationButtons
                        .padding(.bottom, 16)
                }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)

            Spacer()

            Button("Reset") {
                withAnimation(.smooth(duration: 0.4)) {
                    state.resetAll()
                }
                let normalized = ImageCropper.normalizeOrientation(image)
                displayImage = normalized
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)

            Spacer()

            Button("Done") {
                confirmCrop()
            }
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    // MARK: - Image area

    @ViewBuilder
    private func imageArea(in geo: GeometryProxy) -> some View {
        let safeArea = geo.safeAreaInsets
        let availableWidth = geo.size.width - 32
        let availableHeight = geo.size.height
            - 56 // toolbar
            - 32 // spacers
            - 44 // aspect bar
            - 56 // rotation buttons
            - safeArea.top - safeArea.bottom

        let imgAspect = displayImage.size.width / max(displayImage.size.height, 1)
        let fitWidth = min(availableWidth, availableHeight * imgAspect)
        let fitHeight = fitWidth / imgAspect

        ZStack {
            // Image layer — NO clipping so zoom can grow past bounds
            Image(uiImage: displayImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: fitWidth, height: fitHeight)
                .scaleEffect(state.imageScale)
                .offset(state.imageOffset)
                .transition(.blurReplace)

            // Overlay (dimming + grid + handles) — clipped to the layout frame
            CropOverlayView(
                cropRect: state.cropRect,
                geometrySize: CGSize(width: fitWidth, height: fitHeight)
            )

            // Gesture layer — covers full frame (including dim zone)
            Color.clear
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .simultaneousGesture(magnifyGesture)
        }
        .frame(width: fitWidth, height: fitHeight)
        // Only clip the overlay, not the image — image can overflow when zoomed
        .clipped()
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .local) }) { frame in
            if state.imageDisplayFrame != frame {
                state.imageDisplayFrame = frame
                if !hasInitialized {
                    hasInitialized = true
                    initializeCropState()
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: displayImage.size.width)
        .animation(.smooth(duration: 0.35), value: displayImage.size.height)
    }

    // MARK: - Rotation buttons

    private var rotationButtons: some View {
        HStack(spacing: 32) {
            Button {
                rotate(degrees: -90)
            } label: {
                Image(systemName: "rotate.left")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Button {
                rotate(degrees: 90)
            } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .glassEffect(.regular.interactive(), in: .circle)
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if state.activeHandle == nil {
                    let handle = state.hitTest(point: value.startLocation)
                    state.activeHandle = handle
                    state.dragStartCropRect = state.cropRect
                    state.dragStartImageOffset = state.imageOffset
                }

                guard let handle = state.activeHandle else { return }

                if handle == .panImage {
                    state.handleImagePan(translation: value.translation)
                } else {
                    state.handleDrag(handle: handle, translation: value.translation)
                }
            }
            .onEnded { _ in
                state.activeHandle = nil
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if state.pinchStartScale == 1.0, state.imageScale != 1.0 {
                    state.pinchStartScale = state.imageScale
                } else if state.pinchStartScale == 1.0 {
                    state.pinchStartScale = 1.0
                }
                let newScale = max(state.pinchStartScale * value.magnification, 1.0)
                state.imageScale = newScale
                state.imageOffset = state.clampImageOffset(state.imageOffset)
            }
            .onEnded { _ in
                state.pinchStartScale = state.imageScale
                state.imageOffset = state.clampImageOffset(state.imageOffset)
            }
    }

    // MARK: - Actions

    private func initializeCropState() {
        // Set original ratio for the "Original" preset
        let normalized = ImageCropper.normalizeOrientation(image)
        state.originalImageRatio = normalized.size.width / max(normalized.size.height, 1)

        if let existing = existingCrop {
            state.rotation = existing.rotation
            let frame = state.imageDisplayFrame
            state.cropRect = CGRect(
                x: frame.origin.x + existing.cropRect.origin.x * frame.width,
                y: frame.origin.y + existing.cropRect.origin.y * frame.height,
                width: existing.cropRect.width * frame.width,
                height: existing.cropRect.height * frame.height
            )
        } else {
            state.resetCrop()
        }
    }

    private func rotate(degrees: Int) {
        state.rotation = (state.rotation + degrees + 360) % 360
        let normalized = ImageCropper.normalizeOrientation(image)

        withAnimation(.smooth(duration: 0.4)) {
            displayImage = ImageCropper.rotate(normalized, degrees: state.rotation)
            state.resetCrop()
        }
    }

    private func confirmCrop() {
        let normalizedRect = ImageCropper.viewRectToNormalized(
            state.cropRect,
            imageDisplayFrame: state.imageDisplayFrame,
            imageOffset: state.imageOffset,
            imageScale: state.imageScale
        )

        let croppedImage = ImageCropper.applyCrop(
            to: image,
            normalizedRect: normalizedRect,
            rotation: state.rotation
        )

        onDone(CropResult(
            croppedImage: croppedImage,
            rotation: state.rotation,
            cropRect: normalizedRect
        ))
    }
}

// MARK: - Preview

#Preview {
    let size = CGSize(width: 600, height: 400)
    let renderer = UIGraphicsImageRenderer(size: size)
    let sampleImage = renderer.image { ctx in
        let colors = [UIColor.systemOrange.cgColor, UIColor.systemPurple.cgColor]
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: [0, 1]
        )!
        ctx.cgContext.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: size.width, y: size.height),
            options: []
        )
        ctx.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        ctx.cgContext.setLineWidth(1)
        for x in stride(from: 0, to: size.width, by: 50) {
            ctx.cgContext.move(to: CGPoint(x: x, y: 0))
            ctx.cgContext.addLine(to: CGPoint(x: x, y: size.height))
        }
        for y in stride(from: 0, to: size.height, by: 50) {
            ctx.cgContext.move(to: CGPoint(x: 0, y: y))
            ctx.cgContext.addLine(to: CGPoint(x: size.width, y: y))
        }
        ctx.cgContext.strokePath()
    }

    CropView(
        image: sampleImage,
        onDone: { _ in },
        onCancel: {}
    )
}

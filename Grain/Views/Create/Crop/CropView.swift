import SwiftUI

/// Full-screen crop tool. Presented as `.fullScreenCover` from both story
/// and gallery create flows.
struct CropView: View {
    let image: UIImage
    let existingCrop: CropResult?
    let onDone: (CropResult) -> Void
    let onCancel: () -> Void

    @State private var state = CropState()
    /// Always the orientation-normalized original. Never mutated — rotation
    /// is applied visually via `.rotationEffect()`.
    @State private var displayImage: UIImage
    @State private var hasInitialized = false
    @State private var isRotating = false

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
        _displayImage = State(initialValue: ImageCropper.normalizeOrientation(image))
    }

    private var isSwapped: Bool {
        state.rotationDegrees == 90 || state.rotationDegrees == 270
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Image fills available space — controls float on top
                imageArea(in: geo)

                // Floating controls
                VStack(spacing: 0) {
                    // Top: toolbar + tool buttons
                    VStack(spacing: 8) {
                        toolbar
                            .padding(.horizontal, 16)

                        toolButtons
                    }
                    .padding(.top, 8)

                    Spacer()

                    // Bottom: orientation toggle + ratio strip
                    VStack(spacing: 8) {
                        orientationToggle

                        AspectRatioBar(state: state)
                    }
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
            }
            .foregroundStyle(.white.opacity(0.5))
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

    // MARK: - Tool buttons (rotation + grid) — top row

    private var toolButtons: some View {
        HStack(spacing: 24) {
            Button {
                rotate(degrees: -90)
            } label: {
                Image(systemName: "rotate.left")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Button {
                state.showGrid.toggle()
            } label: {
                Image(systemName: "grid")
                    .font(.system(size: 18))
                    .foregroundStyle(state.showGrid ? .white : .white.opacity(0.35))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .glassEffect(state.showGrid ? .regular.interactive() : .regular, in: .circle)

            Button {
                rotate(degrees: 90)
            } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .glassEffect(.regular.interactive(), in: .circle)
        }
    }

    // MARK: - Orientation toggle (portrait / landscape)

    /// Always visible — dimmed when the selected preset doesn't support orientation
    /// (Free, Original, Square). Active orientation is highlighted, inactive is dimmed.
    private var orientationToggle: some View {
        let enabled = state.showOrientationToggle
        return HStack(spacing: 16) {
            Button {
                guard enabled, state.isPortrait else { return }
                withAnimation(.smooth(duration: 0.3)) {
                    state.toggleOrientation()
                }
            } label: {
                // Landscape rectangle
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(lineWidth: 1.5)
                    .frame(width: 18, height: 12)
                    .foregroundStyle(
                        enabled
                            ? (!state.isPortrait ? .white : .white.opacity(0.35))
                            : .white.opacity(0.15)
                    )
                    .frame(width: 40, height: 36)
                    .contentShape(Rectangle())
            }
            .glassEffect(
                enabled && !state.isPortrait ? .regular.interactive() : .regular,
                in: .capsule
            )

            Button {
                guard enabled, !state.isPortrait else { return }
                withAnimation(.smooth(duration: 0.3)) {
                    state.toggleOrientation()
                }
            } label: {
                // Portrait rectangle
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(lineWidth: 1.5)
                    .frame(width: 12, height: 18)
                    .foregroundStyle(
                        enabled
                            ? (state.isPortrait ? .white : .white.opacity(0.35))
                            : .white.opacity(0.15)
                    )
                    .frame(width: 40, height: 36)
                    .contentShape(Rectangle())
            }
            .glassEffect(
                enabled && state.isPortrait ? .regular.interactive() : .regular,
                in: .capsule
            )
        }
    }

    // MARK: - Image area

    /// Height reserved by all controls above and below the image.
    private static let controlsHeight: CGFloat = 44 + 48 + 44 + 44 + 48

    @ViewBuilder
    private func imageArea(in geo: GeometryProxy) -> some View {
        let safeArea = geo.safeAreaInsets
        let availableWidth = geo.size.width - 32
        let availableHeight = geo.size.height
            - Self.controlsHeight
            - safeArea.top - safeArea.bottom

        let baseW = displayImage.size.width
        let baseH = displayImage.size.height
        let postW = isSwapped ? baseH : baseW
        let postH = isSwapped ? baseW : baseH
        let imgAspect = postW / max(postH, 1)

        let (fitWidth, fitHeight): (CGFloat, CGFloat) = {
            let w = min(availableWidth, availableHeight * imgAspect)
            let h = w / imgAspect
            if h > availableHeight {
                return (availableHeight * imgAspect, availableHeight)
            }
            return (w, h)
        }()

        ZStack {
            // Image — sized for pre-rotation, then rotated into post-rotation frame.
            // No clipping so zoom can overflow.
            Image(uiImage: displayImage)
                .resizable()
                .frame(
                    width: isSwapped ? fitHeight : fitWidth,
                    height: isSwapped ? fitWidth : fitHeight
                )
                .rotationEffect(.degrees(state.rotationAngle))
                .scaleEffect(state.imageScale)
                .offset(state.imageOffset)

            // Overlay — dimming extends beyond frame for zoom overflow
            CropOverlayView(
                cropRect: state.cropRect,
                geometrySize: CGSize(width: fitWidth, height: fitHeight),
                showGrid: state.showGrid
            )

            // Gesture layer
            Color.clear
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .simultaneousGesture(magnifyGesture)
        }
        .frame(width: fitWidth, height: fitHeight)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .local) }) { frame in
            state.imageDisplayFrame = frame
            if !hasInitialized {
                hasInitialized = true
                initializeCropState()
            } else if isRotating {
                // During rotation animation, keep crop rect tracking the frame
                state.cropRect = frame
                state.imageOffset = .zero
                state.imageScale = 1.0
            }
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if state.activeHandle == nil {
                    guard let handle = state.hitTest(point: value.startLocation) else { return }
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
        state.originalImageRatio = displayImage.size.width / max(displayImage.size.height, 1)

        if let existing = existingCrop {
            state.rotationAngle = Double(existing.rotation)
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
        isRotating = true
        withAnimation(.smooth(duration: 0.4)) {
            state.rotationAngle += Double(degrees)
        } completion: {
            isRotating = false
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
            rotation: state.rotationDegrees
        )

        onDone(CropResult(
            croppedImage: croppedImage,
            rotation: state.rotationDegrees,
            cropRect: normalizedRect
        ))
    }
}

// MARK: - Preview

#Preview {
    let sampleImage: UIImage = {
        guard let path = Bundle.main.url(forResource: "Mount_Hood_reflected_in_Mirror_Lake,_Oregon", withExtension: "jpg")?.path,
              let img = UIImage(contentsOfFile: path)
        else {
            return PreviewData.gradientThumb(
                colors: [UIColor.systemOrange.cgColor, UIColor.systemPurple.cgColor],
                size: CGSize(width: 600, height: 400)
            )
        }
        return img
    }()

    CropView(
        image: sampleImage,
        onDone: { _ in },
        onCancel: {}
    )
}

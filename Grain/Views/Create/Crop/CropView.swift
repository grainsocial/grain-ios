import os
import SwiftUI

private let cropViewSignposter = OSSignposter(subsystem: "social.grain.grain", category: "CropView")

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
    @State private var postRotationNormalizedCrop: CGRect?
    @State private var isProcessing = false

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
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            GeometryReader { geo in
                imageArea(in: geo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Controls — respect safe area for Dynamic Island / home indicator
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    toolbar
                        .padding(.horizontal, 16)

                    toolButtons
                }
                .padding(.top, 8)

                Spacer()

                VStack(spacing: 8) {
                    bottomControls

                    AspectRatioBar(state: state)
                }
                .padding(.bottom, 16)
            }
            .tint(.primary)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            // Cancel when pristine, Reset when modified
            Button {
                if state.hasModifications {
                    withAnimation(.smooth(duration: 0.4)) {
                        state.resetAll()
                    }
                } else {
                    onCancel()
                }
            } label: {
                Text(state.hasModifications ? "Reset" : "Cancel")
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)

            Spacer()

            Button("Done") {
                confirmCrop()
            }
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .animation(.smooth(duration: 0.3), value: state.hasModifications)
    }

    // MARK: - Tool buttons — top row

    /// Standalone tool button with its own glass circle.
    private func toolButton(_ icon: String, active: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(active ? .primary : .tertiary)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .glassEffect(active ? .regular.interactive() : .regular, in: .circle)
    }

    /// Button inside a shared pill — no individual glass.
    private func pillButton(_ icon: String, active: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(active ? .primary : .tertiary)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
    }

    private var toolButtons: some View {
        HStack(spacing: 16) {
            // Rotate pair in a single pill
            HStack(spacing: 0) {
                pillButton("rotate.left") { rotate(degrees: -90) }
                    .offset(y: -1) // optical center — arrow weight sits low
                pillButton("rotate.right") { rotate(degrees: 90) }
                    .offset(y: -1)
            }
            .glassEffect(.regular.interactive(), in: .capsule)

            toolButton("grid", active: state.showGrid) { state.showGrid.toggle() }

            // Zoom pair in a single pill — minus (fit) left, plus (zoom) right
            HStack(spacing: 0) {
                pillButton("minus.magnifyingglass",
                           active: state.isViewModified)
                {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        state.resetView()
                    }
                }
                pillButton("plus.magnifyingglass") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) {
                        state.zoomToCrop()
                    }
                }
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    // MARK: - Bottom controls (lock + orientation toggle)

    private var bottomControls: some View {
        let orientationEnabled = state.showOrientationToggle
        return HStack(spacing: 12) {
            // Lock toggle
            Button {
                state.toggleRatioLock()
            } label: {
                Image(systemName: state.isRatioLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(state.isRatioLocked ? .primary : .tertiary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .glassEffect(state.isRatioLocked ? .regular.interactive() : .regular, in: .circle)

            // Landscape / Portrait pair in a single pill
            HStack(spacing: 0) {
                Button {
                    guard orientationEnabled, state.isPortrait else { return }
                    withAnimation(.smooth(duration: 0.3)) {
                        state.toggleOrientation()
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(lineWidth: 1.5)
                        .frame(width: 18, height: 12)
                        .foregroundStyle(
                            orientationEnabled
                                ? (!state.isPortrait ? .primary : .tertiary)
                                : .quaternary
                        )
                        .frame(width: 40, height: 36)
                        .contentShape(Rectangle())
                }

                Button {
                    guard orientationEnabled, !state.isPortrait else { return }
                    withAnimation(.smooth(duration: 0.3)) {
                        state.toggleOrientation()
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(lineWidth: 1.5)
                        .frame(width: 12, height: 18)
                        .foregroundStyle(
                            orientationEnabled
                                ? (state.isPortrait ? .primary : .tertiary)
                                : .quaternary
                        )
                        .frame(width: 40, height: 36)
                        .contentShape(Rectangle())
                }
            }
            .glassEffect(
                orientationEnabled ? .regular.interactive() : .regular,
                in: .capsule
            )
        }
    }

    // MARK: - Image area

    /// Height reserved by all controls above and below the image.
    private static let controlsHeight: CGFloat = 44 + 48 + 44 + 44 + 48

    @ViewBuilder
    private func imageArea(in geo: GeometryProxy) -> some View {
        let availableWidth = geo.size.width - 32
        let availableHeight = geo.size.height - Self.controlsHeight

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
            // Image + overlay in the same coordinate space.
            // scaleEffect/offset are applied to both so the mask
            // tracks the image during zoom and pan.
            ZStack {
                // Black fill prevents white corners during rotation animation
                Color.black

                Image(uiImage: displayImage)
                    .resizable()
                    .frame(
                        width: isSwapped ? fitHeight : fitWidth,
                        height: isSwapped ? fitWidth : fitHeight
                    )
                    .rotationEffect(.degrees(state.rotationAngle))

                CropOverlayView(
                    cropRect: state.cropRect,
                    geometrySize: CGSize(width: fitWidth, height: fitHeight),
                    showGrid: state.showGrid
                )
            }
            .frame(width: fitWidth, height: fitHeight)
            .clipped()
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .local) }) { frame in
                state.imageDisplayFrame = frame
                if !hasInitialized {
                    hasInitialized = true
                    initializeCropState()
                } else if isRotating {
                    state.cropRect = frame
                }
            }
            .scaleEffect(state.imageScale)
            .offset(state.imageOffset)

            // Screen-space handles (outside transform chain — constant size at any zoom)
            CropHandlesView(screenCropRect: state.screenCropRect)

            // Gesture layer — ExtendedTouchView extends touch area 44pt
            // beyond bounds so boundary handles are reachable.
            CropGestureOverlay(
                state: state,
                frameSize: CGSize(width: fitWidth, height: fitHeight)
            )
            .frame(width: fitWidth, height: fitHeight)
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
        // Normalize crop to 0…1 in the current frame
        let frame = state.imageDisplayFrame
        guard frame.width > 0, frame.height > 0 else { return }
        let preNorm = CGRect(
            x: (state.cropRect.minX - frame.minX) / frame.width,
            y: (state.cropRect.minY - frame.minY) / frame.height,
            width: state.cropRect.width / frame.width,
            height: state.cropRect.height / frame.height
        )

        // Map through rotation.
        // 90° CW:  point (x,y) → (1-y, x)  ⇒  rect → (1-maxY, minX, h, w)
        // 270° CW: point (x,y) → (y, 1-x)  ⇒  rect → (minY, 1-maxX, h, w)
        // 180°:    point (x,y) → (1-x, 1-y) ⇒  rect → (1-maxX, 1-maxY, w, h)
        let normDeg = ((degrees % 360) + 360) % 360
        let postNorm: CGRect = switch normDeg {
        case 90:
            CGRect(x: 1 - preNorm.maxY, y: preNorm.minX,
                   width: preNorm.height, height: preNorm.width)
        case 270:
            CGRect(x: preNorm.minY, y: 1 - preNorm.maxX,
                   width: preNorm.height, height: preNorm.width)
        case 180:
            CGRect(x: 1 - preNorm.maxX, y: 1 - preNorm.maxY,
                   width: preNorm.width, height: preNorm.height)
        default:
            preNorm
        }
        postRotationNormalizedCrop = postNorm

        isRotating = true
        withAnimation(.smooth(duration: 0.4)) {
            state.rotationAngle += Double(degrees)
            state.imageOffset = .zero
            state.imageScale = 1.0
        } completion: {
            isRotating = false
            if let norm = postRotationNormalizedCrop {
                let newFrame = state.imageDisplayFrame
                let viewRect = CGRect(
                    x: newFrame.origin.x + norm.origin.x * newFrame.width,
                    y: newFrame.origin.y + norm.origin.y * newFrame.height,
                    width: norm.width * newFrame.width,
                    height: norm.height * newFrame.height
                )
                withAnimation(.smooth(duration: 0.25)) {
                    state.cropRect = state.nearestValidCrop(viewRect, ratio: state.effectiveLockedRatio)
                }
            }
            postRotationNormalizedCrop = nil
        }
    }

    private func confirmCrop() {
        guard !isProcessing else { return }
        isProcessing = true

        // In overlay space the image fills imageDisplayFrame,
        // so normalized rect is just cropRect / frameSize.
        let frame = state.imageDisplayFrame
        let validCrop = state.nearestValidCrop(state.cropRect, ratio: state.effectiveLockedRatio)
        let normalizedRect = CGRect(
            x: (validCrop.minX - frame.minX) / max(frame.width, 1),
            y: (validCrop.minY - frame.minY) / max(frame.height, 1),
            width: validCrop.width / max(frame.width, 1),
            height: validCrop.height / max(frame.height, 1)
        )
        let rotation = state.rotationDegrees
        let sourceImage = image

        Task.detached {
            let spid = cropViewSignposter.makeSignpostID()
            let spState = cropViewSignposter.beginInterval("confirmCrop", id: spid)
            let croppedImage = ImageCropper.applyCrop(
                to: sourceImage,
                normalizedRect: normalizedRect,
                rotation: rotation
            )
            cropViewSignposter.endInterval("confirmCrop", spState)

            await MainActor.run {
                onDone(CropResult(
                    croppedImage: croppedImage,
                    rotation: rotation,
                    cropRect: normalizedRect
                ))
            }
        }
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

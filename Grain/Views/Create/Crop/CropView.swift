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
    @State private var lastGeoSize: CGSize = .zero

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
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { lastGeoSize = $0 }

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
            // Close when pristine, Reset when modified
            Button {
                if state.hasModifications {
                    resetToBaseline()
                } else {
                    onCancel()
                }
            } label: {
                Text(state.hasModifications ? "Reset" : "Close")
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)

            Spacer()

            Button("Apply") {
                confirmCrop()
            }
            .fontWeight(.semibold)
            .foregroundStyle(state.hasModifications ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            .disabled(!state.hasModifications)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(
                state.hasModifications ? .regular.interactive() : .regular,
                in: .capsule
            )
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

    /// Compute the fitted image dimensions for a given rotation state.
    private func fitSize(geoSize: CGSize, swapped: Bool) -> (width: CGFloat, height: CGFloat) {
        let availableWidth = geoSize.width - 32
        let availableHeight = geoSize.height - Self.controlsHeight
        let baseW = displayImage.size.width
        let baseH = displayImage.size.height
        let postW = swapped ? baseH : baseW
        let postH = swapped ? baseW : baseH
        let imgAspect = postW / max(postH, 1)
        let w = min(availableWidth, availableHeight * imgAspect)
        let h = w / imgAspect
        if h > availableHeight {
            return (availableHeight * imgAspect, availableHeight)
        }
        return (w, h)
    }

    @ViewBuilder
    private func imageArea(in geo: GeometryProxy) -> some View {
        let fit = fitSize(geoSize: geo.size, swapped: isSwapped)
        let fitWidth = fit.width
        let fitHeight = fit.height

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
                    // When restoring an existing rotation, set rotation first
                    // and wait for the frame to update to the rotated dimensions
                    // before placing the crop rect.
                    if let existing = existingCrop, existing.rotation != 0,
                       state.rotationAngle != Double(existing.rotation)
                    {
                        state.rotationAngle = Double(existing.rotation)
                        return
                    }
                    hasInitialized = true
                    initializeCropState()
                }
            }
            .scaleEffect(state.imageScale)
            .offset(state.imageOffset)

            // Screen-space handles (outside transform chain — constant size at any zoom)
            CropHandlesView(screenCropRect: state.screenCropRect)
                .frame(width: fitWidth, height: fitHeight)

            // Gesture layer extends 44pt beyond image frame so handles at
            // the image boundary can be grabbed from outside.
            CropGestureOverlay(
                state: state,
                frameSize: CGSize(width: fitWidth, height: fitHeight),
                touchInset: 44
            )
            .frame(width: fitWidth + 88, height: fitHeight + 88)
        }
    }

    // MARK: - Actions

    private func resetToBaseline() {
        // Precompute the baseline frame in case rotation changes isSwapped.
        let baseRotDeg = Int(state.baselineRotation.truncatingRemainder(dividingBy: 360))
        let baseSwapped = (baseRotDeg + 360) % 360 == 90 || (baseRotDeg + 360) % 360 == 270
        let baseFit = fitSize(geoSize: lastGeoSize, swapped: baseSwapped)
        let baseFrame = CGRect(x: 0, y: 0, width: baseFit.width, height: baseFit.height)
        let base = state.baselineNormalizedCrop
        let baseCrop = CGRect(
            x: base.origin.x * baseFrame.width,
            y: base.origin.y * baseFrame.height,
            width: base.width * baseFrame.width,
            height: base.height * baseFrame.height
        )

        withAnimation(.smooth(duration: 0.4)) {
            state.resetAll()
            // Override the cropRect that resetAll set (it used the old frame).
            state.cropRect = baseCrop
        }
    }

    private func initializeCropState() {
        state.originalImageRatio = displayImage.size.width / max(displayImage.size.height, 1)

        if let existing = existingCrop {
            // Rotation was already set in onGeometryChange (before this call),
            // and imageDisplayFrame now has the correct rotated dimensions.
            let frame = state.imageDisplayFrame
            state.cropRect = CGRect(
                x: frame.origin.x + existing.cropRect.origin.x * frame.width,
                y: frame.origin.y + existing.cropRect.origin.y * frame.height,
                width: existing.cropRect.width * frame.width,
                height: existing.cropRect.height * frame.height
            )
            state.setBaseline(rotation: Double(existing.rotation), normalizedCrop: existing.cropRect)
        } else {
            state.resetCrop()
            state.setBaseline(rotation: 0, normalizedCrop: CGRect(x: 0, y: 0, width: 1, height: 1))
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

        // Precompute the new frame so cropRect can be set inside withAnimation
        // (onGeometryChange callbacks don't inherit the animation transaction).
        let newRotDeg = ((state.rotationDegrees + normDeg) % 360)
        let newSwapped = newRotDeg == 90 || newRotDeg == 270
        let newFit = fitSize(geoSize: lastGeoSize, swapped: newSwapped)
        let newFrame = CGRect(x: 0, y: 0, width: newFit.width, height: newFit.height)

        isRotating = true
        withAnimation(.smooth(duration: 0.4)) {
            state.rotationAngle += Double(degrees)
            state.imageOffset = .zero
            state.imageScale = 1.0
            // Set cropRect to the new full frame within the animation transaction
            // so overlay and handles interpolate smoothly with the frame transition.
            state.cropRect = newFrame
        } completion: {
            isRotating = false
            if let norm = postRotationNormalizedCrop {
                let currentFrame = state.imageDisplayFrame
                let viewRect = CGRect(
                    x: currentFrame.origin.x + norm.origin.x * currentFrame.width,
                    y: currentFrame.origin.y + norm.origin.y * currentFrame.height,
                    width: norm.width * currentFrame.width,
                    height: norm.height * currentFrame.height
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

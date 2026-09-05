import PhotosUI
import SwiftUI

/// The viewfinder half of the story composer: live camera preview with a
/// shutter button, plus library and lens-flip controls either side of it.
struct StoryCaptureStage: View {
    let camera: StoryCamera
    @Binding var selectedPhoto: PhotosPickerItem?
    let errorMessage: String?
    let onCapture: (UIImage) -> Void
    let onCaptureFailed: () -> Void
    let onCancel: () -> Void

    @State private var shutterFlash = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                viewfinder
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                VStack {
                    HStack {
                        StoryChromeButton("xmark", label: "Cancel", action: onCancel)
                        Spacer()
                        if camera.status == .ready, camera.hasFlash {
                            StoryChromeButton(
                                camera.flashMode == .on ? "bolt.fill" : "bolt.slash",
                                label: camera.flashMode == .on ? "Flash on" : "Flash off"
                            ) {
                                camera.toggleFlash()
                            }
                        }
                    }
                    .padding(16)
                    Spacer()
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.tint(.red.opacity(0.6)), in: .rect(cornerRadius: 12))
                            .padding(16)
                    }
                }

                Color.white
                    .opacity(shutterFlash ? 0.8 : 0)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            controls
                .padding(.top, 20)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var viewfinder: some View {
        switch camera.status {
        case .ready:
            CameraPreviewView(session: camera.session)
        case .starting:
            Color(white: 0.08)
        case .unauthorized:
            placeholder(
                title: "Camera access is off",
                message: "Allow camera access in Settings to take a photo, or pick one from your library."
            ) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.glass)
            }
        case .unavailable:
            placeholder(
                title: "Camera unavailable",
                message: "Pick a photo from your library instead."
            ) {
                EmptyView()
            }
        }
    }

    private func placeholder(
        title: String,
        message: String,
        @ViewBuilder action: () -> some View
    ) -> some View {
        ZStack {
            Color(white: 0.08)
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                action()
                    .padding(.top, 4)
            }
            .padding(32)
        }
    }

    private var controls: some View {
        HStack {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
            }
            .liquidGlassCircle()
            .accessibilityLabel("Choose from library")

            Spacer()

            Button {
                Task { await takePhoto() }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(.white)
                        .frame(width: 64, height: 64)
                        .scaleEffect(camera.isCapturing ? 0.85 : 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(camera.status != .ready || camera.isCapturing)
            .opacity(camera.status == .ready ? 1 : 0.35)
            .animation(.easeOut(duration: 0.15), value: camera.isCapturing)
            .accessibilityLabel("Take photo")

            Spacer()

            Button {
                Task { await camera.flip() }
            } label: {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.camera")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
            }
            .liquidGlassCircle()
            .disabled(camera.status != .ready)
            .opacity(camera.status == .ready ? 1 : 0.35)
            .accessibilityLabel("Switch camera")
        }
        .padding(.horizontal, 32)
    }

    private func takePhoto() async {
        withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
        let image = await camera.capture()
        withAnimation(.easeIn(duration: 0.2)) { shutterFlash = false }
        if let image {
            onCapture(image)
        } else {
            onCaptureFailed()
        }
    }
}

/// Round glass icon button used for the corner controls over the viewfinder
/// and the captured photo.
struct StoryChromeButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    init(_ symbol: String, label: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
        }
        .liquidGlassCircle()
        .accessibilityLabel(label)
    }
}

#Preview {
    @Previewable @State var photo: PhotosPickerItem?
    ZStack {
        Color.black.ignoresSafeArea()
        StoryCaptureStage(
            camera: StoryCamera(),
            selectedPhoto: $photo,
            errorMessage: nil,
            onCapture: { _ in },
            onCaptureFailed: {},
            onCancel: {}
        )
    }
    .grainPreview()
}

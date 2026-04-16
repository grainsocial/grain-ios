import SwiftUI

/// Lightweight display model shared by `ExifInfoView`.
/// Both `GrainExif` (feed) and `ExifSummary` (create flow) map to this
/// via their `displayData` computed properties defined below.
struct ExifDisplayData {
    var camera: String?
    var lens: String?
    var focalLength: String?
    var fNumber: String?
    var exposureTime: String?
    var iso: String?
}

extension GrainExif {
    var displayData: ExifDisplayData {
        ExifDisplayData(
            camera: cameraName,
            lens: lensName,
            focalLength: formattedFocalLength,
            fNumber: formattedFNumber,
            exposureTime: formattedExposureTime,
            iso: iSO.map { "ISO \($0)" }
        )
    }
}

extension ExifSummary {
    var displayData: ExifDisplayData {
        ExifDisplayData(
            camera: camera,
            lens: lens,
            focalLength: focalLength,
            fNumber: aperture,
            exposureTime: shutterSpeed,
            iso: iso
        )
    }
}

struct ExifInfoView: View {
    let exif: ExifDisplayData?
    /// Always reserve layout space for the camera row even when the current exif is nil.
    /// Set true when any photo in the gallery has a camera name.
    var reserveCameraRow: Bool = false
    /// Always reserve layout space for the lens row even when the current exif is nil.
    var reserveLensRow: Bool = false
    /// Foreground style for all text and icons.
    var style: AnyShapeStyle = .init(.secondary)

    var body: some View {
        let showCamera = reserveCameraRow || exif?.camera != nil
        let showLens = reserveLensRow || exif?.lens != nil
        if showCamera || showLens || exif != nil {
            VStack(alignment: .leading, spacing: 4) {
                if showCamera {
                    HStack(spacing: 6) {
                        Image(systemName: "camera").font(.caption2)
                        Text(exif?.camera ?? " ").font(.caption)
                    }
                    .foregroundStyle(style)
                    .opacity(exif?.camera != nil ? 1 : 0)
                }
                if showLens {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.circle").font(.caption2)
                        Text(exif?.lens ?? " ").font(.caption)
                    }
                    .foregroundStyle(style)
                    .opacity(exif?.lens != nil ? 1 : 0)
                }
                let settingsTokens = [exif?.focalLength, exif?.fNumber, exif?.exposureTime, exif?.iso]
                if settingsTokens.contains(where: { $0 != nil }) {
                    ExifSettingsRow(
                        tokens: settingsTokens,
                        style: style
                    )
                }
            }
            .opacity(exif != nil ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: exif == nil)
        }
    }
}

struct ExifSettingsRow: View {
    let tokens: [String?]
    var style: AnyShapeStyle = .init(.secondary)

    var body: some View {
        ZStack(alignment: .leading) {
            Text(" ").hidden() // holds caption line height when all tokens are nil
            HStack(spacing: 6) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, value in
                    if let value {
                        Text(value.digitWidthProxy)
                            .hidden()
                            .overlay(Text(value).contentTransition(.identity))
                            // Zero-duration overrides the parent .smooth context for this
                            // view's appearance/disappearance — snaps in/out instantly while
                            // sibling positions still shift smoothly via the HStack animation.
                            .transition(.opacity.animation(.linear(duration: 0)))
                    }
                }
            }
            .animation(.smooth, value: tokens)
        }
        .font(.caption)
        .foregroundStyle(style)
    }
}

#Preview {
    ExifInfoView(exif: ExifDisplayData(
        camera: "Leica M11",
        lens: "Summilux-M 35mm f/1.4",
        focalLength: "35mm",
        fNumber: "f/2",
        exposureTime: "1/500",
        iso: "ISO 200"
    ))
    .padding()
}

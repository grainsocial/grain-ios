import SwiftUI

struct ExifInfoView: View {
    let exif: GrainExif

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let camera = exif.cameraName {
                HStack(spacing: 6) {
                    Image(systemName: "camera")
                        .font(.caption2)
                    Text(camera)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            if let lens = exif.lensName {
                HStack(spacing: 6) {
                    Image(systemName: "circle.circle")
                        .font(.caption2)
                    Text(lens)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            if let settings = exif.settingsLine {
                Text(settings)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ExifInfoView(exif: GrainExif(
        uri: "at://preview",
        cid: "cid",
        photo: "at://preview/photo",
        createdAt: "2024-06-15T18:00:00Z",
        exposureTime: "1/500",
        fNumber: "f/2.0",
        focalLengthIn35mmFormat: "35mm",
        iSO: 200,
        lensModel: "Summilux-M 35mm f/1.4",
        make: "Leica",
        model: "M11"
    ))
    .padding()
}

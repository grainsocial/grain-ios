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

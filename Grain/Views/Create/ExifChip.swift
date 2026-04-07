import SwiftUI

/// Three-state exif indicator: absent = no exif data, inactive = has exif but
/// sendExif is off, active = has exif and will be uploaded.
enum ExifState: Equatable {
    case absent, inactive, active
}

/// EXIF camera badge.
///
/// - `compact: true`  — icon only, for strip and grid cells where space is tight.
/// - `compact: false` — icon + camera name (width-capped, truncates with ellipsis),
///   for the captions list where there's room to read it.
struct ExifChip: View {
    let state: ExifState
    var cameraName: String?
    var compact: Bool = false

    var body: some View {
        if state != .absent {
            let on = state == .active
            if compact {
                Image(systemName: "camera.fill")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(on ? Color("AccentColor").opacity(0.15) : Color(.systemGray5), in: Capsule())
                    .foregroundStyle(on ? Color("AccentColor") : Color.secondary)
            } else {
                Label(cameraName ?? "EXIF", systemImage: "camera.fill")
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: 90, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(on ? Color("AccentColor").opacity(0.12) : Color(.systemGray5), in: Capsule())
                    .foregroundStyle(on ? Color("AccentColor") : Color.secondary)
            }
        }
    }
}

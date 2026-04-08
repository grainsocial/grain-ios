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

    var body: some View {
        if state != .absent {
            let on = state == .active
            Image(systemName: "camera.fill")
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
                .opacity(on ? 1 : 0.5)
        }
    }
}

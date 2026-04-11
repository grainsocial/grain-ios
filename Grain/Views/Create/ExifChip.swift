import SwiftUI

/// Three-state exif indicator: absent = no exif data, inactive = has exif but
/// sendExif is off, active = has exif and will be uploaded.
enum ExifState: Equatable {
    case absent, inactive, active
}

/// EXIF camera badge shown on photo thumbnails.
struct ExifChip: View {
    let state: ExifState

    var body: some View {
        if state != .absent {
            let on = state == .active
            Image(systemName: "camera.fill")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 19, height: 19)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                .opacity(on ? 1 : 0.5)
        }
    }
}

import UIKit

/// Persisted crop output. Stored alongside the original image so the user
/// can re-enter the crop tool and adjust without losing data.
///
/// **Order of operations:** rotation is applied FIRST, then the crop rect
/// (which is stored in post-rotation coordinate space).
struct CropResult {
    let croppedImage: UIImage
    /// Clockwise rotation applied before cropping: 0, 90, 180, or 270.
    let rotation: Int
    /// Normalized crop rect (0…1) in POST-ROTATION coordinate space.
    let cropRect: CGRect
}

import SwiftUI

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

/// Captures everything CropView needs at tap time so the fullScreenCover
/// never races against state propagation.
struct CropRequest: Identifiable {
    let id = UUID()
    let image: UIImage
    let existingCrop: CropResult?
}

extension View {
    func cropSheet(request: Binding<CropRequest?>, onCropped: @escaping (CropResult) -> Void) -> some View {
        fullScreenCover(item: request) { req in
            CropView(image: req.image, existingCrop: req.existingCrop) { result in
                onCropped(result)
                request.wrappedValue = nil
            } onCancel: {
                request.wrappedValue = nil
            }
        }
    }
}

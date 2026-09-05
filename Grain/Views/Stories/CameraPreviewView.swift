import AVFoundation
import SwiftUI

/// Live viewfinder for the story camera. Aspect-fills whatever frame it's
/// given; the session keeps it upright as the phone rotates.
struct CameraPreviewView: UIViewRepresentable {
    let session: StoryCameraSession

    func makeUIView(context _: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        session.attach(previewLayer: view.previewLayer)
        return view
    }

    func updateUIView(_: PreviewView, context _: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

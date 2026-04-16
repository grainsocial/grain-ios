import SwiftUI

/// The crop overlay: dimmed region + optional rule-of-thirds grid.
///
/// Border and handles are drawn in screen-space by `CropHandlesView`.
/// This view only handles the dim mask and grid (which must track the
/// overlay coordinate system to align with the image transform).
///
/// Conforms to `Animatable` so SwiftUI interpolates the crop rect
/// between values, giving smooth transitions on preset/rotation changes.
struct CropOverlayView: View, @preconcurrency Animatable {
    var cropRect: CGRect
    let geometrySize: CGSize
    let showGrid: Bool

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            .init(.init(cropRect.origin.x, cropRect.origin.y),
                  .init(cropRect.size.width, cropRect.size.height))
        }
        set {
            cropRect = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    var body: some View {
        ZStack {
            dimmingMask
            if showGrid {
                gridLines
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Dimming

    /// Extends well beyond the frame so zoomed images are still dimmed.
    private var dimmingMask: some View {
        let overflow: CGFloat = 2000
        return Path { path in
            path.addRect(CGRect(
                x: -overflow,
                y: -overflow,
                width: geometrySize.width + overflow * 2,
                height: geometrySize.height + overflow * 2
            ))
            path.addRect(cropRect)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
    }

    // MARK: - Grid

    private var gridLines: some View {
        Path { path in
            let r = cropRect
            let thirdW = r.width / 3
            for i in 1 ... 2 {
                let x = r.minX + thirdW * CGFloat(i)
                path.move(to: CGPoint(x: x, y: r.minY))
                path.addLine(to: CGPoint(x: x, y: r.maxY))
            }
            let thirdH = r.height / 3
            for i in 1 ... 2 {
                let y = r.minY + thirdH * CGFloat(i)
                path.move(to: CGPoint(x: r.minX, y: y))
                path.addLine(to: CGPoint(x: r.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
    }
}

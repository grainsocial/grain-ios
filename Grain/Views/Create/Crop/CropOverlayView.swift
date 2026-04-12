import SwiftUI

/// The crop overlay: dimmed region, optional rule-of-thirds grid,
/// border with integrated L-bracket corner handles and edge bar handles.
///
/// Handles are drawn as part of the crop rect border — they're not
/// separate floating elements. The rect and handles move as one unit.
struct CropOverlayView: View {
    let cropRect: CGRect
    let geometrySize: CGSize
    let showGrid: Bool

    var body: some View {
        ZStack {
            dimmingMask
            if showGrid {
                gridLines
            }
            cropBorderAndHandles
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
        .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
    }

    // MARK: - Border + handles (one unit)

    private let handleLength: CGFloat = 20
    private let handleThickness: CGFloat = 3

    /// Thin border + thicker L-brackets at corners + bars at edge midpoints.
    /// All drawn in a single Path group so they're visually one element.
    private var cropBorderAndHandles: some View {
        let r = cropRect
        return ZStack {
            // Thin border
            Rectangle()
                .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)

            // Corner L-brackets + edge bars — drawn on top of the border
            Path { path in
                // Top-left
                corner(&path, at: CGPoint(x: r.minX, y: r.minY), xDir: 1, yDir: 1)
                // Top-right
                corner(&path, at: CGPoint(x: r.maxX, y: r.minY), xDir: -1, yDir: 1)
                // Bottom-left
                corner(&path, at: CGPoint(x: r.minX, y: r.maxY), xDir: 1, yDir: -1)
                // Bottom-right
                corner(&path, at: CGPoint(x: r.maxX, y: r.maxY), xDir: -1, yDir: -1)

                // Edge midpoint bars
                edgeBar(&path, center: CGPoint(x: r.midX, y: r.minY), horizontal: true)
                edgeBar(&path, center: CGPoint(x: r.midX, y: r.maxY), horizontal: true)
                edgeBar(&path, center: CGPoint(x: r.minX, y: r.midY), horizontal: false)
                edgeBar(&path, center: CGPoint(x: r.maxX, y: r.midY), horizontal: false)
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: handleThickness, lineCap: .round))
        }
    }

    private func corner(_ path: inout Path, at point: CGPoint, xDir: CGFloat, yDir: CGFloat) {
        path.move(to: point)
        path.addLine(to: CGPoint(x: point.x + handleLength * xDir, y: point.y))
        path.move(to: point)
        path.addLine(to: CGPoint(x: point.x, y: point.y + handleLength * yDir))
    }

    private func edgeBar(_ path: inout Path, center: CGPoint, horizontal: Bool) {
        let half = handleLength / 2
        if horizontal {
            path.move(to: CGPoint(x: center.x - half, y: center.y))
            path.addLine(to: CGPoint(x: center.x + half, y: center.y))
        } else {
            path.move(to: CGPoint(x: center.x, y: center.y - half))
            path.addLine(to: CGPoint(x: center.x, y: center.y + half))
        }
    }
}

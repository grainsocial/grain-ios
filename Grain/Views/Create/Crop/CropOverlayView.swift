import SwiftUI

/// Draws the crop overlay: dimmed region outside the crop rect, rule-of-thirds
/// grid, border, and 8 drag handles (4 corners + 4 edge midpoints).
struct CropOverlayView: View {
    let cropRect: CGRect
    let geometrySize: CGSize

    var body: some View {
        ZStack {
            dimmingMask
            gridLines
            handles
            cropBorder
        }
        .allowsHitTesting(false)
    }

    // MARK: - Dimming

    private var dimmingMask: some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: geometrySize))
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

    // MARK: - Handles

    private let handleLength: CGFloat = 20
    private let handleThickness: CGFloat = 3

    private var handles: some View {
        let r = cropRect
        return ZStack {
            // Corners — L-shaped brackets
            cornerHandle(at: CGPoint(x: r.minX, y: r.minY), xDir: 1, yDir: 1)
            cornerHandle(at: CGPoint(x: r.maxX, y: r.minY), xDir: -1, yDir: 1)
            cornerHandle(at: CGPoint(x: r.minX, y: r.maxY), xDir: 1, yDir: -1)
            cornerHandle(at: CGPoint(x: r.maxX, y: r.maxY), xDir: -1, yDir: -1)

            // Edge midpoints — short bars
            edgeHandle(center: CGPoint(x: r.midX, y: r.minY), horizontal: true)
            edgeHandle(center: CGPoint(x: r.midX, y: r.maxY), horizontal: true)
            edgeHandle(center: CGPoint(x: r.minX, y: r.midY), horizontal: false)
            edgeHandle(center: CGPoint(x: r.maxX, y: r.midY), horizontal: false)
        }
    }

    private func cornerHandle(at point: CGPoint, xDir: CGFloat, yDir: CGFloat) -> some View {
        Path { path in
            path.move(to: point)
            path.addLine(to: CGPoint(x: point.x + handleLength * xDir, y: point.y))
            path.move(to: point)
            path.addLine(to: CGPoint(x: point.x, y: point.y + handleLength * yDir))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: handleThickness, lineCap: .round))
    }

    private func edgeHandle(center: CGPoint, horizontal: Bool) -> some View {
        let half = handleLength / 2
        return Path { path in
            if horizontal {
                path.move(to: CGPoint(x: center.x - half, y: center.y))
                path.addLine(to: CGPoint(x: center.x + half, y: center.y))
            } else {
                path.move(to: CGPoint(x: center.x, y: center.y - half))
                path.addLine(to: CGPoint(x: center.x, y: center.y + half))
            }
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: handleThickness, lineCap: .round))
    }

    // MARK: - Border

    private var cropBorder: some View {
        Rectangle()
            .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
            .frame(width: cropRect.width, height: cropRect.height)
            .position(x: cropRect.midX, y: cropRect.midY)
    }
}

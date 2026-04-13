import SwiftUI

/// Screen-space crop handles drawn OUTSIDE the scale/offset transform chain.
///
/// All dimensions scale proportionally with the screen-space crop rect so that
/// the visual ratio of handle-size to crop-size stays consistent at any zoom.
///
/// Conforms to `Animatable` so SwiftUI smoothly interpolates handle positions
/// and sizes when the crop rect or view transform is animated.
struct CropHandlesView: View, @preconcurrency Animatable {
    var screenCropRect: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            .init(.init(screenCropRect.origin.x, screenCropRect.origin.y),
                  .init(screenCropRect.size.width, screenCropRect.size.height))
        }
        set {
            screenCropRect = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    // MARK: - Proportional dimensions

    /// Short side of the screen-space crop rect, drives all proportional sizing.
    private var shortSide: CGFloat {
        min(screenCropRect.width, screenCropRect.height)
    }

    /// Corner/edge handle arm length — 12% of short side, min 28pt for HIG tappability.
    private var handleLength: CGFloat {
        min(max(shortSide * 0.12, 28), 44)
    }

    /// Handle stroke thickness — bold enough to be visually grabbable.
    private var handleThickness: CGFloat {
        min(max(shortSide * 0.025, 5), 8)
    }

    /// Border line thickness — proportional but thinner than handles.
    private var borderThickness: CGFloat {
        min(max(shortSide * 0.006, 1), 2)
    }

    var body: some View {
        ZStack {
            borderPath
            handlePath
            moveIndicatorPill
            moveIndicatorLines
        }
        .allowsHitTesting(false)
    }

    // MARK: - Border (screen-space, scales with handles)

    private var borderPath: some View {
        Path { path in
            path.addRect(screenCropRect)
        }
        .stroke(Color.white.opacity(0.7), lineWidth: borderThickness)
    }

    // MARK: - Corner + edge handles

    /// Draws tapered corner L-brackets that transition from thick handle → thin
    /// border, plus edge midpoint bars.  All filled shapes, not strokes, so the
    /// taper is smooth.
    private var handlePath: some View {
        let r = screenCropRect
        let thin = borderThickness / 2
        let thick = handleThickness / 2

        return Path { path in
            // Corners — tapered L-brackets
            taperCorner(&path, at: CGPoint(x: r.minX, y: r.minY), xDir: 1, yDir: 1,
                        armLen: handleLength, thick: thick, thin: thin)
            taperCorner(&path, at: CGPoint(x: r.maxX, y: r.minY), xDir: -1, yDir: 1,
                        armLen: handleLength, thick: thick, thin: thin)
            taperCorner(&path, at: CGPoint(x: r.minX, y: r.maxY), xDir: 1, yDir: -1,
                        armLen: handleLength, thick: thick, thin: thin)
            taperCorner(&path, at: CGPoint(x: r.maxX, y: r.maxY), xDir: -1, yDir: -1,
                        armLen: handleLength, thick: thick, thin: thin)

            // Edge bars — bottom, left, right (no top — move indicator replaces it)
            edgeBar(&path, center: CGPoint(x: r.midX, y: r.maxY), horizontal: true,
                    barLen: handleLength, thick: thick, thin: thin)
            edgeBar(&path, center: CGPoint(x: r.minX, y: r.midY), horizontal: false,
                    barLen: handleLength, thick: thick, thin: thin)
            edgeBar(&path, center: CGPoint(x: r.maxX, y: r.midY), horizontal: false,
                    barLen: handleLength, thick: thick, thin: thin)
        }
        .fill(Color.accentColor)
    }

    /// A single corner L-bracket drawn as two filled trapezoids that taper from
    /// `thick` (at the corner) to `thin` (at the arm ends).
    private func taperCorner(
        _ path: inout Path,
        at pt: CGPoint,
        xDir: CGFloat, yDir: CGFloat,
        armLen: CGFloat,
        thick: CGFloat, thin: CGFloat
    ) {
        // Horizontal arm
        let hEnd = CGPoint(x: pt.x + armLen * xDir, y: pt.y)
        path.move(to: CGPoint(x: pt.x, y: pt.y - thick * yDir))
        path.addLine(to: CGPoint(x: hEnd.x, y: hEnd.y - thin * yDir))
        path.addLine(to: CGPoint(x: hEnd.x, y: hEnd.y + thin * yDir))
        path.addLine(to: CGPoint(x: pt.x, y: pt.y + thick * yDir))
        path.closeSubpath()

        // Vertical arm
        let vEnd = CGPoint(x: pt.x, y: pt.y + armLen * yDir)
        path.move(to: CGPoint(x: pt.x - thick * xDir, y: pt.y))
        path.addLine(to: CGPoint(x: vEnd.x - thin * xDir, y: vEnd.y))
        path.addLine(to: CGPoint(x: vEnd.x + thin * xDir, y: vEnd.y))
        path.addLine(to: CGPoint(x: pt.x + thick * xDir, y: pt.y))
        path.closeSubpath()
    }

    /// Midpoint bar drawn as a filled shape, thick at center tapering to thin at ends.
    private func edgeBar(
        _ path: inout Path,
        center: CGPoint,
        horizontal: Bool,
        barLen: CGFloat,
        thick: CGFloat, thin: CGFloat
    ) {
        let half = barLen / 2
        if horizontal {
            // Horizontal bar (top/bottom edge)
            path.move(to: CGPoint(x: center.x - half, y: center.y - thin))
            path.addLine(to: CGPoint(x: center.x - half * 0.4, y: center.y - thick))
            path.addLine(to: CGPoint(x: center.x + half * 0.4, y: center.y - thick))
            path.addLine(to: CGPoint(x: center.x + half, y: center.y - thin))
            path.addLine(to: CGPoint(x: center.x + half, y: center.y + thin))
            path.addLine(to: CGPoint(x: center.x + half * 0.4, y: center.y + thick))
            path.addLine(to: CGPoint(x: center.x - half * 0.4, y: center.y + thick))
            path.addLine(to: CGPoint(x: center.x - half, y: center.y + thin))
            path.closeSubpath()
        } else {
            // Vertical bar (left/right edge)
            path.move(to: CGPoint(x: center.x - thin, y: center.y - half))
            path.addLine(to: CGPoint(x: center.x - thick, y: center.y - half * 0.4))
            path.addLine(to: CGPoint(x: center.x - thick, y: center.y + half * 0.4))
            path.addLine(to: CGPoint(x: center.x - thin, y: center.y + half))
            path.addLine(to: CGPoint(x: center.x + thin, y: center.y + half))
            path.addLine(to: CGPoint(x: center.x + thick, y: center.y + half * 0.4))
            path.addLine(to: CGPoint(x: center.x + thick, y: center.y - half * 0.4))
            path.addLine(to: CGPoint(x: center.x + thin, y: center.y - half))
            path.closeSubpath()
        }
    }

    // MARK: - Move indicator (3-line grab bar with background pill)

    private var moveIndicatorPill: some View {
        let cx = screenCropRect.midX
        let cy = screenCropRect.minY + 14
        let pillWidth: CGFloat = 28
        let pillHeight: CGFloat = 18

        return Path { path in
            path.addRoundedRect(
                in: CGRect(
                    x: cx - pillWidth / 2,
                    y: cy - pillHeight / 2,
                    width: pillWidth,
                    height: pillHeight
                ),
                cornerSize: CGSize(width: pillHeight / 2, height: pillHeight / 2)
            )
        }
        .fill(Color.accentColor.opacity(0.2))
    }

    private var moveIndicatorLines: some View {
        let cx = screenCropRect.midX
        let cy = screenCropRect.minY + 14
        let lineWidth: CGFloat = 16
        let spacing: CGFloat = 3.5

        return Path { path in
            for i in -1 ... 1 {
                let y = cy + CGFloat(i) * spacing
                path.move(to: CGPoint(x: cx - lineWidth / 2, y: y))
                path.addLine(to: CGPoint(x: cx + lineWidth / 2, y: y))
            }
        }
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
}

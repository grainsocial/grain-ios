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
    var showGrid: Bool
    /// `min(frameWidth, frameHeight) * imageScale` — drives stroke/thickness.
    /// Animatable so it morphs in lockstep with `screenCropRect` instead of
    /// snapping to its final value in one frame.
    var zoomReference: CGFloat
    /// Caller-supplied short side. Kept as input (not derived from
    /// `screenCropRect`) so rotation can override the value being interpolated.
    var cropShortSide: CGFloat

    var animatableData: AnimatablePair<
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            .init(
                .init(.init(screenCropRect.origin.x, screenCropRect.origin.y),
                      .init(screenCropRect.size.width, screenCropRect.size.height)),
                .init(zoomReference, cropShortSide)
            )
        }
        set {
            screenCropRect = CGRect(
                x: newValue.first.first.first,
                y: newValue.first.first.second,
                width: newValue.first.second.first,
                height: newValue.first.second.second
            )
            zoomReference = newValue.second.first
            cropShortSide = newValue.second.second
        }
    }

    // MARK: - Proportional dimensions

    /// Full arm length — zoom-driven. Used for edge bar sizing and thresholds.
    private var fullHandleLength: CGFloat {
        min(max(zoomReference * 0.12, 28), 44)
    }

    /// Corner bracket arm length — stays at full size while edge bars are
    /// visible, then shrinks proportionally after they're fully gone.
    private var handleLength: CGFloat {
        let edgeBarsGone = fullHandleLength * 3
        if cropShortSide >= edgeBarsGone { return fullHandleLength }
        let minArm = max(fullHandleLength * 0.45, 14)
        let t = cropShortSide / max(edgeBarsGone, 1)
        return minArm + (fullHandleLength - minArm) * t
    }

    /// Handle stroke thickness — zoom-driven (constant regardless of crop size).
    private var handleThickness: CGFloat {
        min(max(zoomReference * 0.025, 5), 8)
    }

    /// Border line thickness — zoom-driven.
    private var borderThickness: CGFloat {
        min(max(zoomReference * 0.006, 1), 2)
    }

    /// Half-width at the tapered arm end — follows thickness (zoom-driven).
    private var armEndHalf: CGFloat {
        handleThickness * 0.3
    }

    /// Length of the constant-width section before the taper begins.
    private var armConstant: CGFloat {
        handleLength * 0.35
    }

    var body: some View {
        ZStack {
            // Dim mask + grid drawn in the same screen-space coordinate
            // system as the handles — impossible to desync.
            dimmingMask
            if showGrid { gridLines }

            // Handles + border + move indicator
            ZStack {
                borderPath
                cornerHandlePath
                edgeBarViews
            }
            .shadow(color: .black.opacity(0.6), radius: 1.5, x: 0, y: 0.5)

            moveIndicatorPill
            moveIndicatorLines
        }
        .allowsHitTesting(false)
        // Per-frame handle-sizing telemetry. screenCropRect is the animatable
        // property — fires on every animation tick so Instruments captures
        // the full size morph (including any non-monotonic "up/down").
        .onChange(of: screenCropRect) { _, _ in
            cropViewSignposter.emitEvent(
                "HandleFrame",
                "zoomRef=\(zoomReference, format: .fixed(precision: 1)) cropShort=\(cropShortSide, format: .fixed(precision: 1)) fullLen=\(fullHandleLength, format: .fixed(precision: 1)) handleLen=\(handleLength, format: .fixed(precision: 1)) thick=\(handleThickness, format: .fixed(precision: 1)) showH=\(showHBars) showV=\(showVBars)"
            )
        }
    }

    // MARK: - Border (screen-space, scales with handles)

    private var borderPath: some View {
        Path { path in
            path.addRect(screenCropRect)
        }
        .stroke(Color.white.opacity(0.7), lineWidth: borderThickness)
    }

    // MARK: - Corner handles

    private var cornerHandlePath: some View {
        let r = screenCropRect
        let thin = borderThickness / 2
        let thick = handleThickness / 2

        return Path { path in
            cornerBracket(&path, at: CGPoint(x: r.minX, y: r.minY), xDir: 1, yDir: 1,
                          armLen: handleLength, thick: thick, thin: thin)
            cornerBracket(&path, at: CGPoint(x: r.maxX, y: r.minY), xDir: -1, yDir: 1,
                          armLen: handleLength, thick: thick, thin: thin)
            cornerBracket(&path, at: CGPoint(x: r.minX, y: r.maxY), xDir: 1, yDir: -1,
                          armLen: handleLength, thick: thick, thin: thin)
            cornerBracket(&path, at: CGPoint(x: r.maxX, y: r.maxY), xDir: -1, yDir: -1,
                          armLen: handleLength, thick: thick, thin: thin)
        }
        .fill(Color.white)
    }

    // MARK: - Edge bars (separate views for insert/remove transitions)

    private var showHBars: Bool {
        screenCropRect.width >= fullHandleLength * 4
    }

    private var showVBars: Bool {
        screenCropRect.height >= fullHandleLength * 4
    }

    private var edgeBarViews: some View {
        let r = screenCropRect
        let thick = handleThickness / 2
        let thin = borderThickness / 2
        let fhl = fullHandleLength

        // Bars are always drawn — visibility is purely opacity.
        return ZStack {
            Path { path in
                edgeBar(&path, center: CGPoint(x: r.midX, y: r.maxY), horizontal: true,
                        barLen: fhl, thick: thick, thin: thin)
            }
            .fill(Color.white)
            .opacity(showHBars ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: showHBars)

            Path { path in
                edgeBar(&path, center: CGPoint(x: r.minX, y: r.midY), horizontal: false,
                        barLen: fhl, thick: thick, thin: thin)
                edgeBar(&path, center: CGPoint(x: r.maxX, y: r.midY), horizontal: false,
                        barLen: fhl, thick: thick, thin: thin)
            }
            .fill(Color.white)
            .opacity(showVBars ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: showVBars)
        }
    }

    /// A single corner L-bracket as one continuous 10-vertex polygon.
    /// Both arms have a constant-width section near the corner that
    /// tapers to `armEndHalf` at the tips.
    private func cornerBracket(
        _ path: inout Path,
        at pt: CGPoint,
        xDir: CGFloat, yDir: CGFloat,
        armLen: CGFloat,
        thick: CGFloat, thin _: CGFloat
    ) {
        let endHalf = armEndHalf
        let constLen = armConstant
        let taperLen = armLen - constLen

        // Key points along horizontal arm
        let hConst = CGPoint(x: pt.x + constLen * xDir, y: pt.y)
        let hEnd = CGPoint(x: pt.x + armLen * xDir, y: pt.y)

        // Key points along vertical arm
        let vConst = CGPoint(x: pt.x, y: pt.y + constLen * yDir)
        let vEnd = CGPoint(x: pt.x, y: pt.y + armLen * yDir)

        // Corner rounding radius — proportional to thickness
        let cornerR = thick * 0.5
        // Tip rounding radius — smaller
        let tipR = endHalf * 0.8

        // 10-vertex L-bracket polygon, clockwise from horizontal arm outer tip
        let vertices: [CGPoint] = [
            // Horizontal arm — outer edge (away from corner center)
            CGPoint(x: hEnd.x, y: hEnd.y - endHalf * yDir), // 0: h-arm tip outer
            CGPoint(x: hConst.x, y: hConst.y - thick * yDir), // 1: h-arm constant outer
            // Inner corner junction
            CGPoint(x: pt.x - thick * xDir, y: pt.y - thick * yDir), // 2: outer corner
            // Vertical arm — outer edge
            CGPoint(x: vConst.x - thick * xDir, y: vConst.y), // 3: v-arm constant outer
            CGPoint(x: vEnd.x - endHalf * xDir, y: vEnd.y), // 4: v-arm tip outer
            // Vertical arm — inner edge
            CGPoint(x: vEnd.x + endHalf * xDir, y: vEnd.y), // 5: v-arm tip inner
            CGPoint(x: vConst.x + thick * xDir, y: vConst.y), // 6: v-arm constant inner
            // Inner L junction
            CGPoint(x: pt.x + thick * xDir, y: pt.y + thick * yDir), // 7: inner corner
            // Horizontal arm — inner edge
            CGPoint(x: hConst.x, y: hConst.y + thick * yDir), // 8: h-arm constant inner
            CGPoint(x: hEnd.x, y: hEnd.y + endHalf * yDir), // 9: h-arm tip inner
        ]

        // Per-vertex corner radii
        let radii: [CGFloat] = [
            tipR, // 0: h-tip outer
            taperLen > 1 ? cornerR * 0.3 : 0, // 1: start of taper
            cornerR, // 2: outer corner
            taperLen > 1 ? cornerR * 0.3 : 0, // 3: start of taper
            tipR, // 4: v-tip outer
            tipR, // 5: v-tip inner
            taperLen > 1 ? cornerR * 0.3 : 0, // 6: start of taper
            cornerR, // 7: inner corner
            taperLen > 1 ? cornerR * 0.3 : 0, // 8: start of taper
            tipR, // 9: h-tip inner
        ]

        roundedPolygon(&path, points: vertices, radii: radii)
    }

    /// Midpoint bar drawn as a rounded polygon, thick at center tapering to thin at ends.
    private func edgeBar(
        _ path: inout Path,
        center: CGPoint,
        horizontal: Bool,
        barLen: CGFloat,
        thick: CGFloat, thin _: CGFloat
    ) {
        let half = barLen / 2
        let endHalf = armEndHalf
        let tipR = endHalf * 0.8
        let transR = thick * 0.3

        if horizontal {
            let vertices: [CGPoint] = [
                CGPoint(x: center.x - half, y: center.y - endHalf),
                CGPoint(x: center.x - half * 0.4, y: center.y - thick),
                CGPoint(x: center.x + half * 0.4, y: center.y - thick),
                CGPoint(x: center.x + half, y: center.y - endHalf),
                CGPoint(x: center.x + half, y: center.y + endHalf),
                CGPoint(x: center.x + half * 0.4, y: center.y + thick),
                CGPoint(x: center.x - half * 0.4, y: center.y + thick),
                CGPoint(x: center.x - half, y: center.y + endHalf),
            ]
            let radii: [CGFloat] = [tipR, transR, transR, tipR, tipR, transR, transR, tipR]
            roundedPolygon(&path, points: vertices, radii: radii)
        } else {
            let vertices: [CGPoint] = [
                CGPoint(x: center.x - endHalf, y: center.y - half),
                CGPoint(x: center.x - thick, y: center.y - half * 0.4),
                CGPoint(x: center.x - thick, y: center.y + half * 0.4),
                CGPoint(x: center.x - endHalf, y: center.y + half),
                CGPoint(x: center.x + endHalf, y: center.y + half),
                CGPoint(x: center.x + thick, y: center.y + half * 0.4),
                CGPoint(x: center.x + thick, y: center.y - half * 0.4),
                CGPoint(x: center.x + endHalf, y: center.y - half),
            ]
            let radii: [CGFloat] = [tipR, transR, transR, tipR, tipR, transR, transR, tipR]
            roundedPolygon(&path, points: vertices, radii: radii)
        }
    }

    /// Draw a closed polygon with per-vertex corner rounding using tangent arcs.
    private func roundedPolygon(_ path: inout Path, points: [CGPoint], radii: [CGFloat]) {
        guard points.count >= 3 else { return }
        let n = points.count

        // Start at the midpoint of the edge approaching vertex 0
        let startX = (points[n - 1].x + points[0].x) / 2
        let startY = (points[n - 1].y + points[0].y) / 2
        path.move(to: CGPoint(x: startX, y: startY))

        for i in 0 ..< n {
            let curr = points[i]
            let next = points[(i + 1) % n]
            let r = radii[i]

            if r > 0.1 {
                path.addArc(tangent1End: curr, tangent2End: next, radius: r)
            } else {
                path.addLine(to: curr)
            }
        }
        path.closeSubpath()
    }

    // MARK: - Dim mask (screen-space, synced with handles)

    /// Extends well beyond the view frame so zoomed images are still dimmed.
    private var dimmingMask: some View {
        let overflow: CGFloat = 2000
        return Path { path in
            path.addRect(CGRect(
                x: -overflow,
                y: -overflow,
                width: screenCropRect.width + overflow * 4,
                height: screenCropRect.height + overflow * 4
            ))
            path.addRect(screenCropRect)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
    }

    // MARK: - Grid (screen-space, synced with handles)

    private var gridLines: some View {
        Path { path in
            let r = screenCropRect
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

    // MARK: - Move indicator (3-line grab bar with background pill)

    /// Pill height (capsule short-axis) — a touch larger than the old fixed 18pt.
    private var pillHeight: CGFloat {
        22
    }

    /// Pill width: straight section = handleLength (matches edge bar length) + 2 × radius.
    private var pillWidth: CGFloat {
        handleLength + pillHeight
    }

    /// Line width for the 3-line grab indicator: spans 80 % of the straight section.
    private var indicatorLineWidth: CGFloat {
        handleLength * 0.8
    }

    /// Vertical center of the pill — locked inside the crop rect, just
    /// below the top edge. No toolbar-overlap concerns since it never
    /// leaves the crop area.
    private var moveIndicatorCY: CGFloat {
        screenCropRect.minY + pillHeight / 2 + 6
    }

    private var moveIndicatorPill: some View {
        Capsule()
            .glassEffect(.regular, in: .capsule)
            .frame(width: pillWidth, height: pillHeight)
            .position(x: screenCropRect.midX, y: moveIndicatorCY)
    }

    private var moveIndicatorLines: some View {
        let cx = screenCropRect.midX
        let cy = moveIndicatorCY
        let lw = indicatorLineWidth
        let spacing: CGFloat = 4

        return Path { path in
            for i in -1 ... 1 {
                let y = cy + CGFloat(i) * spacing
                path.move(to: CGPoint(x: cx - lw / 2, y: y))
                path.addLine(to: CGPoint(x: cx + lw / 2, y: y))
            }
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
}

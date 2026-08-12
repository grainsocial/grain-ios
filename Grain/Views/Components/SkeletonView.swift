import SwiftUI

// MARK: - Shimmer

/// Sweeps a soft highlight band across a placeholder shape. A slow, steady
/// wave in the reading direction is the variant users perceive as fastest —
/// pulsing and rapid motion both test worse. Honors Reduce Motion by falling
/// back to a static fill.
private struct Shimmer: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var phase: CGFloat = 0

    private var highlight: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .white.opacity(0.7)
    }

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay {
                    GeometryReader { geo in
                        let width = geo.size.width
                        let band = max(width * 0.45, 60)
                        LinearGradient(
                            colors: [.clear, highlight, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: band)
                        .offset(x: layoutDirection == .rightToLeft
                            ? width - phase * (width + band)
                            : -band + phase * (width + band))
                    }
                    .allowsHitTesting(false)
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}

extension View {
    /// Animated loading sweep. Apply to a filled shape, then clip it.
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}

// MARK: - Flash guard

/// Holds back a loading placeholder for a beat so quick loads show nothing at
/// all instead of a gray flash. Matches the usual ladder: nothing under
/// ~200ms, placeholder beyond it.
struct DelayedSkeleton<Content: View>: View {
    var delay: Duration = .milliseconds(150)
    @ViewBuilder var content: () -> Content
    @State private var visible = false

    var body: some View {
        ZStack {
            if visible {
                content()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: visible)
        .task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            visible = true
        }
    }
}

// MARK: - Building blocks

/// Rounded placeholder bar — use for text lines, buttons, thumbnails.
struct SkeletonBar: View {
    var width: CGFloat?
    var height: CGFloat = 12
    var cornerRadius: CGFloat = 6

    var body: some View {
        Rectangle()
            .fill(Color(.tertiarySystemFill))
            .shimmering()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }
}

/// Circular placeholder — use for avatars.
struct SkeletonCircle: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(.tertiarySystemFill))
            .shimmering()
            .clipShape(Circle())
            .frame(width: size, height: size)
    }
}

/// Placeholder tile matching the 3-up gallery grid cells.
struct SkeletonGrid: View {
    var rows: Int = 3
    var columns: Int = 3
    var aspectRatio: CGFloat = 3.0 / 4.0

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns), spacing: 2) {
            ForEach(0 ..< (rows * columns), id: \.self) { _ in
                Rectangle()
                    .fill(Color(.tertiarySystemFill))
                    .shimmering()
                    .aspectRatio(aspectRatio, contentMode: .fit)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 16) {
            SkeletonCircle(size: 80)
            SkeletonBar(height: 40, cornerRadius: 10)
        }
        SkeletonBar(width: 140, height: 14)
        SkeletonBar(width: 100)
        SkeletonGrid(rows: 2)
    }
    .padding()
    .grainPreview()
}

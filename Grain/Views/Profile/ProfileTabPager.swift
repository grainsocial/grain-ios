import SwiftUI

/// What a swipe between the profile's tabs writes on every frame.
///
/// Kept off `ProfileView`'s `@State` on purpose. Anything the screen's body
/// reads re-evaluates the whole screen when it changes, and a swipe changes
/// the offset a hundred times a second. Only `ProfileTabBar` and
/// `ProfilePagerHeight` read these, so those two are all a swipe re-evaluates.
@MainActor
@Observable
final class ProfilePagerState {
    /// Horizontal content offset of the pager.
    var offsetX: CGFloat = 0
    /// Width of one page; zero until laid out.
    var pageWidth: CGFloat = 0
    /// Measured height of each page's content.
    var pageHeights: [ProfileViewMode: CGFloat] = [:]
    /// Whether the tab bar has scrolled up past the top of the viewport, which
    /// decides whether a tab change scrolls back to it.
    var scrolledPastTop = false

    static let modes: [ProfileViewMode] = [.grid, .favorites, .stories]

    /// Position across the pages as a fraction: 0 is the first page, 1 the
    /// second. Falls back to the selected mode until the pager has a width.
    func progress(selected: ProfileViewMode) -> CGFloat {
        guard pageWidth > 0 else {
            return CGFloat(Self.modes.firstIndex(of: selected) ?? 0)
        }
        return max(0, min(offsetX / pageWidth, CGFloat(Self.modes.count - 1)))
    }

    func activeIndex(selected: ProfileViewMode) -> Int {
        Int(progress(selected: selected).rounded())
    }

    /// Height the pager should be at the current offset: the two pages the
    /// swipe is between, blended by how far it is between them.
    func interpolatedHeight(selected: ProfileViewMode) -> CGFloat {
        let fallback: CGFloat = 200
        let heights = Self.modes.map { pageHeights[$0] ?? fallback }
        let progress = progress(selected: selected)
        let lower = Int(progress.rounded(.down))
        let upper = min(lower + 1, Self.modes.count - 1)
        let fraction = progress - CGFloat(lower)
        return max(heights[lower] * (1 - fraction) + heights[upper] * fraction, fallback)
    }
}

/// The three tab buttons and the indicator that tracks the swipe beneath them.
struct ProfileTabBar: View {
    let pager: ProfilePagerState
    let selected: ProfileViewMode
    let onSelect: (ProfileViewMode) -> Void

    var body: some View {
        let modes = ProfilePagerState.modes
        let activeIndex = pager.activeIndex(selected: selected)

        HStack(spacing: 0) {
            ForEach(Array(modes.enumerated()), id: \.element) { index, mode in
                button(mode, isActive: index == activeIndex)
            }
        }
        .overlay(alignment: .bottomLeading) {
            GeometryReader { tabBarGeo in
                let tabWidth = tabBarGeo.size.width / CGFloat(modes.count)
                let indicatorWidth: CGFloat = 32
                let xOffset = pager.progress(selected: selected) * tabWidth + (tabWidth - indicatorWidth) / 2
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: indicatorWidth, height: 2.5)
                    .offset(x: xOffset, y: -6)
            }
            .frame(height: 2.5)
            .allowsHitTesting(false)
        }
    }

    private func button(_ mode: ProfileViewMode, isActive: Bool) -> some View {
        Button {
            onSelect(mode)
        } label: {
            Image(systemName: isActive ? icon(for: mode) + ".fill" : icon(for: mode))
                .font(.system(size: 22))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.rawValue.capitalized)")
    }

    private func icon(for mode: ProfileViewMode) -> String {
        switch mode {
        case .grid: "square.grid.3x3"
        case .favorites: "heart"
        case .stories: "clock"
        }
    }
}

/// Sizes the pager to the blend of its pages' heights at the current swipe
/// offset. A modifier rather than a `frame` in the parent's body so that the
/// per-frame read of the offset re-evaluates this, not the pages under it.
struct ProfilePagerHeight: ViewModifier {
    let pager: ProfilePagerState
    let selected: ProfileViewMode

    func body(content: Content) -> some View {
        content.frame(height: pager.interpolatedHeight(selected: selected), alignment: .top)
    }
}

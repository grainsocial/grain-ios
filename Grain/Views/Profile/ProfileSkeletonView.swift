import SwiftUI

/// Placeholder that mirrors `ProfileView`'s real layout while the profile
/// loads, so content lands in place instead of popping in after a spinner.
struct ProfileSkeletonView: View {
    /// Own profile shows the grid/favorites/stories tab bar above the grid.
    var showsTabBar = false

    var body: some View {
        VStack(spacing: 12) {
            // Avatar + stats row
            HStack(alignment: .center, spacing: 16) {
                SkeletonCircle(size: 80)
                    .padding(4)

                HStack(spacing: 0) {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        VStack(spacing: 6) {
                            SkeletonBar(width: 28, height: 14)
                            SkeletonBar(width: 54, height: 10)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Name + handle + bio
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBar(width: 150, height: 14)
                SkeletonBar(width: 110, height: 12)
                SkeletonBar(height: 12)
                    .padding(.top, 4)
                SkeletonBar(width: 220, height: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            // Action button row
            SkeletonBar(height: 34, cornerRadius: 10)
                .padding(.horizontal)
                .padding(.top, 2)

            if showsTabBar {
                HStack(spacing: 0) {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        SkeletonBar(width: 24, height: 22, cornerRadius: 5)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 14)
            }

            SkeletonGrid()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading profile")
    }
}

#Preview {
    ScrollView {
        ProfileSkeletonView(showsTabBar: true)
    }
    .grainPreview()
}

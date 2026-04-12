import SwiftUI

/// Horizontal bar with aspect ratio preset chips, portrait/landscape toggle,
/// and a lock button. Floats above the image with liquid glass.
struct AspectRatioBar: View {
    @Bindable var state: CropState

    var body: some View {
        HStack(spacing: 10) {
            // Lock toggle
            Button {
                state.toggleRatioLock()
            } label: {
                Image(systemName: state.isRatioLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(state.isRatioLocked ? .white : .secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .glassEffect(.regular.interactive(), in: .circle)

            // Portrait/landscape toggle — only for ratios that aren't square or free
            if state.showOrientationToggle {
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        state.toggleOrientation()
                    }
                } label: {
                    Image(systemName: state.isPortrait ? "rectangle.portrait" : "rectangle.landscape.rotate")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }

            // Preset chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AspectRatioPreset.allPresets) { preset in
                        Button {
                            withAnimation(.smooth(duration: 0.3)) {
                                state.selectPreset(preset)
                            }
                        } label: {
                            Text(preset.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(
                                    state.selectedPreset == preset ? .white : .secondary
                                )
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .contentShape(Capsule())
                        }
                        .glassEffect(
                            state.selectedPreset == preset
                                ? .regular.interactive()
                                : .regular,
                            in: .capsule
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

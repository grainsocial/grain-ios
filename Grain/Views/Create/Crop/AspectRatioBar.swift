import SwiftUI

/// Horizontal strip of aspect ratio preset chips with a lock toggle.
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
                    .foregroundStyle(state.isRatioLocked ? .white : .white.opacity(0.35))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .glassEffect(state.isRatioLocked ? .regular.interactive() : .regular, in: .circle)

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
                                    state.selectedPreset == preset
                                        ? .white
                                        : .white.opacity(0.35)
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

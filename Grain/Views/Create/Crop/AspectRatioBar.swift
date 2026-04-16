import SwiftUI

/// Horizontal strip of aspect ratio preset chips.
struct AspectRatioBar: View {
    @Bindable var state: CropState

    var body: some View {
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
                                    ? .primary
                                    : .tertiary
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
        .padding(.horizontal, 16)
    }
}

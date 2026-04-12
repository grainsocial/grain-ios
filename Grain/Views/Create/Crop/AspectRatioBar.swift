import SwiftUI

/// Horizontal bar with aspect ratio preset chips and a lock toggle.
struct AspectRatioBar: View {
    @Bindable var state: CropState

    var body: some View {
        HStack(spacing: 12) {
            Button {
                state.toggleRatioLock()
            } label: {
                Image(systemName: state.isRatioLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(state.isRatioLocked ? Color.white : .secondary)
            }

            Divider()
                .frame(height: 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AspectRatioPreset.allCases) { preset in
                        Button {
                            state.selectPreset(preset)
                        } label: {
                            Text(preset.rawValue)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    state.selectedPreset == preset
                                        ? Color.white.opacity(0.2)
                                        : Color.clear,
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    state.selectedPreset == preset ? .white : .secondary
                                )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

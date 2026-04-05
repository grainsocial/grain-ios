import SwiftUI

struct StoryRingView<Content: View>: View {
    let hasStory: Bool
    var viewed: Bool = false
    let size: CGFloat
    @ViewBuilder let content: () -> Content

    private var lineWidth: CGFloat {
        size <= 28 ? 1.5 : size <= 40 ? 2.5 : 3.5
    }

    private var ringSize: CGFloat {
        size + (size <= 28 ? 4 : size <= 40 ? 6 : 8)
    }

    var body: some View {
        content()
            .overlay {
                if hasStory {
                    if viewed {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.4), lineWidth: lineWidth)
                            .frame(width: ringSize, height: ringSize)
                    } else {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0xC9 / 255, green: 0x7C / 255, blue: 0xF8 / 255),
                                        Color(red: 0x85 / 255, green: 0xA1 / 255, blue: 0xFF / 255),
                                        Color(red: 0x5B / 255, green: 0xF0 / 255, blue: 0xD6 / 255),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: lineWidth
                            )
                            .frame(width: ringSize, height: ringSize)
                    }
                }
            }
    }
}

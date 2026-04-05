import SwiftUI

struct StoryRingView<Content: View>: View {
    let hasStory: Bool
    var viewed: Bool = false
    let size: CGFloat
    @ViewBuilder let content: () -> Content

    private var lineWidth: CGFloat { size <= 28 ? 1.5 : size <= 40 ? 2.5 : 3.5 }
    private var ringSize: CGFloat { size + (size <= 28 ? 4 : size <= 40 ? 6 : 8) }

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
                                        Color(red: 0xc9/255, green: 0x7c/255, blue: 0xf8/255),
                                        Color(red: 0x85/255, green: 0xa1/255, blue: 0xff/255),
                                        Color(red: 0x5b/255, green: 0xf0/255, blue: 0xd6/255)
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

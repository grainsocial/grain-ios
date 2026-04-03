import SwiftUI

struct StoryRingView<Content: View>: View {
    let hasStory: Bool
    let size: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .overlay {
                if hasStory {
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
                            lineWidth: size <= 28 ? 1.5 : size <= 40 ? 2.5 : 3.5
                        )
                        .frame(width: size + (size <= 28 ? 4 : size <= 40 ? 6 : 8), height: size + (size <= 28 ? 4 : size <= 40 ? 6 : 8))
                }
            }
    }
}

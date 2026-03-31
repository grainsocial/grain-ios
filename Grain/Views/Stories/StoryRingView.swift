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
                            lineWidth: 2.5
                        )
                        .frame(width: size + 6, height: size + 6)
                }
            }
    }
}

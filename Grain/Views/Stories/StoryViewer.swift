import SwiftUI
import NukeUI

struct StoryViewer: View {
    let stories: [GrainStory]
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(stories: [GrainStory], startIndex: Int = 0) {
        self.stories = stories
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if currentIndex < stories.count {
                let story = stories[currentIndex]

                LazyImage(url: URL(string: story.fullsize)) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(story.aspectRatio.ratio, contentMode: .fit)
                    } else if state.isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                }

                // Progress indicators + creator info
                VStack {
                    HStack(spacing: 4) {
                        ForEach(0..<stories.count, id: \.self) { index in
                            Capsule()
                                .fill(index <= currentIndex ? Color.white : Color.white.opacity(0.3))
                                .frame(height: 2)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Creator info with glass effect
                    HStack {
                        AvatarView(url: story.creator.avatar, size: 32)
                        Text(story.creator.displayName ?? story.creator.handle)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .liquidGlass()
                    .padding(.horizontal)

                    Spacer()

                    // Location pill at bottom
                    if let address = story.address {
                        HStack {
                            Image(systemName: "location.fill")
                            Text(address.locality ?? address.name ?? address.country)
                        }
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .liquidGlass()
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    if value.translation.width < -50 {
                        if currentIndex < stories.count - 1 {
                            currentIndex += 1
                        } else {
                            dismiss()
                        }
                    } else if value.translation.width > 50 {
                        if currentIndex > 0 {
                            currentIndex -= 1
                        }
                    } else {
                        if value.startLocation.x > UIScreen.main.bounds.width / 2 {
                            if currentIndex < stories.count - 1 { currentIndex += 1 } else { dismiss() }
                        } else {
                            if currentIndex > 0 { currentIndex -= 1 }
                        }
                    }
                }
        )
        .statusBarHidden()
    }
}

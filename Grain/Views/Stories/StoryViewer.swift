import SwiftUI
import NukeUI

struct StoryViewer: View {
    @Environment(AuthManager.self) private var auth
    let authors: [GrainStoryAuthor]
    let client: XRPCClient
    var onProfileTap: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    @State private var currentAuthorIndex: Int
    @State private var currentStoryIndex = 0
    @State private var stories: [GrainStory] = []
    @State private var isLoadingStories = false
    @State private var progress: CGFloat = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var showDeleteConfirm = false
    @State private var lastNavTime: Date = .distantPast

    private let storyDuration: TimeInterval = 5.0

    init(authors: [GrainStoryAuthor], startIndex: Int = 0, client: XRPCClient, onProfileTap: ((String) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.authors = authors
        self.client = client
        self.onProfileTap = onProfileTap
        self.onDismiss = onDismiss
        _currentAuthorIndex = State(initialValue: startIndex)
    }

    private var currentStory: GrainStory? {
        guard currentStoryIndex < stories.count else { return nil }
        return stories[currentStoryIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let story = currentStory {
                // Story image
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

                // Overlay UI
                VStack(spacing: 0) {
                    // Progress bars
                    HStack(spacing: 4) {
                        ForEach(0..<stories.count, id: \.self) { index in
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Color.white.opacity(0.3))
                                Capsule()
                                    .fill(Color.white)
                                    .frame(width: barWidth(for: index, totalWidth: geo.size.width))
                            }
                            .frame(height: 2)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Creator info
                    HStack(alignment: .center) {
                        Button {
                            close()
                            onProfileTap?(story.creator.did)
                        } label: {
                            HStack(alignment: .center, spacing: 8) {
                                AvatarView(url: story.creator.avatar, size: 32)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(story.creator.displayName ?? story.creator.handle)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                    Text(relativeTime(story.createdAt))
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                        }
                        Spacer()

                        if story.creator.did == auth.userDID {
                            Button {
                                timerTask?.cancel()
                                showDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.white)
                            }
                        }

                        Button { close() } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.white)
                                .font(.body.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    Spacer()

                    // Location pill
                    if let locationText = storyLocationText(story) {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                Text(locationText)
                            }
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    }
                }

                // Tap zones (below header area)
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 80)
                        .allowsHitTesting(false)
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { goToPrevious() }
                                .frame(width: geo.size.width / 3)
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { goToNext() }
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 80)
                            .onEnded { value in
                                if value.translation.width < -80 {
                                    goToNextAuthor()
                                } else if value.translation.width > 80 {
                                    goToPreviousAuthor()
                                }
                            }
                    )
                }
            } else if isLoadingStories {
                ProgressView()
                    .tint(.white)
            }
        }
        .statusBarHidden()
        .confirmationDialog("Delete this story?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let story = currentStory {
                    Task { await deleteStory(story) }
                }
            }
            Button("Cancel", role: .cancel) {
                startTimer()
            }
        }
        .task {
            await loadStoriesForCurrentAuthor()
        }
    }

    // MARK: - Progress Bar

    private func barWidth(for index: Int, totalWidth: CGFloat) -> CGFloat {
        if index < currentStoryIndex {
            return totalWidth
        } else if index == currentStoryIndex {
            return totalWidth * progress
        } else {
            return 0
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        progress = 0
        timerTask = Task {
            let tickInterval: TimeInterval = 0.05
            let totalTicks = Int(storyDuration / tickInterval)
            for tick in 0...totalTicks {
                try? await Task.sleep(for: .milliseconds(Int(tickInterval * 1000)))
                guard !Task.isCancelled else { return }
                progress = CGFloat(tick) / CGFloat(totalTicks)
            }
            guard !Task.isCancelled else { return }
            goToNext()
        }
    }

    private func close() {
        timerTask?.cancel()
        onDismiss?()
    }

    // MARK: - Navigation

    private func goToNext() {
        guard !isLoadingStories, !stories.isEmpty else { return }
        guard Date().timeIntervalSince(lastNavTime) > 0.3 else { return }
        timerTask?.cancel()
        lastNavTime = Date()
        if currentStoryIndex < stories.count - 1 {
            currentStoryIndex += 1
            startTimer()
        } else {
            goToNextAuthor()
        }
    }

    private func goToPrevious() {
        guard !isLoadingStories, !stories.isEmpty else { return }
        guard Date().timeIntervalSince(lastNavTime) > 0.3 else { return }
        timerTask?.cancel()
        lastNavTime = Date()
        if currentStoryIndex > 0 {
            currentStoryIndex -= 1
            startTimer()
        } else {
            goToPreviousAuthor()
        }
    }

    private func goToNextAuthor() {
        if currentAuthorIndex < authors.count - 1 {
            currentAuthorIndex += 1
            currentStoryIndex = 0
            stories = []
            isLoadingStories = true
            timerTask?.cancel()
            Task { await loadStoriesForCurrentAuthor() }
        } else {
            close()
        }
    }

    private func goToPreviousAuthor() {
        if currentAuthorIndex > 0 {
            currentAuthorIndex -= 1
            currentStoryIndex = 0
            stories = []
            isLoadingStories = true
            timerTask?.cancel()
            Task { await loadStoriesForCurrentAuthor() }
        }
    }

    // MARK: - Data

    private func loadStoriesForCurrentAuthor() async {
        guard currentAuthorIndex < authors.count else { return }
        let did = authors[currentAuthorIndex].profile.did
        isLoadingStories = true
        timerTask?.cancel()

        do {
            let response = try await client.getStories(actor: did, auth: auth.authContext())
            stories = response.stories
            currentStoryIndex = 0
            startTimer()
        } catch {
            stories = []
        }
        isLoadingStories = false
    }

    private func deleteStory(_ story: GrainStory) async {
        guard let authContext = auth.authContext() else { return }
        let rkey = story.uri.split(separator: "/").last.map(String.init) ?? ""
        do {
            try await client.deleteRecord(collection: "social.grain.story", rkey: rkey, auth: authContext)
            stories.removeAll { $0.uri == story.uri }
            if stories.isEmpty {
                goToNextAuthor()
            } else {
                currentStoryIndex = min(currentStoryIndex, stories.count - 1)
                startTimer()
            }
        } catch {
            // Silently fail
        }
    }

    private func storyLocationText(_ story: GrainStory) -> String? {
        // Prefer location.name as the primary display (e.g. "Fimmvörðuháls Trail")
        if let name = story.location?.name, !name.isEmpty {
            return name
        }
        if let address = story.address {
            var parts: [String] = []
            if let name = address.name { parts.append(name) }
            else if let street = address.street { parts.append(street) }
            else if let locality = address.locality { parts.append(locality) }
            if let region = address.region, region != parts.first { parts.append(region) }
            if let locality = address.locality, !parts.contains(locality) { parts.append(locality) }
            if parts.isEmpty { parts.append(address.country) }
            return parts.joined(separator: ", ")
        }
        return nil
    }

    private func relativeTime(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

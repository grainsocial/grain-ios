import SwiftUI
import NukeUI

@Observable
@MainActor
private final class StoryTimer {
    var progress: CGFloat = 0
    var isRunning = false
    private var task: Task<Void, Never>?
    private let duration: TimeInterval = 5.0

    func start() {
        stop()
        progress = 0
        isRunning = true
        halfwayFired = false
        task = Task {
            let tickInterval: TimeInterval = 0.05
            let totalTicks = Int(duration / tickInterval)
            for tick in 0...totalTicks {
                do {
                    try await Task.sleep(for: .milliseconds(Int(tickInterval * 1000)))
                } catch { return }
                guard !Task.isCancelled else { return }
                progress = CGFloat(tick) / CGFloat(totalTicks)
                if !halfwayFired && progress >= 0.5 {
                    halfwayFired = true
                    onHalfway?()
                }
            }
            guard !Task.isCancelled else { return }
            isRunning = false
            onComplete?()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    var onComplete: (() -> Void)?
    var onHalfway: (() -> Void)?
    private var halfwayFired = false
}

struct StoryViewer: View {
    @Environment(AuthManager.self) private var auth
    @Environment(LabelDefinitionsCache.self) private var labelDefsCache
    @Environment(ViewedStoryStorage.self) private var viewedStories
    let authors: [GrainStoryAuthor]
    let client: XRPCClient
    var onProfileTap: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    @State private var currentAuthorIndex: Int
    @State private var currentStoryIndex = 0
    @State private var stories: [GrainStory] = []
    @State private var isLoadingStories = false
    @State private var timer = StoryTimer()
    @State private var showDeleteConfirm = false
    @State private var showReportSheet = false
    @State private var reportStoryUri = ""
    @State private var reportStoryCid = ""
    @State private var lastNavTime: Date = .distantPast
    @State private var labelRevealed = false
    @State private var fadeDismissHandle = FadeDismissHandle()
    @State private var prefetchedStories: [String: [GrainStory]] = [:]

    init(authors: [GrainStoryAuthor], startIndex: Int = 0, startAuthorDid: String? = nil, client: XRPCClient, onProfileTap: ((String) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.authors = authors
        self.client = client
        self.onProfileTap = onProfileTap
        self.onDismiss = onDismiss
        let resolvedIndex: Int
        if let did = startAuthorDid {
            resolvedIndex = authors.firstIndex(where: { $0.profile.did == did }) ?? 0
        } else {
            resolvedIndex = startIndex
        }
        _currentAuthorIndex = State(initialValue: resolvedIndex)
    }

    private var currentStory: GrainStory? {
        guard currentStoryIndex < stories.count else { return nil }
        return stories[currentStoryIndex]
    }

    private var storyLabelResult: LabelResolution {
        resolveLabels(currentStory?.labels, definitions: labelDefsCache.definitions)
    }

    var body: some View {
        storyContent
        .background(
            DragToDismissInstaller(
                handle: fadeDismissHandle,
                onDismiss: { onDismiss?() },
                onDragStart: { timer.stop() },
                onDragCancel: { timer.start() },
                onSwipeLeft: { goToNextAuthor() },
                onSwipeRight: { goToPreviousAuthor() }
            )
        )
        .statusBarHidden()
        .confirmationDialog("Delete this story?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let story = currentStory {
                    Task { await deleteStory(story) }
                }
            }
            Button("Cancel", role: .cancel) {
                timer.start()
            }
        }
        .fullScreenCover(isPresented: $showReportSheet) {
            ReportView(client: client, subjectUri: reportStoryUri, subjectCid: reportStoryCid)
                .environment(auth)
        }
        .onChange(of: showReportSheet) {
            if !showReportSheet {
                timer.start()
            }
        }
        .task {
            timer.onComplete = { [self] in goToNext() }
            timer.onHalfway = { [self] in markCurrentStoryViewed() }
            await loadStoriesForCurrentAuthor()
        }
    }

    @ViewBuilder
    private var storyContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let story = currentStory {
                let lr = storyLabelResult

                // Story image
                ZStack {
                    LazyImage(url: URL(string: story.fullsize)) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(story.aspectRatio.ratio, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        } else if state.isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .overlay {
                        if (lr.action == .warnMedia || lr.action == .warnContent || lr.action == .hide) && !labelRevealed {
                            Rectangle().fill(Color(.secondarySystemBackground))
                        }
                    }

                    if (lr.action == .warnContent || lr.action == .warnMedia || lr.action == .hide) && !labelRevealed {
                        MediaWarningOverlay(name: lr.name) {
                            withAnimation { labelRevealed = true }
                            timer.start()
                        }
                    }
                }

                // Tap zones
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
                }
                .allowsHitTesting(!showReportSheet && !showDeleteConfirm)

                // Header overlay
                VStack(spacing: 0) {
                    StoryProgressBars(timer: timer, stories: stories, currentStoryIndex: currentStoryIndex)
                        .padding(.horizontal)
                        .padding(.top, 8)

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
                                timer.stop()
                                showDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                            }
                        } else {
                            Button {
                                timer.stop()
                                reportStoryUri = story.uri
                                reportStoryCid = story.cid
                                showReportSheet = true
                            } label: {
                                Image(systemName: "flag")
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                            }
                        }

                        Button { close() } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.white)
                                .font(.body.weight(.semibold))
                                .frame(width: 36, height: 36)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    Spacer()
                        .allowsHitTesting(false)

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
            } else if isLoadingStories {
                ProgressView()
                    .tint(.white)
            }
        }
    }

    // MARK: - Navigation

    private func close() {
        timer.stop()
        fadeDismissHandle.fadeDismiss()
    }

    private func goToNext() {
        guard !isLoadingStories, !stories.isEmpty else { return }
        guard !showReportSheet, !showDeleteConfirm else { return }
        guard Date().timeIntervalSince(lastNavTime) > 0.3 else { return }
        markCurrentStoryViewed()
        timer.stop()
        lastNavTime = Date()
        if currentStoryIndex < stories.count - 1 {
            currentStoryIndex += 1
            labelRevealed = false
            timer.start()
        } else {
            goToNextAuthor()
        }
    }

    private func goToPrevious() {
        guard !isLoadingStories, !stories.isEmpty else { return }
        guard !showReportSheet, !showDeleteConfirm else { return }
        guard Date().timeIntervalSince(lastNavTime) > 0.3 else { return }
        timer.stop()
        lastNavTime = Date()
        if currentStoryIndex > 0 {
            currentStoryIndex -= 1
            labelRevealed = false
            timer.start()
        } else {
            goToPreviousAuthor()
        }
    }

    private func goToNextAuthor() {
        if currentAuthorIndex < authors.count - 1 {
            currentAuthorIndex += 1
            switchToCurrentAuthor()
        } else {
            close()
        }
    }

    private func goToPreviousAuthor() {
        if currentAuthorIndex > 0 {
            currentAuthorIndex -= 1
            switchToCurrentAuthor()
        }
    }

    private func switchToCurrentAuthor() {
        timer.stop()
        let did = authors[currentAuthorIndex].profile.did
        if let cached = prefetchedStories.removeValue(forKey: did) {
            stories = cached
            currentStoryIndex = viewedStories.firstUnviewedIndex(in: cached)
            labelRevealed = false
            isLoadingStories = false
            timer.start()
            prefetchAdjacentAuthors()
        } else {
            currentStoryIndex = 0
            stories = []
            isLoadingStories = true
            Task { await loadStoriesForCurrentAuthor() }
        }
    }

    // MARK: - Data

    private func loadStoriesForCurrentAuthor() async {
        guard currentAuthorIndex < authors.count else { return }
        let did = authors[currentAuthorIndex].profile.did
        isLoadingStories = true
        timer.stop()

        do {
            let fetched: [GrainStory]
            if let cached = prefetchedStories.removeValue(forKey: did) {
                fetched = cached
            } else {
                fetched = try await client.getStories(actor: did, auth: await auth.authContext()).stories
            }
            stories = fetched
            currentStoryIndex = viewedStories.firstUnviewedIndex(in: fetched)
            labelRevealed = false
            timer.start()
        } catch {
            stories = []
        }
        isLoadingStories = false

        // Prefetch next author's stories
        prefetchAdjacentAuthors()
    }

    private func prefetchAdjacentAuthors() {
        let nextIndex = currentAuthorIndex + 1
        guard nextIndex < authors.count else { return }
        let did = authors[nextIndex].profile.did
        guard prefetchedStories[did] == nil else { return }
        Task {
            if let response = try? await client.getStories(actor: did, auth: await auth.authContext()) {
                prefetchedStories[did] = response.stories
            }
        }
    }

    private func markCurrentStoryViewed() {
        guard let story = currentStory else { return }
        viewedStories.markViewed(uri: story.uri, authorDid: story.creator.did, createdAt: story.createdAt)
    }

    private func deleteStory(_ story: GrainStory) async {
        guard let authContext = await auth.authContext() else { return }
        let rkey = story.uri.split(separator: "/").last.map(String.init) ?? ""
        do {
            try await client.deleteRecord(collection: "social.grain.story", rkey: rkey, auth: authContext)
            stories.removeAll { $0.uri == story.uri }
            if stories.isEmpty {
                goToNextAuthor()
            } else {
                currentStoryIndex = min(currentStoryIndex, stories.count - 1)
                timer.start()
            }
        } catch {
            // Silently fail
        }
    }

    private func storyLocationText(_ story: GrainStory) -> String? {
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

// Extracted so progress ticks only redraw this view, not the entire StoryViewer
private struct StoryProgressBars: View {
    let timer: StoryTimer
    let stories: [GrainStory]
    let currentStoryIndex: Int

    var body: some View {
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
    }

    private func barWidth(for index: Int, totalWidth: CGFloat) -> CGFloat {
        if index < currentStoryIndex {
            return totalWidth
        } else if index == currentStoryIndex {
            return totalWidth * timer.progress
        } else {
            return 0
        }
    }
}

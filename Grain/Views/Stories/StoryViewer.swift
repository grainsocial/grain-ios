import Nuke
import NukeUI
import SwiftUI

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
        quarterFired = false
        task = Task {
            let tickInterval: TimeInterval = 0.05
            let totalTicks = Int(duration / tickInterval)
            for tick in 0 ... totalTicks {
                do {
                    try await Task.sleep(for: .milliseconds(Int(tickInterval * 1000)))
                } catch { return }
                guard !Task.isCancelled else { return }
                progress = CGFloat(tick) / CGFloat(totalTicks)
                if !quarterFired, progress >= 0.25 {
                    quarterFired = true
                    onQuarter?()
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
    var onQuarter: (() -> Void)?
    private var quarterFired = false
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
    @State private var showLocationCopied = false
    @State private var lastNavTime: Date = .distantPast
    @State private var labelRevealed = false
    @State private var imageLoaded = false
    @State private var fadeDismissHandle = FadeDismissHandle()
    @State private var prefetchedStories: [String: [GrainStory]] = [:]
    @State private var unreadOnly = false
    @State private var authorTransition: CGFloat = 1.0
    @State private var slideOffset: CGFloat = 0
    @State private var authorHistory: [(authorIndex: Int, storyIndex: Int)] = []
    @State private var imagePrefetcher = ImagePrefetcher()

    init(authors: [GrainStoryAuthor], startAuthorDid: String? = nil, client: XRPCClient, onProfileTap: ((String) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.authors = authors
        self.client = client
        self.onProfileTap = onProfileTap
        self.onDismiss = onDismiss
        let resolvedIndex = startAuthorDid.flatMap { did in authors.firstIndex { $0.profile.did == did } } ?? 0
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
            .offset(x: slideOffset)
            .scaleEffect(0.85 + 0.15 * authorTransition)
            .opacity(0.3 + 0.7 * Double(authorTransition))
            .background(
                DragToDismissInstaller(
                    handle: fadeDismissHandle,
                    onDismiss: { onDismiss?() },
                    onDragStart: { timer.stop() },
                    onDragCancel: { startTimerIfSafe() },
                    onSwipeLeft: { goToNextAuthor() },
                    onSwipeRight: { goToPreviousAuthor() }
                )
            )
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
                guard !isPreview else { return }
                let startAuthor = authors[currentAuthorIndex]
                let isOwn = startAuthor.profile.did == auth.userDID
                let hasUnreads = !viewedStories.hasViewedAll(authorDid: startAuthor.profile.did, latestAt: startAuthor.latestAt)
                unreadOnly = isOwn || hasUnreads
                timer.onComplete = { [self] in goToNext() }
                timer.onQuarter = { [self] in markCurrentStoryViewed() }
                await loadStoriesForCurrentAuthor()
            }
    }

    private var storyContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let story = currentStory {
                let lr = storyLabelResult

                // Story image
                ZStack {
                    LazyImage(request: {
                        guard lr.action != .hide || labelRevealed,
                              let url = URL(string: story.fullsize) else { return ImageRequest(url: nil) }
                        return ImageRequest(url: url, priority: .veryHigh)
                    }()) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(story.aspectRatio.ratio, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .onAppear {
                                    if !imageLoaded {
                                        imageLoaded = true
                                        startTimerIfSafe()
                                    }
                                }
                        } else {
                            ZStack {
                                LazyImage(url: URL(string: story.thumb)) { thumbState in
                                    if let thumb = thumbState.image {
                                        thumb
                                            .resizable()
                                            .aspectRatio(story.aspectRatio.ratio, contentMode: .fit)
                                            .blur(radius: 20)
                                            .clipped()
                                    }
                                }
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                    }
                    .id(story.uri)
                    .blur(radius: (lr.action == .warnMedia || lr.action == .warnContent) && !labelRevealed ? 24 : 0)

                    if lr.action == .warnContent || lr.action == .warnMedia || lr.action == .hide, !labelRevealed {
                        MediaWarningOverlay(name: lr.name) {
                            withAnimation { labelRevealed = true }
                            startTimerIfSafe()
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
                .allowsHitTesting(!showReportSheet && !showDeleteConfirm && (labelRevealed || storyLabelResult.action == .none || storyLabelResult.action == .badge))
            } else {
                ProgressView()
                    .tint(.white)
            }

            // Header overlay — always visible regardless of loading state
            let author = authors[currentAuthorIndex].profile
            let story = currentStory
            VStack(spacing: 0) {
                StoryProgressBars(timer: timer, stories: stories, currentStoryIndex: currentStoryIndex, placeholderCount: authors[currentAuthorIndex].storyCount)
                    .padding(.horizontal)
                    .padding(.top, 8)

                HStack(alignment: .center) {
                    Button {
                        if let story {
                            close()
                            onProfileTap?(story.creator.did)
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            AvatarView(url: story?.creator.avatar ?? author.avatar, size: 32)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(story?.creator.displayName ?? story?.creator.handle ?? author.displayName ?? author.handle)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                if let story {
                                    Text(relativeTime(story.createdAt))
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                        }
                    }
                    Spacer()

                    if let story {
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

                if let story, let locationText = storyLocationText(story) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: showLocationCopied ? "checkmark" : "location.fill")
                            Text(showLocationCopied ? "Copied" : locationText)
                        }
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .contentTransition(.symbolEffect(.replace))
                        .id(story.uri)
                        .onTapGesture {
                            UIPasteboard.general.string = locationText
                            withAnimation(.easeInOut(duration: 0.15)) { showLocationCopied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                withAnimation(.easeInOut(duration: 0.15)) { showLocationCopied = false }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - Navigation

    private func close() {
        timer.stop()
        fadeDismissHandle.fadeDismiss()
    }

    private func canNavigate() -> Bool {
        !isLoadingStories && !stories.isEmpty
            && !showReportSheet && !showDeleteConfirm
            && Date().timeIntervalSince(lastNavTime) > 0.3
    }

    private func startTimerIfSafe() {
        guard imageLoaded else { return }
        let action = storyLabelResult.action
        if action == .none || action == .badge { timer.start() }
    }

    private func goToNext() {
        guard canNavigate() else { return }
        markCurrentStoryViewed()
        timer.stop()
        lastNavTime = Date()
        if currentStoryIndex < stories.count - 1 {
            currentStoryIndex += 1
            imageLoaded = false
            labelRevealed = false
            showLocationCopied = false
            startTimerIfSafe()
            prefetchStoryImages()
        } else {
            goToNextAuthor()
        }
    }

    private func goToPrevious() {
        guard canNavigate() else { return }
        timer.stop()
        lastNavTime = Date()
        if currentStoryIndex > 0 {
            currentStoryIndex -= 1
            imageLoaded = false
            labelRevealed = false
            showLocationCopied = false
            startTimerIfSafe()
            prefetchStoryImages()
        } else {
            goToPreviousAuthor()
        }
    }

    private func goToNextAuthor() {
        if let next = findAuthorIndex(from: currentAuthorIndex, forward: true) {
            authorHistory.append((authorIndex: currentAuthorIndex, storyIndex: currentStoryIndex))
            transitionToAuthor(next, direction: 1)
        } else {
            close()
        }
    }

    private func goToPreviousAuthor() {
        if let prev = authorHistory.popLast() {
            transitionToAuthor(prev.authorIndex, direction: -1, resumeIndex: prev.storyIndex)
            return
        }
        // No history (entered mid-strip in reads mode) — walk backward ignoring the reads filter
        var i = currentAuthorIndex - 1
        while i >= 0 {
            if authors[i].profile.did != auth.userDID {
                transitionToAuthor(i, direction: -1)
                return
            }
            i -= 1
        }
    }

    private func transitionToAuthor(_ index: Int, direction: CGFloat, resumeIndex: Int? = nil) {
        timer.stop()
        withAnimation(.easeIn(duration: 0.15)) {
            authorTransition = 0
            slideOffset = -80 * direction
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            currentAuthorIndex = index
            switchToCurrentAuthor(resumeIndex: resumeIndex)
            slideOffset = 80 * direction
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                authorTransition = 1
                slideOffset = 0
            }
        }
    }

    private func findAuthorIndex(from index: Int, forward: Bool) -> Int? {
        let step = forward ? 1 : -1
        var i = index + step
        while i >= 0, i < authors.count {
            let author = authors[i]
            if author.profile.did == auth.userDID { i += step; continue }
            if !unreadOnly || authorHasUnreads(author) { return i }
            i += step
        }
        return nil
    }

    private func authorHasUnreads(_ author: GrainStoryAuthor) -> Bool {
        !viewedStories.hasViewedAll(authorDid: author.profile.did, latestAt: author.latestAt)
    }

    // MARK: - Data

    private func switchToCurrentAuthor(resumeIndex: Int? = nil) {
        timer.stop()
        let did = authors[currentAuthorIndex].profile.did
        if let cached = prefetchedStories.removeValue(forKey: did) {
            presentStories(cached, resumeIndex: resumeIndex)
        } else {
            currentStoryIndex = 0
            stories = []
            isLoadingStories = true
            Task { await loadStoriesForCurrentAuthor() }
        }
    }

    private func loadStoriesForCurrentAuthor() async {
        guard currentAuthorIndex < authors.count else { return }
        let did = authors[currentAuthorIndex].profile.did
        isLoadingStories = true
        timer.stop()

        do {
            let fetched: [GrainStory] = if let cached = prefetchedStories.removeValue(forKey: did) {
                cached
            } else {
                try await client.getStories(actor: did, auth: auth.authContext()).stories
            }
            presentStories(fetched)
        } catch {
            stories = []
            isLoadingStories = false
        }
    }

    private func presentStories(_ fetched: [GrainStory], resumeIndex: Int? = nil) {
        imageLoaded = false
        showLocationCopied = false
        stories = fetched
        if let resume = resumeIndex {
            currentStoryIndex = min(resume, max(fetched.count - 1, 0))
        } else {
            let isOwn = fetched.first?.creator.did == auth.userDID
            currentStoryIndex = (unreadOnly && isOwn) ? 0 : viewedStories.firstUnviewedIndex(in: fetched)
        }
        labelRevealed = false
        isLoadingStories = false
        startTimerIfSafe()
        prefetchAdjacentAuthors()
        prefetchStoryImages()
    }

    private func prefetchAdjacentAuthors() {
        guard let nextIndex = findAuthorIndex(from: currentAuthorIndex, forward: true) else { return }
        let did = authors[nextIndex].profile.did
        guard prefetchedStories[did] == nil else { return }
        Task {
            if let response = try? await client.getStories(actor: did, auth: auth.authContext()) {
                prefetchedStories[did] = response.stories
            }
        }
    }

    private func prefetchStoryImages() {
        let current = stories.map { (thumb: $0.thumb, fullsize: $0.fullsize) }

        // Resolve next authors' stories from prefetched data
        let nextDid = findAuthorIndex(from: currentAuthorIndex, forward: true).map { authors[$0].profile.did }
        let nextStories = nextDid.flatMap { prefetchedStories[$0] }?.map { (thumb: $0.thumb, fullsize: $0.fullsize) }

        let secondNextIdx = findAuthorIndex(from: currentAuthorIndex, forward: true)
            .flatMap { findAuthorIndex(from: $0, forward: true) }
        let secondNextDid = secondNextIdx.map { authors[$0].profile.did }
        let secondNextStories = secondNextDid.flatMap { prefetchedStories[$0] }?.map { (thumb: $0.thumb, fullsize: $0.fullsize) }

        let thirdNextIdx = secondNextIdx.flatMap { findAuthorIndex(from: $0, forward: true) }
        let thirdFirst = thirdNextIdx
            .flatMap { prefetchedStories[authors[$0].profile.did]?.first }
            .map { (thumb: $0.thumb, fullsize: $0.fullsize) }

        let fourthNextIdx = thirdNextIdx.flatMap { findAuthorIndex(from: $0, forward: true) }
        let fourthFirst = fourthNextIdx
            .flatMap { prefetchedStories[authors[$0].profile.did]?.first }
            .map { (thumb: $0.thumb, fullsize: $0.fullsize) }

        let plan = ImagePrefetchPlanning.storyPrefetchRequests(
            currentStories: current,
            currentStoryIndex: currentStoryIndex,
            nextAuthorStories: nextStories,
            secondNextAuthorStories: secondNextStories,
            thirdNextFirstStory: thirdFirst,
            fourthNextFirstStory: fourthFirst
        )
        imagePrefetcher.startPrefetching(with: plan.all)
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

/// Extracted so progress ticks only redraw this view, not the entire StoryViewer
private struct StoryProgressBars: View {
    let timer: StoryTimer
    let stories: [GrainStory]
    let currentStoryIndex: Int
    var placeholderCount: Int = 0

    private var barCount: Int {
        stories.isEmpty ? placeholderCount : stories.count
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< barCount, id: \.self) { index in
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
        guard !stories.isEmpty else { return 0 }
        if index < currentStoryIndex {
            return totalWidth
        } else if index == currentStoryIndex {
            return totalWidth * timer.progress
        } else {
            return 0
        }
    }
}

#Preview {
    StoryViewer(authors: PreviewData.storyAuthors, client: XRPCClient(baseURL: AuthManager.serverURL))
        .environment(AuthManager())
        .environment(LabelDefinitionsCache())
        .environment(ViewedStoryStorage())
}

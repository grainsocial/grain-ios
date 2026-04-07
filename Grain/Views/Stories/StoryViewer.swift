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

private struct PendingAuthorTransition {
    var authorIndex: Int?
    var stories: [GrainStory] = []
    var storyIndex: Int = 0
}

private struct FaceOffsets {
    var current: CGFloat = 0
    var pending: CGFloat = 0
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
    @State private var reportTarget: GrainStory?
    @State private var showLocationCopied = false
    @State private var lastNavTime: Date = .distantPast
    @State private var labelRevealed = false
    @State private var imageLoaded = false
    @State private var fadeDismissHandle = FadeDismissHandle()
    @State private var prefetchedStories: [String: [GrainStory]] = [:]
    @State private var unreadOnly = false
    @State private var pendingTransition = PendingAuthorTransition()
    @State private var faceOffsets = FaceOffsets()
    @State private var swipingForward = true
    @State private var transitionGeneration = 0
    @State private var authorHistory: [(authorIndex: Int, storyIndex: Int)] = []
    @State private var imagePrefetcher = ImagePrefetcher()
    @State private var isDragging = false

    init(authors: [GrainStoryAuthor], startAuthorDid: String? = nil, initialStories: [GrainStory]? = nil, startStoryIndex: Int? = nil, client: XRPCClient, onProfileTap: ((String) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.authors = authors
        self.client = client
        self.onProfileTap = onProfileTap
        self.onDismiss = onDismiss
        let resolvedIndex = startAuthorDid.flatMap { did in authors.firstIndex { $0.profile.did == did } } ?? 0
        _currentAuthorIndex = State(initialValue: resolvedIndex)
        if let initialStories {
            let did = authors[resolvedIndex].profile.did
            _prefetchedStories = State(initialValue: [did: initialStories])
            if let startStoryIndex {
                _currentStoryIndex = State(initialValue: startStoryIndex)
            }
        }
    }

    private var currentStory: GrainStory? {
        guard currentStoryIndex < stories.count else { return nil }
        return stories[currentStoryIndex]
    }

    private var storyLabelResult: LabelResolution {
        resolveLabels(currentStory?.labels, definitions: labelDefsCache.definitions)
    }

    private var screenWidth: CGFloat {
        (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.width) ?? 390
    }

    private var swipeAmount: CGFloat {
        min(abs(faceOffsets.current) / screenWidth, 1)
    }

    var body: some View {
        ZStack {
            if let pendingIdx = pendingTransition.authorIndex {
                pendingFaceView(authorIdx: pendingIdx)
                    .offset(x: faceOffsets.pending)
                    .scaleEffect(0.92 + swipeAmount * 0.08)
                    .opacity(Double(swipeAmount))
            }
            // Drop storyContent from the tree once it's fully faded so the spring's
            // settle window (~200ms past visual completion) doesn't keep an invisible
            // layer alive across the commit — otherwise the stale subtree pops off
            // visibly at commit time.
            if swipeAmount < 1 {
                storyContent
                    .offset(x: faceOffsets.current)
                    .scaleEffect(1 - swipeAmount * 0.08)
                    .opacity(1 - Double(swipeAmount))
                    .transition(.identity)
            }
        }
        .clipped()
        .background(Color.black.ignoresSafeArea())
        .background(
            DragToDismissInstaller(
                handle: fadeDismissHandle,
                onDismiss: { onDismiss?() },
                onDragStart: { timer.stop() },
                onDragCancel: { startTimerIfSafe() },
                onSwipeLeft: { goToNextAuthor() },
                onSwipeRight: { goToPreviousAuthor() },
                onHorizontalDragStart: { forward in beginSwipe(forward: forward) },
                onSwipeDragging: { tx in updateSwipeDrag(tx) },
                onHorizontalDragCancel: { cancelSwipe() }
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
        .fullScreenCover(item: $reportTarget) { story in
            ReportView(client: client, subjectUri: story.uri, subjectCid: story.cid)
                .environment(auth)
        }
        .onChange(of: reportTarget?.uri) {
            if reportTarget == nil { timer.start() }
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

    /// Mirrors the logic in presentStories so pendingTransition.storyIndex matches what will be committed.
    private func resolvedStoryIndex(for stories: [GrainStory], resumeIndex: Int? = nil) -> Int {
        if let resume = resumeIndex {
            return min(resume, max(stories.count - 1, 0))
        }
        let isOwn = stories.first?.creator.did == auth.userDID
        return (unreadOnly && isOwn) ? 0 : viewedStories.firstUnviewedIndex(in: stories)
    }

    @ViewBuilder
    private func pendingFaceView(authorIdx: Int) -> some View {
        let story = pendingTransition.stories.indices.contains(pendingTransition.storyIndex)
            ? pendingTransition.stories[pendingTransition.storyIndex]
            : pendingTransition.stories.first
        let barCount = pendingTransition.stories.isEmpty
            ? max(authors[authorIdx].storyCount, 1)
            : pendingTransition.stories.count
        ZStack {
            Color.black.ignoresSafeArea()
            if let story {
                let thumbURL = URL(string: story.thumb)
                let cached = thumbURL.flatMap {
                    ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: $0))?.image
                }
                if let img = cached {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(story.aspectRatio.ratio, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                } else {
                    LazyImage(url: thumbURL) { state in
                        if let img = state.image {
                            img.resizable()
                                .aspectRatio(story.aspectRatio.ratio, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .transition(.identity)
                        }
                    }
                }
            } else {
                ProgressView().tint(.white)
            }
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(0 ..< barCount, id: \.self) { i in
                        GeometryReader { geo in
                            Capsule().fill(Color.white.opacity(0.3))
                            Capsule().fill(Color.white)
                                .frame(width: i < pendingTransition.storyIndex ? geo.size.width : 0)
                        }
                        .frame(height: 2)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                HStack(alignment: .center, spacing: 8) {
                    AvatarView(url: authors[authorIdx].profile.avatar, size: 32, animated: false)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(story?.creator.displayName ?? story?.creator.handle ?? authors[authorIdx].profile.displayName ?? authors[authorIdx].profile.handle)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        if let story {
                            Text(relativeTime(story.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                    if authors[authorIdx].profile.did == auth.userDID {
                        Image(systemName: "trash")
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "flag")
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Spacer().allowsHitTesting(false)

                if let story, let locationText = storyLocationText(story) {
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
        }
    }

    /// Synchronous Nuke cache lookup so the avatar swaps atomically at commit.
    /// Falls back to AvatarView(animated:false) whose lastUIImage shows the prior
    /// avatar during any mid-animation cache miss — visually identical, no type-switch artifact.
    @ViewBuilder
    private func storyAvatarView(url: String?) -> some View {
        if let urlStr = url,
           let imageURL = URL(string: urlStr),
           let img = ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: imageURL))?.image
        {
            Image(uiImage: img)
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else {
            AvatarView(url: url, size: 32, animated: false)
        }
    }

    private var storyContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let story = currentStory {
                let lr = storyLabelResult

                // Story image — check memory cache before creating LazyImage so
                // we never get a two-state view swap (sync Image → LazyImage-delivered
                // Image) for the same pixel content, which causes a flash.
                let cachedFullsize: UIImage? = (lr.action != .hide || labelRevealed)
                    ? URL(string: story.fullsize).flatMap {
                        ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: $0))?.image
                    }
                    : nil
                ZStack {
                    Group {
                        if let cached = cachedFullsize {
                            // DEBUG: blue = fullsize sync-pulled from memory cache (no LazyImage needed)
                            Image(uiImage: cached)
                                .resizable()
                                .aspectRatio(story.aspectRatio.ratio, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                // .overlay(alignment: .topLeading) {
                                //     Color.blue.opacity(0.35).ignoresSafeArea()
                                //     Text("fullsize · cache").font(.caption2.bold()).padding(6).background(.black.opacity(0.5)).foregroundStyle(.white).padding(8)
                                // }
                                .onAppear {
                                    if !imageLoaded {
                                        imageLoaded = true
                                        startTimerIfSafe()
                                    }
                                }
                        } else {
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
                                        // .overlay(alignment: .topLeading) {
                                        //     // DEBUG: green = fullsize delivered by LazyImage (network/disk)
                                        //     Color.green.opacity(0.35).ignoresSafeArea()
                                        //     Text("fullsize · network").font(.caption2.bold()).padding(6).background(.black.opacity(0.5)).foregroundStyle(.white).padding(8)
                                        // }
                                        .onAppear {
                                            if !imageLoaded {
                                                imageLoaded = true
                                                startTimerIfSafe()
                                            }
                                        }
                                } else {
                                    ZStack {
                                        if let thumbURL = URL(string: story.thumb),
                                           let cachedThumb = ImagePipeline.shared.cache
                                           .cachedImage(for: ImageRequest(url: thumbURL))?.image
                                        {
                                            Image(uiImage: cachedThumb)
                                                .resizable()
                                                .aspectRatio(story.aspectRatio.ratio, contentMode: .fit)
                                                .blur(radius: 20)
                                                .clipped()
                                            // .overlay(alignment: .topLeading) {
                                            //     // DEBUG: yellow = thumb sync-pulled from memory cache
                                            //     Color.yellow.opacity(0.35).ignoresSafeArea()
                                            //     Text("thumb · cache").font(.caption2.bold()).padding(6).background(.black.opacity(0.5)).foregroundStyle(.white).padding(8)
                                            // }
                                        } else {
                                            LazyImage(url: URL(string: story.thumb)) { thumbState in
                                                if let thumb = thumbState.image {
                                                    thumb
                                                        .resizable()
                                                        .aspectRatio(story.aspectRatio.ratio, contentMode: .fit)
                                                        .blur(radius: 20)
                                                        .clipped()
                                                    // .overlay(alignment: .topLeading) {
                                                    //     // DEBUG: red = thumb from network (cache miss)
                                                    //     Color.red.opacity(0.35).ignoresSafeArea()
                                                    //     Text("thumb · network").font(.caption2.bold()).padding(6).background(.black.opacity(0.5)).foregroundStyle(.white).padding(8)
                                                    // }
                                                }
                                            }
                                        }
                                        ProgressView()
                                            .tint(.white)
                                    }
                                }
                            }
                        }
                    }
                    .blur(radius: (lr.action == .warnMedia || lr.action == .warnContent) && !labelRevealed ? 24 : 0)

                    if lr.action == .warnContent || lr.action == .warnMedia || lr.action == .hide, !labelRevealed {
                        MediaWarningOverlay(name: lr.name) {
                            withAnimation { labelRevealed = true }
                            startTimerIfSafe()
                        }
                    }
                }
                .id(story.uri)

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
                .allowsHitTesting(reportTarget == nil && !showDeleteConfirm && (labelRevealed || storyLabelResult.action == .none || storyLabelResult.action == .badge))
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
                            storyAvatarView(url: story?.creator.avatar ?? author.avatar)
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

                    if author.did == auth.userDID {
                        Button {
                            guard story != nil else { return }
                            timer.stop()
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                        }
                    } else {
                        Button {
                            guard let story else { return }
                            timer.stop()
                            reportTarget = story
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
            && reportTarget == nil && !showDeleteConfirm
            && !isDragging
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
            advanceStory(by: 1)
        } else {
            goToNextAuthor()
        }
    }

    private func goToPrevious() {
        guard canNavigate() else { return }
        timer.stop()
        lastNavTime = Date()
        if currentStoryIndex > 0 {
            advanceStory(by: -1)
        } else {
            goToPreviousAuthor()
        }
    }

    private func advanceStory(by delta: Int) {
        timer.progress = 0
        currentStoryIndex += delta
        imageLoaded = false
        labelRevealed = false
        showLocationCopied = false
        prefetchStoryImages()
    }

    private func goToNextAuthor() {
        if let pending = pendingTransition.authorIndex {
            guard swipingForward else { cancelSwipe(); return }
            isDragging = false
            authorHistory.append((authorIndex: currentAuthorIndex, storyIndex: currentStoryIndex))
            transitionToAuthor(pending, forward: true)
            return
        }
        guard let next = findAuthorIndex(from: currentAuthorIndex, forward: true) else {
            close(); return
        }
        authorHistory.append((authorIndex: currentAuthorIndex, storyIndex: currentStoryIndex))
        transitionToAuthor(next, forward: true)
    }

    private func goToPreviousAuthor() {
        if let pending = pendingTransition.authorIndex {
            guard !swipingForward else { cancelSwipe(); return }
            isDragging = false
            if let prev = authorHistory.popLast() {
                transitionToAuthor(pending, forward: false, resumeIndex: prev.storyIndex)
            } else {
                transitionToAuthor(pending, forward: false)
            }
            return
        }
        if let prev = authorHistory.popLast() {
            transitionToAuthor(prev.authorIndex, forward: false, resumeIndex: prev.storyIndex)
            return
        }
        // No history — walk backward ignoring the reads filter
        var i = currentAuthorIndex - 1
        while i >= 0 {
            if authors[i].profile.did != auth.userDID {
                transitionToAuthor(i, forward: false)
                return
            }
            i -= 1
        }
    }

    private func beginSwipe(forward: Bool) {
        guard pendingTransition.authorIndex == nil else { return }
        isDragging = true
        timer.stop()
        swipingForward = forward

        let resumeForBackward: Int? = forward ? nil : authorHistory.last?.storyIndex

        let targetIdx: Int?
        if forward {
            targetIdx = findAuthorIndex(from: currentAuthorIndex, forward: true)
        } else {
            if let prev = authorHistory.last {
                targetIdx = prev.authorIndex
            } else {
                var i = currentAuthorIndex - 1
                var found: Int?
                while i >= 0 {
                    if authors[i].profile.did != auth.userDID { found = i; break }
                    i -= 1
                }
                targetIdx = found
            }
        }
        guard let idx = targetIdx else { return }
        pendingTransition.authorIndex = idx
        let did = authors[idx].profile.did
        if let cached = prefetchedStories[did] {
            pendingTransition.stories = cached
            pendingTransition.storyIndex = resolvedStoryIndex(for: cached, resumeIndex: resumeForBackward)
        } else {
            pendingTransition.storyIndex = resumeForBackward ?? 0
            Task {
                if let response = try? await client.getStories(actor: did, auth: auth.authContext()) {
                    pendingTransition.stories = response.stories
                    pendingTransition.storyIndex = resolvedStoryIndex(for: response.stories, resumeIndex: resumeForBackward)
                }
            }
        }
        faceOffsets.pending = forward ? screenWidth : -screenWidth
    }

    private func updateSwipeDrag(_ tx: CGFloat) {
        guard pendingTransition.authorIndex != nil else { return }
        let clamped = max(-screenWidth, min(screenWidth, tx))
        faceOffsets.current = clamped
        let origin: CGFloat = swipingForward ? screenWidth : -screenWidth
        faceOffsets.pending = origin + clamped * 0.65
    }

    private func cancelSwipe() {
        isDragging = false
        transitionGeneration += 1
        let gen = transitionGeneration
        let resetOffset: CGFloat = swipingForward ? screenWidth : -screenWidth
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88), completionCriteria: .removed) {
            faceOffsets.current = 0
            faceOffsets.pending = resetOffset
        } completion: {
            guard transitionGeneration == gen else { return }
            withTransaction(Transaction(animation: nil)) {
                pendingTransition = PendingAuthorTransition()
                faceOffsets = FaceOffsets()
            }
            startTimerIfSafe()
        }
    }

    private func transitionToAuthor(_ index: Int, forward: Bool, resumeIndex: Int? = nil) {
        timer.stop()
        transitionGeneration += 1
        let gen = transitionGeneration

        // Set up pending face if not already done by beginSwipe
        if pendingTransition.authorIndex != index {
            swipingForward = forward
            pendingTransition.authorIndex = index
            let did = authors[index].profile.did
            let cached = prefetchedStories[did] ?? []
            pendingTransition.stories = cached
            pendingTransition.storyIndex = resolvedStoryIndex(for: cached, resumeIndex: resumeIndex)
            faceOffsets.pending = forward ? screenWidth : -screenWidth
            faceOffsets.current = 0
        }
        let targetCurrentOffset: CGFloat = forward ? -screenWidth : screenWidth
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88), completionCriteria: .removed) {
            faceOffsets.current = targetCurrentOffset
            faceOffsets.pending = 0
        } completion: {
            guard transitionGeneration == gen else { return }
            withTransaction(Transaction(animation: nil)) {
                let storiesToPresent = pendingTransition.stories
                currentAuthorIndex = index
                timer.progress = 0
                if !storiesToPresent.isEmpty {
                    presentStories(storiesToPresent, resumeIndex: resumeIndex)
                } else {
                    switchToCurrentAuthor(resumeIndex: resumeIndex)
                }
                pendingTransition = PendingAuthorTransition()
                faceOffsets = FaceOffsets()
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
                        .frame(width: max(0, barWidth(for: index, totalWidth: geo.size.width)))
                }
                .frame(height: 2)
                .transaction { $0.animation = nil }
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

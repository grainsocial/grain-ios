import Nuke
import NukeUI
import os
import SwiftUI

private let svLogger = Logger(subsystem: "social.grain.grain", category: "StoryViewer")
private let svSignposter = OSSignposter(subsystem: "social.grain.grain", category: "StoryViewer")

@MainActor private var svInstanceCounter: Int = 0
@MainActor private func svNextInstanceID() -> Int {
    svInstanceCounter += 1
    return svInstanceCounter
}

@Observable
@MainActor
private final class StoryTimer {
    var progress: CGFloat = 0
    var isRunning = false
    private var task: Task<Void, Never>?
    private let duration: TimeInterval = 5.0

    func start() {
        svLogger.info("[timer.start] called")
        svSignposter.emitEvent("timer.start")
        progress = 0
        quarterFired = false
        run(fromProgress: 0)
    }

    func resume() {
        guard !isRunning else { return }
        guard progress < 1.0 else { start(); return }
        run(fromProgress: progress)
    }

    private func run(fromProgress start: CGFloat) {
        stop()
        isRunning = true
        let tickInterval: TimeInterval = 0.05
        let totalTicks = Int(duration / tickInterval)
        let startTick = max(Int(start * CGFloat(totalTicks)), 0)
        task = Task {
            for tick in startTick ... totalTicks {
                do {
                    try await Task.sleep(for: .milliseconds(Int(tickInterval * 1000)))
                } catch { return }
                guard !Task.isCancelled else { return }
                progress = CGFloat(tick) / CGFloat(totalTicks)
                if !quarterFired, progress >= 0.01 {
                    quarterFired = true
                    onQuarter?()
                }
            }
            guard !Task.isCancelled else { return }
            isRunning = false
            svLogger.info("[timer.complete] fired onComplete")
            svSignposter.emitEvent("timer.complete")
            onComplete?()
        }
    }

    func stop() {
        if isRunning {
            svLogger.info("[timer.stop] called (was running)")
            svSignposter.emitEvent("timer.stop")
        }
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

/// Reference-typed memo for the current story's fullsize cache lookup.
/// Why: `cachedFullsizeImage` is read from the view body. Computing it
/// inline re-checks Nuke's memory cache on every body eval, so if a
/// `@State` write (e.g. `imageLoaded = true` from LazyImage's onAppear)
/// fires AFTER LazyImage has delivered, the next body re-eval sees a
/// sudden cache hit and swaps the if/else branch from LazyImage → sync
/// `Image(uiImage:)`. The branch swap tears down the LazyImage subtree,
/// which visibly flashes the blurred thumb placeholder for one frame.
/// Holding the lookup in a class means we can memoize per-URI without
/// triggering view invalidation on update.
@MainActor private final class FullsizeMemo {
    var uri: String?
    var image: UIImage?
}

struct StoryViewer: View {
    @Environment(AuthManager.self) private var auth
    @Environment(LabelDefinitionsCache.self) private var labelDefsCache
    @Environment(ViewedStoryStorage.self) private var viewedStories
    @Environment(StoryStatusCache.self) private var storyStatusCache
    @Environment(StoryCommentPresenter.self) private var commentPresenter
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
    @State private var fullsizeMemo = FullsizeMemo()

    // MARK: - Comments & Likes

    @State private var commentsViewModel: StoryCommentsViewModel
    /// Local mirror of the presenter's sheet state. Driven by the `onDidClose`
    /// callback passed to `commentPresenter.open(...)`. Do NOT replace this
    /// with a read of `commentPresenter.presentedStoryUri` — that read would
    /// re-evaluate the body on every open/close and cascade into a storyContent
    /// re-render (black flash on sheet transitions).
    @State private var isCommentSheetOpen = false
    @State private var hasLoadedInitialStories = false
    @State private var hearts: [HeartAnimationState] = []
    @State private var favoritingStoryUris: Set<String> = []
    @State private var heartBeatTrigger = 0
    @State private var instanceID: Int = 0

    init(authors: [GrainStoryAuthor], startAuthorDid: String? = nil, initialStories: [GrainStory]? = nil, startStoryIndex: Int? = nil, client: XRPCClient, onProfileTap: ((String) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.authors = authors
        self.client = client
        self.onProfileTap = onProfileTap
        self.onDismiss = onDismiss
        _commentsViewModel = State(initialValue: StoryCommentsViewModel(client: client))
        let resolvedIndex = startAuthorDid.flatMap { did in authors.firstIndex { $0.profile.did == did } } ?? 0
        _currentAuthorIndex = State(initialValue: resolvedIndex)
        if let initialStories {
            let did = authors[resolvedIndex].profile.did
            _prefetchedStories = State(initialValue: [did: initialStories])
            if let startStoryIndex {
                _currentStoryIndex = State(initialValue: startStoryIndex)
            }
        }
        let id = svNextInstanceID()
        _instanceID = State(initialValue: id)
        svLogger.info("[init] StoryViewer.init id=\(id) startAuthorDid=\(startAuthorDid ?? "nil") authors.count=\(authors.count)")
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
        .preferredColorScheme(.dark)
        .background(
            DragToDismissInstaller(
                handle: fadeDismissHandle,
                onDismiss: { onDismiss?() },
                onDragStart: { timer.stop() },
                onDragCancel: { startTimerIfSafe() },
                onSwipeLeft: { goToNextAuthor() },
                onSwipeRight: { goToPreviousAuthor() },
                onSwipeUp: { openCommentSheet(focusInput: false) },
                onHorizontalDragStart: { forward in beginSwipe(forward: forward) },
                onSwipeDragging: { tx in updateSwipeDrag(tx) },
                onHorizontalDragCancel: { cancelSwipe() },
                isEnabled: !isCommentSheetOpen
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
        .onChange(of: currentStory?.uri) { _, _ in
            hearts.removeAll()
        }
        .task {
            // Guard against re-runs: .task can re-fire when the view re-enters the
            // hierarchy (e.g. after sheet presentation cycles), and we only want to
            // load stories once per StoryViewer instance.
            guard !hasLoadedInitialStories else { return }
            hasLoadedInitialStories = true
            if isPreview, prefetchedStories.isEmpty { return }
            let startAuthor = authors[currentAuthorIndex]
            let isOwn = startAuthor.profile.did == auth.userDID
            let hasUnreads = !viewedStories.hasViewedAll(authorDid: startAuthor.profile.did, latestAt: startAuthor.latestAt)
            unreadOnly = isOwn || hasUnreads
            if !isPreview {
                timer.onComplete = { [self] in goToNext() }
                timer.onQuarter = { [self] in markCurrentStoryViewed() }
            }
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
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(story?.creator.displayName ?? story?.creator.handle ?? authors[authorIdx].profile.displayName ?? authors[authorIdx].profile.handle)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            Text(story.map { DateFormatting.relativeTime($0.createdAt) } ?? " ")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(story != nil ? 0.7 : 0))
                                .animation(.easeIn(duration: 0.12), value: story != nil)
                        }
                        Text(story.flatMap { storyLocationText($0) } ?? " ")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(story.flatMap { storyLocationText($0) } != nil ? 0.7 : 0))
                            .lineLimit(1)
                            .animation(.easeIn(duration: 0.12), value: story.flatMap { storyLocationText($0) } != nil)
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

                bottomInputBar(interactive: false, story: story)
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

                // Memoized per-URI. Computing this inline would re-check Nuke's
                // memory cache on every body eval; once LazyImage delivers and
                // writes `imageLoaded`, the resulting re-eval would flip a
                // miss→hit and swap the if/else branch, tearing down LazyImage
                // and briefly flashing the blurred thumb placeholder.
                let cachedFullsize = cachedFullsizeImage(
                    for: story,
                    blocked: lr.action == .hide && !labelRevealed
                )
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
                                    svSignposter.emitEvent("storyImage.syncHit.appear")
                                    svLogger.info("[storyImage] sync-hit onAppear uri=\(story.uri)")
                                    if !imageLoaded {
                                        imageLoaded = true
                                        startTimerIfSafe()
                                    }
                                }
                        } else {
                            LazyImage(request: {
                                guard lr.action != .hide || labelRevealed,
                                      let url = URL(string: story.fullsize) else { return ImageRequest(url: nil) }
                                return ImageRequest(url: url, priority: .veryHigh, options: .disableDiskCacheWrites)
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
                                            svSignposter.emitEvent("storyImage.lazyDelivered.appear")
                                            svLogger.info("[storyImage] lazy-delivered onAppear uri=\(story.uri)")
                                            if !imageLoaded {
                                                imageLoaded = true
                                                startTimerIfSafe()
                                            }
                                        }
                                } else {
                                    if let thumbURL = URL(string: story.thumb),
                                       let cachedThumb = ImagePipeline.shared.cache
                                       .cachedImage(for: ImageRequest(url: thumbURL))?.image
                                    {
                                        Image(uiImage: cachedThumb)
                                            .resizable()
                                            .aspectRatio(story.aspectRatio.ratio, contentMode: .fit)
                                            .frame(maxWidth: .infinity)
                                            .clipped()
                                    } else {
                                        LazyImage(url: URL(string: story.thumb)) { thumbState in
                                            if let thumb = thumbState.image {
                                                thumb
                                                    .resizable()
                                                    .aspectRatio(story.aspectRatio.ratio, contentMode: .fit)
                                                    .frame(maxWidth: .infinity)
                                                    .clipped()
                                            }
                                        }
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

                // Tap zones — with a bottom inset so they don't cover the comment input bar.
                // Double-tap reports its location in the "storyHearts" coordinate space
                // (declared on the outer ZStack below) so the heart lands under the finger.
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
                    Color.clear
                        .frame(height: 80)
                        .allowsHitTesting(false)
                }
                .allowsHitTesting(reportTarget == nil && !showDeleteConfirm && !isCommentSheetOpen && (labelRevealed || storyLabelResult.action == .none || storyLabelResult.action == .badge))

                // Double-tap heart animations
                ForEach(hearts) { heart in
                    DoubleTapHeartView(state: heart)
                        .onChange(of: heart.isComplete) {
                            hearts.removeAll { $0.isComplete }
                        }
                }
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
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text(story?.creator.displayName ?? story?.creator.handle ?? author.displayName ?? author.handle)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                    Text(story.map { DateFormatting.relativeTime($0.createdAt) } ?? " ")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(story != nil ? 0.7 : 0))
                                        .animation(.easeIn(duration: 0.12), value: story != nil)
                                }
                                Text(story.flatMap { storyLocationText($0) } ?? " ")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(story.flatMap { storyLocationText($0) } != nil ? 0.7 : 0))
                                    .lineLimit(1)
                                    .animation(.easeIn(duration: 0.12), value: story.flatMap { storyLocationText($0) } != nil)
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

                // MARK: Comment preview + input bar

                if let currentStory, currentStory.expired != true {
                    Group {
                        if let latest = commentsViewModel.firstComment,
                           commentsViewModel.activeStoryUri == currentStory.uri
                        {
                            Button {
                                openCommentSheet(focusInput: false)
                            } label: {
                                HStack(spacing: 6) {
                                    AvatarView(url: latest.author.avatar, size: 20, animated: false)
                                    Text(latest.text)
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.white.opacity(0.15), in: .capsule)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 16)
                            .padding(.trailing, 64)
                            .padding(.bottom, 4)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: commentsViewModel.firstComment?.uri)

                    bottomInputBar(interactive: true, story: currentStory)
                }
            }
        }
        .coordinateSpace(.named("storyHearts"))
    }

    // MARK: - Navigation

    private func close() {
        timer.stop()
        fadeDismissHandle.fadeDismiss()
    }

    private func canNavigate() -> Bool {
        !isLoadingStories && !stories.isEmpty
            && reportTarget == nil && !showDeleteConfirm
            && !isCommentSheetOpen
            && !isDragging
            && Date().timeIntervalSince(lastNavTime) > 0.3
    }

    private func startTimerIfSafe() {
        guard imageLoaded, !isCommentSheetOpen else { return }
        let action = storyLabelResult.action
        if action == .none || action == .badge { timer.start() }
    }

    private func resumeTimerIfSafe() {
        guard imageLoaded, !isCommentSheetOpen else { return }
        let action = storyLabelResult.action
        if action == .none || action == .badge { timer.resume() }
    }

    private func isFullsizeCached(_ story: GrainStory?) -> Bool {
        storyFullsizeCached(story)
    }

    /// Returns the fullsize image for `story` if Nuke has it in the memory
    /// cache, memoized per story URI. Only re-checks the pipeline when the
    /// URI changes; otherwise returns the previously-recorded result so
    /// view-body re-evals don't swap the image branch mid-render.
    private func cachedFullsizeImage(for story: GrainStory, blocked: Bool) -> UIImage? {
        if blocked { return nil }
        if fullsizeMemo.uri == story.uri {
            return fullsizeMemo.image
        }
        let image = URL(string: story.fullsize).flatMap {
            ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: $0))?.image
        }
        fullsizeMemo.uri = story.uri
        fullsizeMemo.image = image
        svSignposter.emitEvent("fullsizeMemo.update", "hit=\(image != nil)")
        svLogger.info("[fullsizeMemo] update uri=\(story.uri) hit=\(image != nil)")
        return image
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
        svLogger.info("[advanceStory] delta=\(delta) currentIdx=\(currentStoryIndex)")
        svSignposter.emitEvent("advanceStory", "delta=\(delta)")
        timer.progress = 0
        let newIndex = currentStoryIndex + delta
        let nextStory = stories.indices.contains(newIndex) ? stories[newIndex] : nil
        currentStoryIndex = newIndex
        if isFullsizeCached(nextStory) {
            startTimerIfSafe()
        } else {
            imageLoaded = false
        }
        labelRevealed = false
        prefetchStoryImages()
        if let uri = nextStory?.uri {
            Task { await commentsViewModel.switchToStory(uri: uri, auth: auth.authContext()) }
        }
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
        // No previous author found — resume the timer
        startTimerIfSafe()
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
        svLogger.info("[loadStoriesForCurrentAuthor] enter authorIdx=\(currentAuthorIndex)")
        svSignposter.emitEvent("loadStoriesForCurrentAuthor.enter")
        guard currentAuthorIndex < authors.count else { return }
        let did = authors[currentAuthorIndex].profile.did
        isLoadingStories = true
        timer.stop()

        do {
            let fromCache = prefetchedStories[did] != nil
            let fetched: [GrainStory] = if let cached = prefetchedStories.removeValue(forKey: did) {
                cached
            } else {
                try await client.getStories(actor: did, auth: auth.authContext()).stories
            }
            svLogger.info("[loadStoriesForCurrentAuthor] fetched count=\(fetched.count) fromCache=\(fromCache)")
            presentStories(fetched)
        } catch {
            svLogger.error("[loadStoriesForCurrentAuthor] error: \(error)")
            stories = []
            isLoadingStories = false
        }
    }

    private func presentStories(_ fetched: [GrainStory], resumeIndex: Int? = nil) {
        svLogger.info("[presentStories] enter count=\(fetched.count) resumeIndex=\(resumeIndex ?? -1)")
        svSignposter.emitEvent("presentStories.enter", "count=\(fetched.count)")
        let targetIndex: Int
        if let resume = resumeIndex {
            targetIndex = min(resume, max(fetched.count - 1, 0))
        } else {
            let isOwn = fetched.first?.creator.did == auth.userDID
            targetIndex = (unreadOnly && isOwn) ? 0 : viewedStories.firstUnviewedIndex(in: fetched)
        }
        let targetStory = fetched.indices.contains(targetIndex) ? fetched[targetIndex] : nil
        if !isFullsizeCached(targetStory) { imageLoaded = false }
        stories = fetched
        currentStoryIndex = targetIndex
        labelRevealed = false
        isLoadingStories = false
        startTimerIfSafe()
        prefetchAdjacentAuthors()
        prefetchStoryImages()
        if let uri = targetStory?.uri {
            Task {
                let ctx = await auth.authContext()
                commentsViewModel.switchToStory(uri: uri, auth: ctx)
                commentsViewModel.prefetchPreviews(for: fetched.map(\.uri), auth: ctx)
            }
        }
    }

    private func prefetchAdjacentAuthors() {
        guard let nextIndex = findAuthorIndex(from: currentAuthorIndex, forward: true) else { return }
        let did = authors[nextIndex].profile.did
        guard prefetchedStories[did] == nil else { return }
        Task {
            let ctx = await auth.authContext()
            if let response = try? await client.getStories(actor: did, auth: ctx) {
                prefetchedStories[did] = response.stories
                commentsViewModel.prefetchPreviews(for: response.stories.map(\.uri), auth: ctx)
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
                storyStatusCache.remove(did: story.creator.did)
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

    // MARK: - Comments & Likes

    private func openCommentSheet(focusInput: Bool) {
        guard let uri = currentStory?.uri else {
            svLogger.info("[openCommentSheet] SKIPPED (currentStory nil)")
            return
        }
        svLogger.info("[openCommentSheet] uri=\(uri) focusInput=\(focusInput)")
        svSignposter.emitEvent("openCommentSheet", "focusInput=\(focusInput)")
        timer.stop()
        isCommentSheetOpen = true
        let onProfileTap = onProfileTap
        commentPresenter.open(
            storyUri: uri,
            focusInput: focusInput,
            commentsViewModel: commentsViewModel,
            client: client,
            onProfileTap: { [commentPresenter, fadeDismissHandle] did in
                commentPresenter.close()
                fadeDismissHandle.fadeDismiss()
                onProfileTap?(did)
            },
            onDidClose: {
                svSignposter.emitEvent("onDidClose")
                isCommentSheetOpen = false
                resumeTimerIfSafe()
            }
        )
    }

    private var isFavorited: Bool {
        guard let story = currentStory else { return false }
        return story.viewer?.fav != nil
    }

    private func bottomInputBar(interactive: Bool, story: GrainStory?) -> some View {
        let favState = interactive ? isFavorited : (story?.viewer?.fav != nil)
        return HStack(spacing: 12) {
            // "Add a comment..." — opens sheet with keyboard
            if interactive {
                Button {
                    openCommentSheet(focusInput: true)
                } label: {
                    Text("Add a comment...")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .capsule)
            } else {
                Text("Add a comment...")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
            }

            // Heart — favorite/unfavorite
            if interactive {
                Button {
                    if !favState { heartBeatTrigger &+= 1 }
                    triggerFavoriteToggle()
                } label: {
                    heartIcon(isFavorited: favState)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                heartIcon(isFavorited: favState)
                    .onChange(of: favState) { oldValue, newValue in
                        if oldValue != true, newValue == true { heartBeatTrigger &+= 1 }
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func heartIcon(isFavorited: Bool) -> some View {
        Image(systemName: isFavorited ? "heart.fill" : "heart")
            .font(.title)
            .foregroundStyle(isFavorited ? AnyShapeStyle(Color.heart) : AnyShapeStyle(.white))
            .keyframeAnimator(initialValue: 1.0, trigger: heartBeatTrigger) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.35, duration: 0.14, spring: .bouncy)
                    SpringKeyframe(0.95, duration: 0.12, spring: .bouncy)
                    SpringKeyframe(1.22, duration: 0.12, spring: .bouncy)
                    SpringKeyframe(1.0, duration: 0.20, spring: .bouncy)
                }
            }
            .frame(width: 44, height: 44)
    }

    private func doubleTapLike(at point: CGPoint) {
        hearts.append(HeartAnimationState(position: point))
        heartBeatTrigger &+= 1
        guard !isFavorited else { return }
        triggerFavoriteToggle()
    }

    private func triggerFavoriteToggle() {
        guard let storyUri = currentStory?.uri else { return }
        guard !favoritingStoryUris.contains(storyUri) else {
            svLogger.info("[triggerFavoriteToggle] SKIPPED — toggle already in flight uri=\(storyUri)")
            svSignposter.emitEvent("toggleStoryFavorite.skipped", "reason=inFlight")
            return
        }
        favoritingStoryUris.insert(storyUri)
        Task {
            await toggleStoryFavorite(storyUri: storyUri)
            favoritingStoryUris.remove(storyUri)
        }
    }

    /// Toggle the favorite state for the *story that was visible when the user tapped*,
    /// not whichever story happens to be current when the network request returns.
    /// The story timer or a tap can advance `currentStoryIndex` across the `await`,
    /// so every mutation must look up the story by its captured URI.
    private func toggleStoryFavorite(storyUri: String) async {
        guard let authContext = await auth.authContext() else {
            svLogger.info("[toggleStoryFavorite] BAIL — no authContext")
            return
        }

        let capturedViewer = stories.first(where: { $0.uri == storyUri })?.viewer
        let existingFavUri = capturedViewer?.fav
        let op = existingFavUri == nil ? "like" : "unlike"

        let toggleState = svSignposter.beginInterval(
            "toggleStoryFavorite",
            id: svSignposter.makeSignpostID(),
            "op=\(op) uri=\(storyUri)"
        )
        defer { svSignposter.endInterval("toggleStoryFavorite", toggleState) }
        svLogger.info("[toggleStoryFavorite] enter op=\(op) uri=\(storyUri)")

        func indexOfCapturedStory() -> Int? {
            stories.firstIndex { $0.uri == storyUri }
        }

        if let favUri = existingFavUri {
            // Unfavorite — optimistic
            let prevViewer: StoryViewerState?
            if let idx = indexOfCapturedStory() {
                prevViewer = stories[idx].viewer
                stories[idx].viewer = nil
            } else {
                prevViewer = nil
            }
            svSignposter.emitEvent("toggleStoryFavorite.optimistic", "op=unlike uri=\(storyUri)")
            do {
                try await FavoriteService.delete(favoriteUri: favUri, client: client, auth: authContext)
                svSignposter.emitEvent("toggleStoryFavorite.success", "op=unlike uri=\(storyUri)")
                svLogger.info("[toggleStoryFavorite] success op=unlike uri=\(storyUri)")
            } catch {
                svSignposter.emitEvent("toggleStoryFavorite.error", "op=unlike uri=\(storyUri)")
                svLogger.error("[toggleStoryFavorite] unlike error: \(error); rolling back uri=\(storyUri)")
                if let idx = indexOfCapturedStory() {
                    stories[idx].viewer = prevViewer
                }
            }
        } else {
            // Favorite — optimistic
            let prevViewer: StoryViewerState?
            if let idx = indexOfCapturedStory() {
                prevViewer = stories[idx].viewer
                stories[idx].viewer = StoryViewerState(fav: "pending")
            } else {
                prevViewer = nil
            }
            svSignposter.emitEvent("toggleStoryFavorite.optimistic", "op=like uri=\(storyUri)")
            do {
                let response = try await FavoriteService.create(subject: storyUri, client: client, auth: authContext)
                if let newFavUri = response.uri {
                    if let idx = indexOfCapturedStory() {
                        stories[idx].viewer = StoryViewerState(fav: newFavUri)
                    }
                    svSignposter.emitEvent("toggleStoryFavorite.success", "op=like uri=\(storyUri)")
                    svLogger.info("[toggleStoryFavorite] success op=like uri=\(storyUri)")
                } else {
                    svSignposter.emitEvent("toggleStoryFavorite.error", "op=like reason=nilUri uri=\(storyUri)")
                    svLogger.error("[toggleStoryFavorite] create returned nil uri; rolling back uri=\(storyUri)")
                    if let idx = indexOfCapturedStory() {
                        stories[idx].viewer = prevViewer
                    }
                }
            } catch {
                svSignposter.emitEvent("toggleStoryFavorite.error", "op=like uri=\(storyUri)")
                svLogger.error("[toggleStoryFavorite] like error: \(error); rolling back uri=\(storyUri)")
                if let idx = indexOfCapturedStory() {
                    stories[idx].viewer = prevViewer
                }
            }
        }
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

#Preview("Story Viewer") {
    StoryViewer(
        authors: PreviewData.storyAuthors,
        startAuthorDid: "did:plc:prevuser1",
        initialStories: PreviewData.stories,
        client: XRPCClient(baseURL: AuthManager.serverURL)
    )
    .environment(AuthManager())
    .environment(LabelDefinitionsCache())
    .environment(ViewedStoryStorage())
    .environment(StoryStatusCache())
    .environment(StoryCommentPresenter())
}

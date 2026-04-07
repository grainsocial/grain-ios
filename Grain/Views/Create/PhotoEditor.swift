import SwiftUI

// MARK: - Editor mode

/// The three modes the gallery editor can be in. Owned by `PhotoEditor` as
/// `@State` and surfaced via a segmented `Picker` in the section header.
enum EditorMode: Equatable, CaseIterable {
    /// Strip layout + Post Preview carousel.
    case preview
    /// 3-column reorder grid.
    case reorder
    /// Scrollable list of photos with inline alt-text fields.
    case captions

    var label: String {
        switch self {
        case .preview: "Preview"
        case .reorder: "Reorder"
        case .captions: "Captions"
        }
    }
}

// MARK: - Cell geometry

/// Bundle of layout values a `PhotoThumbnailCell` needs to lay out its photo,
/// mask, and X button. Computed once by the parent layout (PhotoStrip or
/// ReorderablePhotoGrid) and passed in, so the cell can't be constructed with
/// a mask side that doesn't match its mode (e.g. preview mode with a 200pt
/// mask). The constraint lives in the type rather than in a runtime assert.
///
/// `photoSize` is derived from `mode`, `maskSide`, and `photoAspect` so that
/// strip cells use scaledToFill semantics (smallest dim = maskSide, the other
/// dim overflows so the square mask center-crops the photo) and grid cells
/// use scaledToFit semantics (largest dim = maskSide, the other dim
/// letterboxes inside the square mask so the *full* photo is visible).
struct CellGeometry: Equatable {
    let mode: EditorMode
    /// Side length of the square mask. Strip → 72; grid → column-width square.
    let maskSide: CGFloat
    /// Photo's natural aspect ratio (w/h) from `item.thumbnail`.
    let photoAspect: CGFloat

    /// The photo's rendered size after the mode-specific scaling rule. The
    /// cell sets the inner image's `.frame` to exactly this size, then wraps
    /// it in a `maskSide × maskSide` outer frame plus `.clipped()` so the
    /// mask crops whatever falls outside.
    var photoSize: CGSize {
        switch mode {
        case .preview:
            // scaledToFill: smaller dim of the rendered photo == maskSide,
            // larger dim overflows so the mask center-crops it.
            photoAspect >= 1
                ? CGSize(width: maskSide * photoAspect, height: maskSide)
                : CGSize(width: maskSide, height: maskSide / photoAspect)
        case .reorder:
            // scaledToFit: larger dim of the rendered photo == maskSide,
            // smaller dim letterboxes inside the square mask. Result: the
            // full photo is visible with empty space on the off-axis.
            photoAspect >= 1
                ? CGSize(width: maskSide, height: maskSide / photoAspect)
                : CGSize(width: maskSide * photoAspect, height: maskSide)
        case .captions:
            // Captions list uses the same scaledToFill rule as preview so
            // small row thumbnails fill their square without letterboxing.
            photoAspect >= 1
                ? CGSize(width: maskSide * photoAspect, height: maskSide)
                : CGSize(width: maskSide, height: maskSide / photoAspect)
        }
    }

    /// Corner radius applied to the mask. Strip and captions cells get 8pt
    /// rounded corners; grid cells get a sharp square so the full photo is
    /// visible without a pinched edge.
    var maskCornerRadius: CGFloat {
        mode == .reorder ? 0 : 8
    }
}

struct PhotoEditor: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    /// True while a cell is in the picked-up state (between long-press-fires and
    /// touch-release). The parent Form uses this to drive .scrollDisabled so that
    /// vertical scroll is locked only during the actual drag — not during the
    /// 0.18s arming window that precedes it.
    @Binding var isReordering: Bool
    let sendExif: Bool

    /// Current editor mode. Owned at this level so the section header button,
    /// the strip/grid swap, and the conditional carousel + alt-text sections
    /// all read from the same source of truth. Defaults to `.preview` so the
    /// strip + carousel are visible when a gallery first appears.
    @State private var mode: EditorMode = .preview
    /// True from the moment the user taps the header button until the
    /// withAnimation completion fires. Drives two things in concert:
    /// (1) cells hide their X buttons so they don't pop in mid-morph,
    /// (2) the Post Preview carousel section stays gone for the full duration
    ///     of the move (instead of popping back in the instant mode flips back
    ///     to .preview).
    /// Both settle simultaneously when the animation completes.
    @State private var isAnimatingMode = false
    @State private var showingCarouselAlt = false
    /// Shared namespace for the strip↔grid matched-geometry transition. The
    /// namespace itself is declared once at the editor level and passed to both
    /// PhotoThumbnailCell callsites so their photo views share stable geometry IDs
    /// across the mode toggle.
    @Namespace private var photoNamespace
    /// Shared namespace for the selection ring matched-geometry effect. The ring
    /// flies between cells when `selectedPhotoID` changes within a mode, and
    /// rides the cell's `photoNamespace` morph when the mode itself switches.
    @Namespace private var selectionNamespace

    /// LRU preview cache. The carousel uses these instead of `item.thumbnail` (which
    /// is downsized to 150pt for the strip/grid and looks blurry full-screen). Cache
    /// is capped to keep peak memory bounded — 20 photos × full-res would be hundreds
    /// of MB on a phone. We load on selection change and prune the oldest entries.
    @State private var previewCache: [UUID: UIImage] = [:]
    @State private var previewCacheOrder: [UUID] = []
    @State private var loadingPreviewIDs: Set<UUID> = []
    @State private var prefetchTasks: [UUID: Task<Void, Never>] = [:]

    /// 1500pt is plenty for a phone-screen carousel — at 3x density that's 4500
    /// pixels of horizontal resolution, more than the screen's native width.
    private let previewMaxDimension: CGFloat = 1500
    private let previewCacheLimit = 5

    private var selectedIndex: Int? {
        guard let id = selectedPhotoID else { return nil }
        return items.firstIndex(where: { $0.id == id })
    }

    /// Wraps `mode` so the segmented Picker gets the same `isAnimatingMode`
    /// gating as the old button: gate goes up synchronously at the start of the
    /// animation and comes back down in the completion handler.
    ///
    /// The `!isAnimatingMode` guard also prevents a mid-flight tap on a
    /// different segment from racing with the in-progress transition.
    ///
    /// A 1.5 s Task safety-net forces the gate down if the completion is
    /// silently dropped — a known iOS 17/18 issue when a concurrent transaction
    /// replaces the animation before it settles.
    private var modeBinding: Binding<EditorMode> {
        Binding(
            get: { mode },
            set: { newMode in
                guard newMode != mode, !isAnimatingMode else { return }
                withAnimation(.smooth) {
                    isAnimatingMode = true
                    mode = newMode
                } completion: {
                    // Plain assignment — no withAnimation. The morph has already
                    // settled; wrapping this in withAnimation(.smooth) re-runs a
                    // smooth transaction over every view that reads isAnimatingMode
                    // (both PhotoStrip and ReorderablePhotoGrid receive a new param
                    // value), causing SwiftUI to re-interpolate cell positions that
                    // are already at rest, which produces the post-morph wobble.
                    isAnimatingMode = false
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    guard isAnimatingMode else { return }
                    isAnimatingMode = false
                }
            }
        )
    }

    var body: some View {
        // MARK: Photos section (strip OR grid)

        Section {
            // Plain if/else swap (NOT a ZStack with both subtrees mounted).
            // Only one layout is in the view tree at a time, which means:
            //
            //   1. The Section's natural height is the active layout's height,
            //      so the strip section actually expands DOWN into the grid
            //      when mode flips inside withAnimation (and shrinks back).
            //   2. matched-geometry can't have two simultaneous sources for
            //      the same id, so no isActive plumbing is needed.
            //   3. The inactive layout doesn't run a layout pass each frame,
            //      which removes the background work that was stuttering the
            //      strip's auto-scroll on tap.
            //
            // matched-geometry still pairs the cells across the swap because
            // both layouts use the same `photoNamespace` and the same
            // `item.id` per cell, and the swap is wrapped in withAnimation —
            // SwiftUI snapshots the source's bounds at unmount and animates
            // the destination from those bounds to its natural bounds. The
            // critical detail is that `MatchedPhotoModifier` is applied to
            // the OUTER cell frame (not the inner image), so the cell's
            // POSITION is what gets paired, not just the inner image bounds.
            Group {
                if mode == .preview {
                    // No .transition — matched-geometry drives the morph.
                    PhotoStrip(
                        items: $items,
                        selectedPhotoID: $selectedPhotoID,
                        matchedNamespace: photoNamespace,
                        selectionNamespace: selectionNamespace,
                        isAnimatingMode: isAnimatingMode
                    )
                } else if mode == .reorder {
                    // No .transition — matched-geometry drives the morph.
                    ReorderablePhotoGrid(
                        items: $items,
                        selectedPhotoID: $selectedPhotoID,
                        isReordering: $isReordering,
                        matchedNamespace: photoNamespace,
                        selectionNamespace: selectionNamespace,
                        isAnimatingMode: isAnimatingMode
                    )
                } else {
                    // Captions has no matched-geometry pairing, so opacity
                    // crossfade is the only transition available.
                    captionsList
                        .transition(.opacity)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        } header: {
            Picker("Mode", selection: modeBinding) {
                ForEach(EditorMode.allCases, id: \.self) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isAnimatingMode)
        }

        // MARK: Post Preview section (carousel + EXIF) — preview mode only

        // The section stays in the tree for the entire duration of any
        // transition that touches preview mode (mode == .preview OR
        // isAnimatingMode). This prevents the hard-cut that would occur if we
        // only gated on mode == .preview and the section left the tree the
        // instant mode flipped to something else.
        //
        // `showingCarousel` is the single truth that drives both opacity and
        // frame height simultaneously:
        //   - Height 0 while hidden so the section takes no layout space and
        //     the form doesn't show a black gap mid-morph.
        //   - Both dimensions animate together on the .smooth curve so the
        //     carousel expands+fades in as one motion.
        if let idx = selectedIndex, mode == .preview || isAnimatingMode {
            let showingCarousel = mode == .preview && !isAnimatingMode
            Section {
                VStack(spacing: 0) {
                    photoCarousel
                    if items.contains(where: { $0.exifSummary != nil }) {
                        ExifInfoView(
                            exif: items[idx].exifSummary?.displayData,
                            reserveCameraRow: items.contains(where: { $0.exifSummary?.camera != nil }),
                            reserveLensRow: items.contains(where: { $0.exifSummary?.lens != nil }),
                            style: AnyShapeStyle(sendExif ? .secondary : .tertiary)
                        )
                        .transaction { $0.animation = nil }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Color.black)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.black.opacity(showingCarousel ? 1 : 0))
            } header: {
                Text("Post Preview")
            }
            .opacity(showingCarousel ? 1 : 0)
            .animation(.smooth, value: isAnimatingMode)
        }
    }

    // MARK: - Captions list

    /// Scrollable list of photo rows shown in `.captions` mode. Each row has a
    /// small square thumbnail on the left and an inline alt-text TextField on
    /// the right, so the user can caption every photo without tapping around.
    private var captionsList: some View {
        VStack(spacing: 0) {
            ForEach($items) { $item in
                HStack(alignment: .top, spacing: 12) {
                    let aspect: CGFloat = {
                        let w = item.thumbnail.size.width
                        let h = item.thumbnail.size.height
                        return h > 0 ? w / h : 1
                    }()
                    let geo = CellGeometry(mode: .captions, maskSide: 60, photoAspect: aspect)
                    Image(uiImage: item.thumbnail)
                        .resizable()
                        .frame(width: geo.photoSize.width, height: geo.photoSize.height)
                        .frame(width: geo.maskSide, height: geo.maskSide)
                        .clipped()
                        .cornerRadius(geo.maskCornerRadius)

                    VStack(alignment: .leading, spacing: 4) {
                        TextField(
                            "Add a description for accessibility",
                            text: $item.alt,
                            axis: .vertical
                        )
                        .font(.subheadline)
                        .lineLimit(2 ... 4)

                        if sendExif {
                            ExifInfoView(exif: item.exifSummary?.displayData)
                                .transaction { $0.animation = nil }
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 20)

                if item.id != items.last?.id {
                    Divider().padding(.leading, 92)
                }
            }
        }
    }

    // MARK: - Carousel (mirrors GalleryCardView.photoCarousel)

    private func ratio(for item: PhotoItem) -> CGFloat {
        let w = item.thumbnail.size.width
        let h = item.thumbnail.size.height
        guard h > 0 else { return 1 }
        return w / h
    }

    @ViewBuilder
    private var photoCarousel: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            let ratios = items.map(ratio(for:))
            let hasMixedRatios = Set(ratios.map { Int($0 * 100) }).count > 1
            let safeIdx = min(max(selectedIndex ?? 0, 0), items.count - 1)
            let carouselRatio: CGFloat = hasMixedRatios
                ? max(ratios.min() ?? 1, 0.56)
                : ratios[safeIdx]

            ZStack(alignment: .bottom) {
                Color.black

                TabView(selection: $selectedPhotoID) {
                    ForEach(items) { item in
                        ZStack {
                            ZoomableImage(
                                localImage: previewCache[item.id] ?? item.thumbnail,
                                aspectRatio: ratio(for: item)
                            )

                            if showingCarouselAlt {
                                let alt = item.alt.trimmingCharacters(in: .whitespaces)
                                if !alt.isEmpty {
                                    ZStack {
                                        Color.black.opacity(0.6)
                                        Text(alt)
                                            .font(.subheadline)
                                            .foregroundStyle(.white)
                                            .multilineTextAlignment(.center)
                                            .padding(20)
                                    }
                                    .allowsHitTesting(false)
                                }
                            }
                        }
                        .tag(item.id as UUID?)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator
                altPillIndicator(for: safeIdx)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(carouselRatio, contentMode: .fit)
            .contentShape(Rectangle())
            .onTapGesture {
                let alt = items[safeIdx].alt.trimmingCharacters(in: .whitespaces)
                guard !alt.isEmpty else { return }
                withAnimation(.smooth) { showingCarouselAlt.toggle() }
            }
            .onChange(of: selectedPhotoID) { _, newID in
                showingCarouselAlt = false
                if newID != nil {
                    prefetchPreviewsAroundSelection()
                }
            }
            .onAppear {
                prefetchPreviewsAroundSelection()
            }
            .onDisappear {
                prefetchTasks.values.forEach { $0.cancel() }
                prefetchTasks.removeAll()
            }
        }
    }

    // MARK: - Preview cache

    /// Load high-res previews for the currently-selected photo PLUS its immediate
    /// neighbors (prev/next), so that by the time the user pinches to zoom, the
    /// 1500pt preview is already in the cache instead of the 150pt thumbnail.
    /// Without this prefetch the zoom overlay shows a heavily-blurred image until
    /// the load completes — by which point the user has already given up.
    private func prefetchPreviewsAroundSelection() {
        guard let id = selectedPhotoID,
              let centerIdx = items.firstIndex(where: { $0.id == id }) else { return }
        let neighborOffsets = [0, -1, 1]
        for offset in neighborOffsets {
            let idx = centerIdx + offset
            guard items.indices.contains(idx) else { continue }
            loadPreviewIfNeeded(for: items[idx])
        }
    }

    /// Load a higher-resolution preview image for `item` into `previewCache` unless
    /// it's already cached or in flight. The cache is bounded by `previewCacheLimit`
    /// — when exceeded, the least-recently-used entry is evicted. The carousel reads
    /// from this cache and falls back to `item.thumbnail` (150pt) while loading.
    private func loadPreviewIfNeeded(for item: PhotoItem) {
        guard previewCache[item.id] == nil,
              !loadingPreviewIDs.contains(item.id) else { return }
        loadingPreviewIDs.insert(item.id)
        let id = item.id
        let source = item.source
        let task = Task {
            let image = await Self.loadPreviewImage(source: source, maxDimension: previewMaxDimension)
            await MainActor.run {
                prefetchTasks.removeValue(forKey: id)
                loadingPreviewIDs.remove(id)
                guard let image else { return }
                // Bail if the item was deleted while we were loading.
                guard items.contains(where: { $0.id == id }) else { return }
                // Move id to the most-recent slot in the LRU. removeAll-then-append
                // is correct even if the id was somehow already present (it never
                // double-counts in the order array).
                previewCache[id] = image
                previewCacheOrder.removeAll { $0 == id }
                previewCacheOrder.append(id)
                while previewCacheOrder.count > previewCacheLimit {
                    let evict = previewCacheOrder.removeFirst()
                    previewCache.removeValue(forKey: evict)
                }
            }
        }
        prefetchTasks[id] = task
    }

    /// Static so the closure body doesn't capture `self`. For picker items we have
    /// to fetch the original Data via PhotosPicker; for camera items the full UIImage
    /// already lives in the PhotoSource enum. In both cases we downsize to
    /// `maxDimension` so cached previews fit a sane memory budget.
    private static func loadPreviewImage(source: PhotoSource, maxDimension: CGFloat) async -> UIImage? {
        switch source {
        case let .picker(pickerItem):
            guard let data = try? await pickerItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return nil }
            return PhotoItem.makeThumbnail(from: image, maxSize: maxDimension)
        case let .camera(image, _):
            return PhotoItem.makeThumbnail(from: image, maxSize: maxDimension)
        }
    }

    @ViewBuilder
    private var pageIndicator: some View {
        if items.count > 1 {
            let current = selectedIndex ?? 0
            let ratios = items.map(ratio(for:))
            let hasPortrait = ratios.contains { $0 < 1 }
            HStack(spacing: 5) {
                let total = items.count
                let maxVisible = 5
                let start = total <= maxVisible ? 0 : min(max(current - 2, 0), total - maxVisible)
                let end = total <= maxVisible ? total : start + maxVisible

                ForEach(start ..< end, id: \.self) { index in
                    let distance = abs(index - current)
                    let currentIsLandscape = ratios[current] >= 1
                    let dotColor: Color = hasPortrait && currentIsLandscape ? .secondary : .white
                    Circle()
                        .fill(dotColor.opacity(index == current ? 1.0 : distance == 1 ? 0.5 : distance == 2 ? 0.3 : 0.2))
                        .frame(
                            width: distance <= 1 ? 6 : distance == 2 ? 4 : 3,
                            height: distance <= 1 ? 6 : distance == 2 ? 4 : 3
                        )
                        .animation(.smooth, value: current)
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func altPillIndicator(for index: Int) -> some View {
        let hasAlt = !items[index].alt.trimmingCharacters(in: .whitespaces).isEmpty
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text("ALT")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .opacity(hasAlt ? 1 : 0.5)
                    .padding(8)
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    @Previewable @State var state: [PhotoItem] = PreviewData.photoItems
    @Previewable @State var selected: UUID?
    @Previewable @State var zoomState = ImageZoomState()
    Form {
        PhotoEditor(
            items: $state,
            selectedPhotoID: $selected,
            isReordering: .constant(false),
            sendExif: true
        )
    }
    .environment(zoomState)
    .modifier(ImageZoomOverlay(zoomState: zoomState))
    .onAppear { selected = state.first?.id }
    .preferredColorScheme(.dark)
}

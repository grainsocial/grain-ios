import SwiftUI
import UIKit

// MARK: - Preview cache store

/// Holds the LRU preview-image cache that the carousel uses for hi-res zoom.
///
/// Extracted from `PhotoEditor` so that cache mutations — cache hits, task
/// bookkeeping — only invalidate `PhotoCarouselView`, which actually reads
/// `previewCache`. Any mutation on a plain `@State` dictionary on `PhotoEditor`
/// would have re-rendered the entire editor (PhotoStrip, ReorderablePhotoGrid,
/// and captionsList too), even though none of those views touch this data.
///
/// `@Observable` lets us be surgical: only `previewCache` participates in
/// tracking, while the three bookkeeping properties are marked
/// `@ObservationIgnored` so writes to them don't trigger a re-render at all.
@Observable
@MainActor
final class PreviewCacheStore {
    /// Decoded hi-res images keyed by PhotoItem.id. Reads of this dict inside a
    /// SwiftUI body will register a dependency; writes will trigger an update only
    /// for views that read it. This is intentionally observable.
    var previewCache: [UUID: UIImage] = [:]

    /// LRU eviction order. Internal bookkeeping — must NOT trigger re-renders.
    @ObservationIgnored private var previewCacheOrder: [UUID] = []
    /// Set of IDs currently being loaded. Internal bookkeeping — must NOT trigger re-renders.
    @ObservationIgnored private var loadingPreviewIDs: Set<UUID> = []
    /// Active prefetch tasks keyed by PhotoItem.id. Internal bookkeeping — must NOT trigger re-renders.
    @ObservationIgnored private var prefetchTasks: [UUID: Task<Void, Never>] = [:]

    /// 1500pt is plenty for a phone-screen carousel — at 3x density that's 4500
    /// pixels of horizontal resolution, more than the screen's native width.
    let previewMaxDimension: CGFloat = 1500
    let previewCacheLimit = 5

    /// Cancel all in-flight tasks. Call from `onDisappear`.
    func cancelAllTasks() {
        prefetchTasks.values.forEach { $0.cancel() }
        prefetchTasks.removeAll()
    }

    /// Load high-res previews for the currently-selected photo PLUS its immediate
    /// neighbors (prev/next), so that by the time the user pinches to zoom, the
    /// 1500pt preview is already in the cache instead of the 150pt thumbnail.
    /// Without this prefetch the zoom overlay shows a heavily-blurred image until
    /// the load completes — by which point the user has already given up.
    func prefetchPreviewsAroundSelection(items: [PhotoItem], selectedPhotoID: UUID?) {
        guard let id = selectedPhotoID,
              let centerIdx = items.firstIndex(where: { $0.id == id }) else { return }
        // ±2 window. At 1500pt max dimension a decoded preview can be ~50 MB;
        // loading all photos would be ~1 GB. byPreparingForDisplay() in
        // loadPreviewImage ensures each hi-res image is decompressed before the
        // carousel draws it, so the first display never stalls the main thread.
        for offset in -2 ... 2 {
            let idx = centerIdx + offset
            guard items.indices.contains(idx) else { continue }
            loadPreviewIfNeeded(for: items[idx], items: items)
        }
    }

    /// Load a higher-resolution preview image for `item` into `previewCache` unless
    /// it's already cached or in flight. The cache is bounded by `previewCacheLimit`
    /// — when exceeded, the least-recently-used entry is evicted. The carousel reads
    /// from this cache and falls back to `item.thumbnail` (150pt) while loading.
    private func loadPreviewIfNeeded(for item: PhotoItem, items: [PhotoItem]) {
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
            let resized = PhotoItem.makeThumbnail(from: image, maxSize: maxDimension)
            // Pre-decode so the bitmap is ready before the carousel draws it.
            // byPreparingForDisplay() decompresses on a background thread; fall
            // back to the undecompressed image if it returns nil.
            return await resized.byPreparingForDisplay() ?? resized
        case let .camera(image, _):
            let resized = PhotoItem.makeThumbnail(from: image, maxSize: maxDimension)
            return await resized.byPreparingForDisplay() ?? resized
        }
    }
}

// MARK: - Photo carousel view

/// Self-contained carousel section content: the paged TabView, page-dot
/// indicator, ALT-text pill, and EXIF info row.
///
/// Extracted from `PhotoEditor` so that the 4 cache-bookkeeping `@State`
/// properties (previewCache, previewCacheOrder, loadingPreviewIDs,
/// prefetchTasks) and `showingCarouselAlt` live here instead of on the editor.
/// Any mutation to those properties now only triggers a re-render of this
/// struct — not PhotoStrip, ReorderablePhotoGrid, or captionsList.
struct PhotoCarouselView: View {
    let items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    let sendExif: Bool

    /// Tracks whether the ALT-text overlay is visible. Local to the carousel —
    /// PhotoEditor doesn't need to know about this toggle.
    @State private var showingCarouselAlt = false
    /// Cache store owned by this view. `@State` is the correct ownership
    /// primitive for `@Observable` objects created inside a view — it gives the
    /// store the same lifetime as the view without going through the
    /// `@StateObject` path (which requires `ObservableObject`).
    @State private var cacheStore = PreviewCacheStore()

    private var selectedIndex: Int? {
        guard let id = selectedPhotoID else { return nil }
        return items.firstIndex(where: { $0.id == id })
    }

    private func ratio(for item: PhotoItem) -> CGFloat {
        let w = item.thumbnail.size.width
        let h = item.thumbnail.size.height
        guard h > 0 else { return 1 }
        return w / h
    }

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            let ratios = items.map(ratio(for:))
            let hasMixedRatios = Set(ratios.map { Int($0 * 100) }).count > 1
            let safeIdx = min(max(selectedIndex ?? 0, 0), items.count - 1)
            let carouselRatio: CGFloat = hasMixedRatios
                ? max(ratios.min() ?? 1, 0.56)
                : ratios[safeIdx]

            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Color.black

                    TabView(selection: $selectedPhotoID) {
                        ForEach(items) { item in
                            ZStack {
                                ZoomableImage(
                                    localImage: item.carouselPreview,
                                    aspectRatio: ratio(for: item),
                                    // Pass the hi-res prefetched image for zoom if ready;
                                    // ZoomableImage falls back to carouselPreview otherwise.
                                    zoomImage: cacheStore.previewCache[item.id]
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
                        cacheStore.prefetchPreviewsAroundSelection(items: items, selectedPhotoID: selectedPhotoID)
                    }
                }
                .onAppear {
                    cacheStore.prefetchPreviewsAroundSelection(items: items, selectedPhotoID: selectedPhotoID)
                }
                .onDisappear {
                    cacheStore.cancelAllTasks()
                }

                if items.contains(where: { $0.exifSummary != nil }), let idx = selectedIndex {
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
        }
    }

    // MARK: - Page indicator

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

    // MARK: - ALT pill indicator

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
    /// Pre-measured width of the photos section row. The Group containing
    /// strip/grid always occupies this row, so its width is known before the
    /// grid mounts. Passing it in means ReorderablePhotoGrid has the correct
    /// cellSide from frame zero — no mid-animation onGeometryChange correction.
    @State private var gridContainerWidth: CGFloat = UIScreen.main.bounds.width
    /// Shared namespace for the strip↔grid matched-geometry transition. The
    /// namespace itself is declared once at the editor level and passed to both
    /// PhotoThumbnailCell callsites so their photo views share stable geometry IDs
    /// across the mode toggle.
    @Namespace private var photoNamespace

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

                // Captions ↔ strip/grid involves a dramatic height change in the
                // Form row (a short strip vs. a very tall captions list). Animating
                // that height change inside withAnimation(.smooth) puts UIKit's
                // UICollectionViewCompositionalLayout into a recursive layout loop
                // (depth 100, assertion crash). Instant swap avoids this entirely.
                // Strip ↔ grid stays animated so matched-geometry can morph cells.
                let involvesCaption = newMode == .captions || mode == .captions
                if involvesCaption {
                    mode = newMode
                } else {
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
                        isAnimatingMode: isAnimatingMode,
                        sendExif: sendExif
                    )
                } else if mode == .reorder {
                    // No .transition — matched-geometry drives the morph.
                    ReorderablePhotoGrid(
                        items: $items,
                        selectedPhotoID: $selectedPhotoID,
                        isReordering: $isReordering,
                        matchedNamespace: photoNamespace,
                        containerWidth: gridContainerWidth,
                        isAnimatingMode: isAnimatingMode,
                        sendExif: sendExif
                    )
                } else {
                    // Captions has no matched-geometry pairing. No transition
                    // here — a .transition(.opacity) keeps captionsList in the
                    // same Form row as the incoming strip/grid during its exit
                    // animation. Two views of wildly different heights in the
                    // same row causes UICollectionView layout recursion (depth
                    // 100 assertion). Hard swap is correct: strip↔grid uses
                    // matched-geometry, not a transition, for the same reason.
                    captionsList
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { newWidth in
                guard newWidth > 0 else { return }
                var t = Transaction()
                t.animation = nil
                withTransaction(t) { gridContainerWidth = newWidth }
            }
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
        if let _ = selectedIndex, mode == .preview {
            Section {
                // .id(items.count) forces UICollectionView to remeasure this
                // row whenever photos are added or removed. SwiftUI propagating
                // a changed .aspectRatio alone is not enough — UIKit's
                // compositional layout caches row heights and won't re-query
                // the cell unless its view identity changes.
                PhotoCarouselView(
                    items: items,
                    selectedPhotoID: $selectedPhotoID,
                    sendExif: sendExif
                )
                .id(items.count)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.black)
            } header: {
                Text("Post Preview")
            }
            .transition(.opacity)
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
}

#Preview {
    @Previewable @State var state: [PhotoItem] = PreviewData.photoItemsWithExif
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

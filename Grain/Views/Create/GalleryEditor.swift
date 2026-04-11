import os
import SwiftUI
import UIKit

private let photoLoadingSignposter = OSSignposter(subsystem: "social.grain.grain", category: "PhotoLoading.Preview")
private let morphSignposter = OSSignposter(subsystem: "social.grain.grain", category: "Animation.Morph")
private let reorderSignposter = OSSignposter(subsystem: "social.grain.grain", category: "Animation.Reorder")

// MARK: - Preview cache store

/// Holds the LRU preview-image cache that the carousel uses for hi-res zoom.
///
/// Extracted from `GalleryEditor` so that cache mutations — cache hits, task
/// bookkeeping — only invalidate `PhotoCarouselView`, which actually reads
/// `previewCache`. Any mutation on a plain `@State` dictionary on `PhotoEditor`
/// would have re-rendered the entire editor, even though none of those views
/// touch this data.
///
/// `@Observable` lets us be surgical: only `previewCache` participates in
/// tracking, while the three bookkeeping properties are marked
/// `@ObservationIgnored` so writes to them don't trigger a re-render at all.
@Observable
@MainActor
final class PreviewCacheStore {
    var previewCache: [UUID: UIImage] = [:]

    @ObservationIgnored private var previewCacheOrder: [UUID] = []
    @ObservationIgnored private var loadingPreviewIDs: Set<UUID> = []
    @ObservationIgnored private var prefetchTasks: [UUID: Task<Void, Never>] = [:]

    let previewMaxDimension: CGFloat = 1500
    let previewCacheLimit = 5

    func cancelAllTasks() {
        prefetchTasks.values.forEach { $0.cancel() }
        prefetchTasks.removeAll()
    }

    func prefetchPreviewsAroundSelection(items: [PhotoItem], selectedPhotoID: UUID?) {
        guard let id = selectedPhotoID,
              let centerIdx = items.firstIndex(where: { $0.id == id }) else { return }
        let state = photoLoadingSignposter.beginInterval("PrefetchWindow", id: photoLoadingSignposter.makeSignpostID(), "center=\(centerIdx),total=\(items.count)")
        for offset in -2 ... 2 {
            let idx = centerIdx + offset
            guard items.indices.contains(idx) else { continue }
            loadPreviewIfNeeded(for: items[idx], items: items)
        }
        photoLoadingSignposter.endInterval("PrefetchWindow", state)
    }

    private func loadPreviewIfNeeded(for item: PhotoItem, items: [PhotoItem]) {
        guard previewCache[item.id] == nil,
              !loadingPreviewIDs.contains(item.id) else { return }
        loadingPreviewIDs.insert(item.id)
        let id = item.id
        let source = item.source
        let maxDim = previewMaxDimension
        let cacheLimit = previewCacheLimit
        let task = Task.detached(priority: .utility) { [weak self] in
            let spid = photoLoadingSignposter.makeSignpostID()
            let previewState = photoLoadingSignposter.beginInterval("LoadPreview", id: spid)
            let image = await PreviewCacheStore.loadPreviewImage(source: source, maxDimension: maxDim)
            photoLoadingSignposter.endInterval("LoadPreview", previewState, "success=\(image != nil)")
            await MainActor.run {
                guard let self else { return }
                self.prefetchTasks.removeValue(forKey: id)
                self.loadingPreviewIDs.remove(id)
                guard let image else { return }
                guard items.contains(where: { $0.id == id }) else { return }
                self.previewCache[id] = image
                self.previewCacheOrder.removeAll { $0 == id }
                self.previewCacheOrder.append(id)
                while self.previewCacheOrder.count > cacheLimit {
                    let evict = self.previewCacheOrder.removeFirst()
                    self.previewCache.removeValue(forKey: evict)
                }
            }
        }
        prefetchTasks[id] = task
    }

    private nonisolated static func loadPreviewImage(source: PhotoSource, maxDimension: CGFloat) async -> UIImage? {
        switch source {
        case let .picker(pickerItem):
            let transferState = photoLoadingSignposter.beginInterval("LoadTransferable", id: photoLoadingSignposter.makeSignpostID())
            guard let data = try? await pickerItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                photoLoadingSignposter.endInterval("LoadTransferable", transferState, "result=nil")
                return nil
            }
            photoLoadingSignposter.endInterval("LoadTransferable", transferState, "bytes=\(data.count)")
            let thumbState = photoLoadingSignposter.beginInterval("MakeThumbnail", id: photoLoadingSignposter.makeSignpostID())
            let resized = PhotoItem.makeThumbnail(from: image, maxSize: maxDimension)
            photoLoadingSignposter.endInterval("MakeThumbnail", thumbState)
            let decodeState = photoLoadingSignposter.beginInterval("Decompress", id: photoLoadingSignposter.makeSignpostID())
            let result = await resized.byPreparingForDisplay() ?? resized
            photoLoadingSignposter.endInterval("Decompress", decodeState)
            return result
        case let .camera(image, _):
            let thumbState = photoLoadingSignposter.beginInterval("MakeThumbnail", id: photoLoadingSignposter.makeSignpostID())
            let resized = PhotoItem.makeThumbnail(from: image, maxSize: maxDimension)
            photoLoadingSignposter.endInterval("MakeThumbnail", thumbState)
            let decodeState = photoLoadingSignposter.beginInterval("Decompress", id: photoLoadingSignposter.makeSignpostID())
            let result = await resized.byPreparingForDisplay() ?? resized
            photoLoadingSignposter.endInterval("Decompress", decodeState)
            return result
        }
    }
}

// MARK: - Photo carousel view

struct PhotoCarouselView: View {
    let items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    let sendExif: Bool

    @State private var showingCarouselAlt = false
    @State private var cacheStore = PreviewCacheStore()

    private var selectedIndex: Int? {
        guard let id = selectedPhotoID else { return nil }
        return items.firstIndex(where: { $0.id == id })
    }

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            let ratios = items.map(\.naturalAspect)
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
                                    aspectRatio: item.naturalAspect,
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
            .background(Color(.secondarySystemBackground))
        }
    }

    @ViewBuilder
    private var pageIndicator: some View {
        if items.count > 1 {
            let current = selectedIndex ?? 0
            let ratios = items.map(\.naturalAspect)
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

// MARK: - Editor mode

enum EditorMode: Equatable, CaseIterable {
    case preview
    case reorder
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

struct CellGeometry: Equatable {
    let mode: EditorMode
    let maskSide: CGFloat
    let photoAspect: CGFloat

    var photoSize: CGSize {
        switch mode {
        case .preview:
            photoAspect >= 1
                ? CGSize(width: maskSide * photoAspect, height: maskSide)
                : CGSize(width: maskSide, height: maskSide / photoAspect)
        case .reorder:
            photoAspect >= 1
                ? CGSize(width: maskSide, height: maskSide / photoAspect)
                : CGSize(width: maskSide * photoAspect, height: maskSide)
        case .captions:
            photoAspect >= 1
                ? CGSize(width: maskSide * photoAspect, height: maskSide)
                : CGSize(width: maskSide, height: maskSide / photoAspect)
        }
    }

    var maskCornerRadius: CGFloat {
        mode == .reorder ? 0 : 8
    }
}

// MARK: - Wallet-style removal transition

private struct WalletRemoveModifier: ViewModifier {
    let isRemoving: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(isRemoving ? 0.5 : 1, anchor: .center)
            .offset(y: isRemoving ? -20 : 0)
            .opacity(isRemoving ? 0 : 1)
    }
}

extension AnyTransition {
    static var walletRemove: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.85).combined(with: .opacity),
            removal: .modifier(
                active: WalletRemoveModifier(isRemoving: true),
                identity: WalletRemoveModifier(isRemoving: false)
            )
        )
    }
}

// MARK: - GalleryEditor

struct GalleryEditor: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    @Binding var isReordering: Bool
    @Binding var isAnimatingMode: Bool
    @Binding var mode: EditorMode
    let sendExif: Bool
    var onDeleteItem: ((PhotoItem) -> Void)?
    @State private var gridContainerWidth: CGFloat = 0
    @State private var stripState = StripScrollState()
    @State private var reorderState = ReorderDragState()

    private var selectedIndex: Int? {
        guard let id = selectedPhotoID else { return nil }
        return items.firstIndex(where: { $0.id == id })
    }

    // Grid constants (shared with AdaptivePhotoLayout)
    private let gridColumnCount = 3
    private let gridSpacing: CGFloat = 4
    private let gridOuterPadding: CGFloat = 16

    private var gridCellSide: CGFloat {
        let total = max(0, gridContainerWidth - gridOuterPadding * 2 - gridSpacing * CGFloat(gridColumnCount - 1))
        return max(1, total / CGFloat(gridColumnCount))
    }

    private var gridStride: CGSize {
        let side = gridCellSide + gridSpacing
        return CGSize(width: side, height: side)
    }

    private var maskSide: CGFloat {
        switch mode {
        case .preview: StripScrollState.thumbSize
        case .reorder: gridCellSide
        case .captions: 60
        }
    }

    private var dragPlacement: ReorderDragPlacement? {
        guard let start = reorderState.dragStartIndex,
              let current = reorderState.dragCurrentIndex
        else { return nil }
        return ReorderDragPlacement(draggedIndex: start, currentIndex: current)
    }

    /// Mode binding with animation gate. Uses `withAnimation` completion
    /// instead of timer-based gate drop — no matchedGeometryEffect means
    /// completion actually fires. Safety-net timer per debugging playbook.
    private var modeBinding: Binding<EditorMode> {
        Binding(
            get: { mode },
            set: { newMode in
                guard newMode != mode, !isAnimatingMode, !reorderState.isDragging else { return }

                let morphSpid = morphSignposter.makeSignpostID()
                let morphState = morphSignposter.beginInterval(
                    "MorphAnimation", id: morphSpid,
                    "from=\(mode.label),to=\(newMode.label)"
                )

                isAnimatingMode = true
                withAnimation(.smooth) {
                    mode = newMode
                } completion: {
                    morphSignposter.endInterval("MorphAnimation", morphState, "path=completion")
                    isAnimatingMode = false
                }
                // Safety net — completion should fire, but iOS can drop it
                // if a concurrent transaction replaces the animation mid-flight.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    isAnimatingMode = false
                }
            }
        )
    }

    var body: some View {
        // MARK: Photos section

        Section {
            AdaptivePhotoLayout(
                mode: mode,
                containerWidth: gridContainerWidth,
                stripScrollOffset: stripState.currentOffset,
                dragPlacement: dragPlacement
            ) {
                ForEach($items) { $item in
                    let index = items.firstIndex(where: { $0.id == item.id }) ?? 0
                    let exifState: ExifState = {
                        guard item.exifSummary != nil else { return .absent }
                        return sendExif ? .active : .inactive
                    }()

                    cellView(item: $item, index: index, exifState: exifState)
                        // Live drag position: offset tracks the finger without animation.
                        // dragOffset is kept out of the Layout so the sibling spring
                        // animation is never contaminated by the immediate offset update.
                        .offset(
                            x: reorderState.draggedID == item.id ? reorderState.dragOffset.width : 0,
                            y: reorderState.draggedID == item.id ? reorderState.dragOffset.height : 0
                        )
                        .zIndex(reorderState.draggedID == item.id ? 1000 : 0)
                        .gesture(
                            ReorderRecognizer(isEnabled: mode == .reorder) { phase, translation in
                                handleReorder(phase: phase, translation: translation, itemID: item.id, index: index)
                            }
                        )
                        .transition(mode == .preview ? .walletRemove : .opacity)
                        .layoutValue(key: PhotoIndexKey.self, value: index)
                }
            }
            // No explicit .clipped() — the Form Section row clips its content
            // naturally. Adding .clipped() here over-clips cells at strip edges
            // (the X button and cell frame extend past the layout bounds when
            // partially scrolled off-screen, cutting into the visible portion).
            .contentShape(Rectangle())
            .animation(.smooth, value: mode)
            .gesture(
                StripPanRecognizer(
                    isEnabled: mode == .preview,
                    onChanged: { stripState.dragTranslation = $0 },
                    onEnded: { t, p in
                        stripState.handleDragEnded(
                            translation: t,
                            predictedEnd: p,
                            containerWidth: gridContainerWidth,
                            itemCount: items.count
                        )
                    }
                )
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newHeight in
                // Signpost the actual rendered row height so Instruments shows
                // whether the section box is sized correctly per mode.
                morphSignposter.emitEvent("LayoutRowHeight", "mode=\(mode.label),h=\(Int(newHeight))")
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { newWidth in
                guard newWidth > 0 else { return }
                var t = Transaction()
                t.animation = nil
                withTransaction(t) { gridContainerWidth = newWidth }
            }
            .onChange(of: gridContainerWidth) { _, newWidth in
                guard newWidth > 0, !isAnimatingMode else { return }
                if let id = selectedPhotoID,
                   let idx = items.firstIndex(where: { $0.id == id })
                {
                    stripState.scrollToIndex(idx, itemCount: items.count, containerWidth: newWidth, animated: false)
                }
            }
            .onChange(of: selectedPhotoID) { _, newID in
                guard mode == .preview, !isAnimatingMode,
                      let newID, let idx = items.firstIndex(where: { $0.id == newID })
                else { return }
                stripState.scrollToIndex(idx, itemCount: items.count, containerWidth: gridContainerWidth)
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .preview, gridContainerWidth > 0,
                   let id = selectedPhotoID,
                   let idx = items.firstIndex(where: { $0.id == id })
                {
                    stripState.scrollToIndex(idx, itemCount: items.count, containerWidth: gridContainerWidth, animated: false)
                }
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
    }

    // MARK: - Cell view

    private func cellView(item: Binding<PhotoItem>, index: Int, exifState: ExifState) -> some View {
        HStack(alignment: .top, spacing: mode == .captions ? 12 : 0) {
            PhotoThumbnailCell(
                item: item,
                geometry: CellGeometry(
                    mode: mode,
                    maskSide: maskSide,
                    photoAspect: item.wrappedValue.naturalAspect
                ),
                isSelected: mode == .preview && selectedPhotoID == item.wrappedValue.id,
                isDragging: reorderState.draggedID == item.wrappedValue.id,
                hideDelete: mode != .preview,
                deleteOpacity: mode == .preview
                    ? stripState.deleteOpacity(cellIndex: index, containerWidth: gridContainerWidth)
                    : 1,
                exifState: mode == .reorder ? .absent : exifState,
                isAnimatingMode: isAnimatingMode,
                onTap: { handleCellTap(itemID: item.wrappedValue.id, index: index) },
                onDelete: { handleDelete(itemID: item.wrappedValue.id) }
            )

            if mode == .captions {
                TextField("Add a description", text: item.alt, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(2 ... 4)

                Spacer(minLength: 0)

                if !item.wrappedValue.alt.isEmpty {
                    Button {
                        item.wrappedValue.alt = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear caption")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if mode == .captions {
                Divider()
                    .padding(.leading, maskSide + 12)
            }
        }
    }

    // MARK: - Handlers

    private func handleCellTap(itemID: UUID, index: Int) {
        guard mode == .preview else { return }
        withAnimation(.snappy) {
            selectedPhotoID = itemID
            stripState.baseOffset = StripScrollState.offset(
                forIndex: index,
                itemCount: items.count,
                containerWidth: gridContainerWidth
            )
        }
    }

    private func handleDelete(itemID: UUID) {
        if let item = items.first(where: { $0.id == itemID }) {
            onDeleteItem?(item)
        }
        if selectedPhotoID == itemID,
           let removedIdx = items.firstIndex(where: { $0.id == itemID })
        {
            let newID: UUID? = removedIdx > 0
                ? items[removedIdx - 1].id
                : removedIdx < items.count - 1 ? items[removedIdx + 1].id : nil
            selectedPhotoID = newID
        }
        let curve: Animation = mode == .preview
            ? .smooth
            : .spring(response: 0.3, dampingFraction: 0.8)
        withAnimation(curve) {
            items.removeAll { $0.id == itemID }
        }
    }

    private func handleReorder(
        phase: ReorderRecognizer.Phase,
        translation: CGSize,
        itemID: UUID,
        index: Int
    ) {
        switch phase {
        case .arming:
            reorderSignposter.emitEvent("Arming", "idx=\(index)")
            isReordering = true
        case .began:
            reorderSignposter.emitEvent("DragBegan", "idx=\(index)")
            reorderState.beginDrag(itemID: itemID, at: index)
        case .changed:
            if let proposed = reorderState.handleDragChanged(
                translation: translation,
                itemCount: items.count,
                columnCount: gridColumnCount,
                stride: gridStride
            ) {
                reorderSignposter.emitEvent(
                    "SlotChange",
                    "from=\(reorderState.dragCurrentIndex ?? -1),to=\(proposed)"
                )
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    reorderState.dragCurrentIndex = proposed
                }
                reorderState.selectionGenerator.selectionChanged()
            }
        case .ended, .cancelled:
            if let start = reorderState.dragStartIndex,
               let current = reorderState.dragCurrentIndex,
               start != current
            {
                reorderSignposter.emitEvent("DragEnded", "start=\(start),final=\(current)")
                withAnimation(.snappy) {
                    items.move(
                        fromOffsets: IndexSet(integer: start),
                        toOffset: current > start ? current + 1 : current
                    )
                    reorderState.dragOffset = .zero
                    reorderState.dragStartIndex = nil
                    reorderState.dragCurrentIndex = nil
                    isReordering = false
                } completion: {
                    reorderState.draggedID = nil
                }
            } else {
                reorderSignposter.emitEvent("DragCancelled", "idx=\(index)")
                reorderState.reset()
                isReordering = false
            }
        }
    }
}

#Preview {
    @Previewable @State var state: [PhotoItem] = PreviewData.photoItemsWithExif
    @Previewable @State var selected: UUID?
    @Previewable @State var mode: EditorMode = .preview
    @Previewable @State var isReordering = false
    @Previewable @State var isAnimatingMode = false
    @Previewable @State var zoomState = ImageZoomState()
    Form {
        GalleryEditor(
            items: $state,
            selectedPhotoID: $selected,
            isReordering: $isReordering,
            isAnimatingMode: $isAnimatingMode,
            mode: $mode,
            sendExif: false
        )
    }
    .scrollDisabled(isReordering || isAnimatingMode)
    .environment(zoomState)
    .modifier(ImageZoomOverlay(zoomState: zoomState))
    .onAppear { selected = state.first?.id }
    .grainPreview()
}

import SwiftUI

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

private extension AnyTransition {
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

// MARK: - Strip View

struct ReorderablePhotoStrip: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    var onTapped: ((UUID) -> Void)?

    // Drag state — visual only. items[] is mutated exactly once on release.
    @State private var draggedID: UUID?
    @State private var dragStartIndex: Int?
    @State private var dragCurrentIndex: Int?
    @State private var dragOffsetX: CGFloat = 0
    /// Live scroll offset and the previous frame's value, so we can compute the delta
    /// when auto-scroll fires and manually compensate dragOffsetX (which keeps the
    /// dragged cell glued to the finger even when the scroll animates).
    @State private var scrollOffsetX: CGFloat = 0
    @State private var lastScrollOffsetX: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var lastAutoScrollAt: Date = .distantPast

    private let thumbSize: CGFloat = 72
    private let spacing: CGFloat = 20
    private let verticalPadding: CGFloat = 22
    private let horizontalPadding: CGFloat = 24
    /// Edge zone measured from where photos visually start/end inside the strip
    /// (i.e., from `horizontalPadding` in from the ScrollView frame). 80pt sensitivity.
    private let edgeZone: CGFloat = 80
    private var cellWidth: CGFloat {
        thumbSize + spacing
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(items) { item in
                        PhotoThumbnailCell(
                            item: bindingFor(itemID: item.id),
                            mode: .square(thumbSize),
                            isSelected: selectedPhotoID == item.id,
                            // All Xs always visible. The dragged cell's zIndex(1)
                            // visually covers other cells (and their Xs) when
                            // overlapping; that's the "Xs are below the picked-up
                            // photo" effect, achieved via z-order, not visibility.
                            hideDelete: false,
                            onTap: {
                                guard draggedID == nil else { return }
                                onTapped?(item.id)
                                selectedPhotoID = item.id
                            },
                            onDelete: { handleDelete(item: item) }
                        )
                        .id(item.id)
                        .offset(x: xOffset(for: item))
                        .geometryGroup()
                        .zIndex(draggedID == item.id ? 1 : 0)
                        .transition(.walletRemove)
                        // UIKit-backed long-press-drag recognizer (ReorderRecognizer).
                        // SwiftUI's LongPressGesture.sequenced(DragGesture) breaks
                        // scroll AND inner taps on real hardware even with
                        // .simultaneousGesture; the UIKit recognizer cooperates
                        // properly because it sets cancelsTouchesInView=false and
                        // implements shouldRecognizeSimultaneouslyWith.
                        .gesture(
                            ReorderRecognizer { phase, translation in
                                handleReorder(
                                    phase: phase,
                                    translation: translation,
                                    item: item,
                                    proxy: proxy
                                )
                            }
                        )
                    }
                }
                .padding(.top, verticalPadding)
                .padding(.bottom, verticalPadding)
                .padding(.horizontal, horizontalPadding)
            }
            .scrollClipDisabled()
            .frame(height: thumbSize + verticalPadding * 2)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, geo in
                let newOffset = geo.contentOffset.x
                if draggedID != nil {
                    // Scroll moved; compensate dragOffsetX so the cell appears stationary
                    // relative to the finger. Without this, drag.onChanged doesn't fire
                    // during auto-scroll animations and the cell jitters.
                    let delta = newOffset - lastScrollOffsetX
                    dragOffsetX += delta
                }
                lastScrollOffsetX = newOffset
                scrollOffsetX = newOffset
                viewportWidth = geo.containerSize.width
            }
            .onChange(of: selectedPhotoID) {
                guard let id = selectedPhotoID, draggedID == nil else { return }
                withAnimation(.smooth) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Reorder dispatch (driven by ReorderRecognizer)

    private func handleReorder(
        phase: ReorderRecognizer.Phase,
        translation: CGSize,
        item: PhotoItem,
        proxy: ScrollViewProxy
    ) {
        switch phase {
        case .began:
            beginDrag(item: item)
        case .changed:
            handleDragChanged(translationX: translation.width, proxy: proxy)
        case .ended, .cancelled:
            handleDragEnded(proxy: proxy)
        }
    }

    /// SO-style live preview: dragged item follows the finger via dragOffsetX, siblings
    /// between dragStartIndex and dragCurrentIndex shift one cell-width to make room.
    /// items[] is NOT mutated until release — what you see is what you'll commit.
    private func xOffset(for item: PhotoItem) -> CGFloat {
        guard let draggedID,
              let start = dragStartIndex,
              let current = dragCurrentIndex,
              let index = items.firstIndex(where: { $0.id == item.id })
        else { return 0 }

        if item.id == draggedID {
            return dragOffsetX
        }
        if current > start, index > start, index <= current {
            return -cellWidth
        }
        if current < start, index >= current, index < start {
            return cellWidth
        }
        return 0
    }

    private func beginDrag(item: PhotoItem) {
        guard draggedID == nil,
              let idx = items.firstIndex(where: { $0.id == item.id })
        else { return }
        draggedID = item.id
        dragStartIndex = idx
        dragCurrentIndex = idx
        // Safety: sync lastScrollOffsetX to the current scroll position so the
        // first .onScrollGeometryChange delta during this drag is 0, not a stale
        // value carried over from before the drag started.
        lastScrollOffsetX = scrollOffsetX
        // Reset the auto-scroll throttle so the first edge crossing fires immediately.
        lastAutoScrollAt = .distantPast
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func handleDragChanged(translationX rawOffset: CGFloat, proxy: ScrollViewProxy) {
        guard let start = dragStartIndex else { return }

        // Hard clamp: dragged cell can extend at most 1/3 of its width past either
        // visible edge. Bounding the drag eliminates the auto-scroll jitter because
        // the cell can't run away while the scroll catches up.
        let naturalX = horizontalPadding + CGFloat(start) * cellWidth
        // Min allowed dragOffsetX: makes the cell's left edge sit at -thumbSize/3.
        let minOffset = -thumbSize / 3 + scrollOffsetX - naturalX
        // Max allowed dragOffsetX: makes the cell's right edge sit at viewportWidth + thumbSize/3.
        let maxOffset = viewportWidth - thumbSize * 2 / 3 + scrollOffsetX - naturalX
        dragOffsetX = max(minOffset, min(maxOffset, rawOffset))

        let proposed = max(0, min(items.count - 1, start + Int((dragOffsetX / cellWidth).rounded())))
        if proposed != dragCurrentIndex {
            // Longer spring than .snappy so the live preview slide is visibly
            // smooth — siblings glide into place instead of popping.
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                dragCurrentIndex = proposed
            }
            UISelectionFeedbackGenerator().selectionChanged()
        }

        autoScrollIfNeeded(proxy: proxy)
    }

    /// Auto-scroll the strip when the dragged cell nears either visible edge.
    /// Uses the dragged cell's center (computed from its natural slot + dragOffset
    /// minus the current scroll offset) as a finger-position proxy. ReorderRecognizer
    /// gives us translation only, not absolute touch location, so we infer instead.
    private func autoScrollIfNeeded(proxy: ScrollViewProxy) {
        guard viewportWidth > 0,
              let start = dragStartIndex,
              let current = dragCurrentIndex else { return }

        // Cell center in viewport coords. naturalX is the cell's left edge in
        // content coords; subtracting scrollOffsetX brings it to viewport coords;
        // adding dragOffsetX accounts for the live drag, then half cellWidth gives
        // the center.
        let naturalX = horizontalPadding + CGFloat(start) * cellWidth
        let cellCenterViewportX = naturalX - scrollOffsetX + dragOffsetX + thumbSize / 2

        let leadingTrigger = horizontalPadding + edgeZone
        let trailingTrigger = viewportWidth - horizontalPadding - edgeZone

        let nowDate = Date()
        guard nowDate.timeIntervalSince(lastAutoScrollAt) > 0.15 else { return }

        if cellCenterViewportX < leadingTrigger, current > 0 {
            lastAutoScrollAt = nowDate
            let targetID = items[max(0, current - 1)].id
            withAnimation(.smooth) {
                proxy.scrollTo(targetID, anchor: .leading)
            }
        } else if cellCenterViewportX > trailingTrigger, current < items.count - 1 {
            lastAutoScrollAt = nowDate
            let targetID = items[min(items.count - 1, current + 1)].id
            withAnimation(.smooth) {
                proxy.scrollTo(targetID, anchor: .trailing)
            }
        }
    }

    private func handleDragEnded(proxy: ScrollViewProxy) {
        guard let start = dragStartIndex,
              let current = dragCurrentIndex
        else {
            resetDragState()
            return
        }

        var movedID: UUID?
        if start != current {
            movedID = items[start].id
            withAnimation(.snappy) {
                items.move(
                    fromOffsets: IndexSet(integer: start),
                    toOffset: current > start ? current + 1 : current
                )
            }
        }

        withAnimation(.snappy) {
            dragOffsetX = 0
        }
        resetDragState()

        // Scroll-to-reveal: brief delay so the move animation settles first.
        if let movedID {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.smooth) {
                    proxy.scrollTo(movedID, anchor: .center)
                }
            }
        }
    }

    private func resetDragState() {
        draggedID = nil
        dragStartIndex = nil
        dragCurrentIndex = nil
    }

    // MARK: - Delete logic

    /// When deleting the selected photo: prefer the previous index, fall back to next,
    /// fall back to nil. When deleting a non-selected photo: leave selection unchanged.
    private func handleDelete(item: PhotoItem) {
        let removedID = item.id
        if selectedPhotoID == removedID,
           let removedIdx = items.firstIndex(where: { $0.id == removedID })
        {
            if removedIdx > 0 {
                selectedPhotoID = items[removedIdx - 1].id
            } else if removedIdx < items.count - 1 {
                selectedPhotoID = items[removedIdx + 1].id
            } else {
                selectedPhotoID = nil
            }
        }
        items.removeAll { $0.id == removedID }
    }

    private func bindingFor(itemID: UUID) -> Binding<PhotoItem> {
        Binding(
            get: { items.first(where: { $0.id == itemID }) ?? items[0] },
            set: { newValue in
                if let idx = items.firstIndex(where: { $0.id == itemID }) {
                    items[idx] = newValue
                }
            }
        )
    }
}

#Preview {
    @Previewable @State var state: [PhotoItem] = PreviewData.photoItems
    @Previewable @State var selected: UUID?
    ReorderablePhotoStrip(items: $state, selectedPhotoID: $selected)
        .padding()
        .onAppear { selected = state.first?.id }
        .preferredColorScheme(.dark)
}

import os
import SwiftUI
import UIKit

private let stripSignposter = OSSignposter(subsystem: "social.grain.grain", category: "Animation.Strip")

// MARK: - UIKit-backed pan recognizer

/// UIKit-backed pan gesture for the photo strip's horizontal scroll.
/// Replaces SwiftUI's `DragGesture` which created a UIKit recognizer
/// that competed with the Form's `UICollectionView` pan — blocking
/// vertical scroll on the strip even with `.simultaneousGesture`.
/// Same simultaneous-recognition delegate pattern as `ReorderRecognizer`.
private struct StripPanRecognizer: UIGestureRecognizerRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (_ translation: CGFloat, _ predictedEnd: CGFloat) -> Void

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_: UIPanGestureRecognizer, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let coordinator = context.coordinator
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .changed:
            coordinator.onChanged(translation)
        case .ended:
            let velocity = recognizer.velocity(in: recognizer.view).x
            coordinator.onEnded(translation, translation + velocity * 0.25)
        case .cancelled, .failed:
            coordinator.onEnded(translation, translation)
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void
        var onEnded: (_ translation: CGFloat, _ predictedEnd: CGFloat) -> Void

        init(
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping (_ translation: CGFloat, _ predictedEnd: CGFloat) -> Void
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        /// Only begin if the initial swipe direction is predominantly
        /// horizontal. Vertical-dominant swipes never transition to .began,
        /// so the Form's UICollectionView scroll view claims them
        /// uncontested — this is the fix for "vertical scroll broken on
        /// strip". Without this, the pan recognizer claimed every direction
        /// and, even with shouldRecognizeSimultaneouslyWith, the Form's
        /// scroll view sometimes deferred to our recognizer.
        nonisolated func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // UIKit delegate methods always dispatch on the main thread;
            // assumeIsolated silences the strict-concurrency warning
            // without adding an unnecessary hop.
            MainActor.assumeIsolated {
                guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
                let velocity = pan.velocity(in: pan.view)
                return abs(velocity.x) > abs(velocity.y)
            }
        }

        nonisolated func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
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

// MARK: - PhotoStrip

/// Read-only horizontal strip of square photo thumbnails. Pure SwiftUI —
/// NO UIScrollView. The HStack is positioned via `@State baseOffset` +
/// `@GestureState dragTranslation`, so layout settles in ONE synchronous
/// SwiftUI pass instead of UIScrollView's async contentOffset propagation.
///
/// Why this matters for matched-geometry: with the old UIScrollView-backed
/// strip, cells mounted at scroll=0 regardless of `.scrollPosition(id:)`
/// because UIKit applied the scroll position asynchronously. Matched-geometry
/// therefore captured destination frames at scroll=0, and the morph followed
/// a two-step "morph then scroll" path. With a pure @State offset, the
/// init pre-seeds `baseOffset` from the selected photo's index + the
/// pre-measured `containerWidth` — the strip mounts already centered on the
/// current selection, so matched-geometry captures destinations at their
/// final resting positions on the first layout pass.
///
/// Visibility gate: only cells that are ACTUALLY VISIBLE at currentOffset
/// participate in matched-geometry. Off-screen cells get
/// `matchedNamespace: nil` and a `.opacity` transition so they fade in/out
/// instead of flying from origins that have no visual meaning. This is the
/// fix for photos-with-off-screen-targets sliding diagonally across the
/// screen during the morph.
struct PhotoStrip: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    /// Shared matched-geometry namespace for the photo view inside each cell.
    var matchedNamespace: Namespace.ID?
    /// True for the duration of the strip↔grid mode swap.
    var isAnimatingMode: Bool = false
    var sendExif: Bool = true
    /// Pre-measured width of the strip's row. PhotoEditor measures the Group
    /// containing strip/grid/captions via `.onGeometryChange` and passes the
    /// width here so the strip's init can compute a centered `baseOffset`
    /// BEFORE the first layout pass. This is the whole point of the
    /// UIScrollView replacement — with containerWidth known at init time,
    /// the first layout captures matched-geometry destination frames at the
    /// correct pre-scrolled positions.
    var containerWidth: CGFloat = 0
    var onTapped: ((UUID) -> Void)?

    /// Base horizontal offset applied to the HStack. Updated in onTap and
    /// `.onChange(of: selectedPhotoID)`. The user's live drag adds
    /// `dragTranslation` on top of this.
    @State private var baseOffset: CGFloat
    /// Live horizontal drag translation from `StripPanRecognizer`.
    /// `@State` (not `@GestureState`) because UIKit gesture recognizers
    /// don't participate in SwiftUI's gesture-state auto-reset lifecycle.
    /// Manually reset in `handleStripDragEnded`.
    @State private var dragTranslation: CGFloat = 0

    static let thumbSize: CGFloat = 72
    static let spacing: CGFloat = 20
    private let verticalPadding: CGFloat = 22

    init(
        items: Binding<[PhotoItem]>,
        selectedPhotoID: Binding<UUID?>,
        matchedNamespace: Namespace.ID? = nil,
        isAnimatingMode: Bool = false,
        sendExif: Bool = true,
        containerWidth: CGFloat = 0,
        onTapped: ((UUID) -> Void)? = nil
    ) {
        _items = items
        _selectedPhotoID = selectedPhotoID
        // Pre-seed baseOffset so the first layout pass renders cells at their
        // correct centered positions. Reading wrappedValue in init is safe:
        // @State is only initialized once; subsequent re-renders skip this
        // path and keep the existing @State value. For subsequent updates
        // (carousel swipe, late-arriving containerWidth), see the onChange
        // handlers below.
        let allItems = items.wrappedValue
        let currentID = selectedPhotoID.wrappedValue
        let idx = allItems.firstIndex(where: { $0.id == currentID }) ?? 0
        _baseOffset = State(
            initialValue: Self.offset(
                forIndex: idx,
                itemCount: allItems.count,
                containerWidth: containerWidth
            )
        )
        self.matchedNamespace = matchedNamespace
        self.isAnimatingMode = isAnimatingMode
        self.sendExif = sendExif
        self.containerWidth = containerWidth
        self.onTapped = onTapped
    }

    // MARK: - Pure layout math

    /// Pure function: compute the baseOffset that centers the cell at `idx`
    /// within a container of width `W`. Clamps so content can never scroll
    /// past its leading or trailing edge. Called from init to pre-seed the
    /// first layout pass, and from onTap/onChange/handleDelete to animate
    /// to a new centered position.
    static func offset(forIndex idx: Int, itemCount: Int, containerWidth W: CGFloat) -> CGFloat {
        guard itemCount > 0, W > 0 else { return 0 }
        let stride = thumbSize + spacing
        let halfCell = thumbSize / 2
        // Unclamped: put cell `idx`'s center at W/2.
        let unclamped = W / 2 - halfCell - CGFloat(idx) * stride
        return clamp(unclamped, itemCount: itemCount, containerWidth: W)
    }

    /// Clamp an offset to `[minOffset, maxOffset]` so the HStack cannot
    /// scroll past its own bounds. `maxOffset = 0` (leading edge flush with
    /// container leading); `minOffset = min(0, W - contentWidth)` (trailing
    /// edge flush, or 0 if all content already fits).
    static func clamp(_ offset: CGFloat, itemCount: Int, containerWidth W: CGFloat) -> CGFloat {
        guard itemCount > 0, W > 0 else { return 0 }
        let contentWidth = CGFloat(itemCount) * thumbSize
            + CGFloat(max(0, itemCount - 1)) * spacing
        let maxOffset: CGFloat = 0
        let minOffset: CGFloat = min(0, W - contentWidth)
        return max(minOffset, min(maxOffset, offset))
    }

    private var currentOffset: CGFloat {
        baseOffset + dragTranslation
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            HStack(spacing: Self.spacing) {
                ForEach($items) { $item in
                    let id = item.id
                    let exifState: ExifState = {
                        guard item.exifSummary != nil else { return .absent }
                        return sendExif ? .active : .inactive
                    }()
                    // O(n) index lookup per cell per render. n ≤ ~20 photos
                    // in practice so O(n²) per render is fine; the
                    // enumerated/indices alternative loses the stable
                    // Identifiable-backed ForEach identity.
                    let idx = items.firstIndex(where: { $0.id == id }) ?? 0
                    // Fraction of the cell's width that overlaps [0, W].
                    // Drives opacity so cells fade as they slide off the edge,
                    // and disables hit-testing when < 50% visible so a
                    // partially-obscured X button can't be accidentally tapped.
                    // Base deleteOpacity on the X button's own screen position, not
                    // the whole cell's overlap. The X is at the cell's top-right
                    // corner (center = cellLeft + thumbSize), so it can be fully
                    // on-screen even when most of the cell has slid off the left
                    // edge. Fades the X over one cell-width of margin from either
                    // screen edge so it vanishes exactly as it reaches the boundary.
                    let cellLeft = currentOffset + CGFloat(idx) * (Self.thumbSize + Self.spacing)
                    let offLeft = -cellLeft // > 0 when left edge is off-screen
                    let offRight = (cellLeft + Self.thumbSize) - W // > 0 when right edge is off-screen
                    // X button center in container coords (top-right corner of cell).
                    let xCenterX = cellLeft + Self.thumbSize
                    // Shrink the X so its circle fits within the screen edge, with
                    // a little padding. Scale = 1 while the cell is fully on-screen.
                    // Scale reaches 0 only when the circle can no longer fit at all.
                    let xRadius: CGFloat = 11 // half of the 22pt icon
                    let xPadding: CGFloat = 2
                    // Immediately-invoked closure so the if/else doesn't land in
                    // the @ViewBuilder result builder as a conditional view.
                    let deleteOpacity: CGFloat = {
                        if offLeft > 0 {
                            // Going off left — X (at cell right edge) trails the
                            // cell by thumbSize, giving a natural fade window.
                            // Use X center distance from left boundary.
                            let dist = xCenterX
                            return dist >= xRadius + xPadding ? 1 : max(0, (dist - xPadding) / xRadius)
                        } else if offRight > 0 {
                            // Going off right — X is at the cell's right edge so
                            // it crosses W the instant offRight > 0; using X
                            // center distance gives immediate pop. Instead measure
                            // from the cell's LEFT edge, which still has thumbSize
                            // of travel before it reaches W — the same natural lag
                            // window as the left side.
                            let dist = W - cellLeft
                            return dist >= xRadius + xPadding ? 1 : max(0, (dist - xPadding) / xRadius)
                        }
                        return 1
                    }()

                    PhotoThumbnailCell(
                        item: $item,
                        geometry: CellGeometry(
                            mode: .preview,
                            maskSide: Self.thumbSize,
                            photoAspect: item.naturalAspect
                        ),
                        isSelected: selectedPhotoID == id,
                        deleteOpacity: deleteOpacity,
                        exifState: exifState,
                        matchedNamespace: matchedNamespace,
                        isAnimatingMode: isAnimatingMode,
                        onTap: {
                            onTapped?(id)
                            stripSignposter.emitEvent(
                                "StripTap",
                                "animatingMode=\(isAnimatingMode),idx=\(idx)"
                            )
                            let target = Self.offset(
                                forIndex: idx,
                                itemCount: items.count,
                                containerWidth: W
                            )
                            // Drive both state mutations in the same
                            // transaction so onChange's redundant update
                            // short-circuits via the guard below.
                            withAnimation(.snappy) {
                                selectedPhotoID = id
                                baseOffset = target
                            }
                        },
                        onDelete: { handleDelete(itemID: id, containerWidth: W) }
                    )
                    .id(id)
                    // During mode transitions matched-geometry drives the morph;
                    // walletRemove's competing scale+offset would distort perceived
                    // screen-space origins. Gate on isAnimatingMode suppresses it
                    // for morphs but preserves it for real deletions.
                    .transition(isAnimatingMode ? .identity : .walletRemove)
                }
            }
            .offset(x: currentOffset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.thumbSize + verticalPadding * 2)
            .contentShape(Rectangle())
            // UIKit-backed pan so the Form's vertical scroll still works
            // when the user swipes up/down on the strip. SwiftUI's
            // DragGesture (even with .simultaneousGesture) created a
            // UIKit recognizer that competed with the Form's
            // UICollectionView pan. The UIKit delegate's
            // shouldRecognizeSimultaneouslyWith: true is the only way
            // to let both fire.
            .gesture(
                StripPanRecognizer(
                    onChanged: { translation in
                        dragTranslation = translation
                    },
                    onEnded: { translation, predictedEnd in
                        handleStripDragEnded(
                            translation: translation,
                            predictedEnd: predictedEnd,
                            containerWidth: W
                        )
                    }
                )
            )
            .onChange(of: containerWidth) { _, newWidth in
                // Fallback for the initial-load case: if PhotoEditor's
                // `.onGeometryChange` hadn't fired before PhotoStrip's init,
                // containerWidth was 0 and baseOffset was pre-seeded to 0.
                // When the real width arrives, snap to the correct centered
                // position. No animation — this is a one-time catch-up for
                // view setup, not user-visible motion.
                guard !isAnimatingMode, newWidth > 0,
                      let currentID = selectedPhotoID,
                      let idx = items.firstIndex(where: { $0.id == currentID })
                else { return }
                let target = Self.offset(
                    forIndex: idx,
                    itemCount: items.count,
                    containerWidth: newWidth
                )
                if abs(target - baseOffset) < 0.5 { return }
                stripSignposter.emitEvent(
                    "StripContainerWidthInit",
                    "width=\(Int(newWidth.rounded())),idx=\(idx)"
                )
                baseOffset = target
            }
            .onChange(of: selectedPhotoID) { _, newID in
                // Skip during mode transitions — the TabView inside the
                // carousel can briefly reset selectedPhotoID on mount, which
                // would fire a spurious scroll-to-center mid-morph.
                guard !isAnimatingMode, let newID,
                      let idx = items.firstIndex(where: { $0.id == newID })
                else { return }
                let target = Self.offset(
                    forIndex: idx,
                    itemCount: items.count,
                    containerWidth: W
                )
                // Short-circuit if tap-inside-strip already set baseOffset
                // to the target in the same transaction. Without this guard
                // the carousel-swipe path would fire a second withAnimation
                // that competes with onTap's .snappy transaction.
                if abs(target - baseOffset) < 0.5 { return }
                stripSignposter.emitEvent(
                    "StripSelectedChanged",
                    "idx=\(idx),delta=\(Int((target - baseOffset).rounded()))"
                )
                withAnimation(.smooth) { baseOffset = target }
            }
        }
        .frame(height: Self.thumbSize + verticalPadding * 2)
    }

    // MARK: - Drag end handler

    /// Commit the drag position and animate to the nearest cell snap
    /// target. With `@State dragTranslation` (not `@GestureState`),
    /// there is no auto-reset race — we have the live value. Commit
    /// baseOffset and reset dragTranslation in the same render pass
    /// so `currentOffset` = committed + 0 = committed. No jump.
    private func handleStripDragEnded(
        translation: CGFloat,
        predictedEnd: CGFloat,
        containerWidth W: CGFloat
    ) {
        let originalBase = baseOffset
        let committed = Self.clamp(
            originalBase + translation,
            itemCount: items.count, containerWidth: W
        )
        baseOffset = committed
        dragTranslation = 0

        // Velocity-projected landing for nearest-cell snap.
        let projected = Self.clamp(
            originalBase + predictedEnd,
            itemCount: items.count, containerWidth: W
        )
        let nearest = items.indices.min(by: {
            abs(Self.offset(forIndex: $0, itemCount: items.count, containerWidth: W) - projected) <
                abs(Self.offset(forIndex: $1, itemCount: items.count, containerWidth: W) - projected)
        }) ?? 0
        stripSignposter.emitEvent(
            "StripDragEnded",
            "translation=\(Int(translation.rounded())),projected=\(Int(predictedEnd.rounded())),snapIdx=\(nearest)"
        )
        withAnimation(.snappy) {
            baseOffset = Self.offset(forIndex: nearest, itemCount: items.count, containerWidth: W)
        }
    }

    // MARK: - Delete logic

    /// When deleting the selected photo: prefer the previous index, fall
    /// back to next, fall back to nil. When deleting a non-selected photo,
    /// leave selection unchanged. After the removal animation settles the
    /// `.onChange(of: selectedPhotoID)` handler re-centers the strip on the
    /// new selection (if any) via its own `.smooth` transaction.
    private func handleDelete(itemID: UUID, containerWidth _: CGFloat) {
        let state = stripSignposter.beginInterval(
            "StripDelete",
            id: stripSignposter.makeSignpostID(),
            "isSelected=\(selectedPhotoID == itemID),animatingMode=\(isAnimatingMode)"
        )
        if selectedPhotoID == itemID,
           let removedIdx = items.firstIndex(where: { $0.id == itemID })
        {
            let newID: UUID? = removedIdx > 0
                ? items[removedIdx - 1].id
                : removedIdx < items.count - 1 ? items[removedIdx + 1].id : nil
            selectedPhotoID = newID
        }
        withAnimation(.smooth) {
            items.removeAll { $0.id == itemID }
        }
        stripSignposter.endInterval("StripDelete", state)
    }
}

#Preview {
    @Previewable @State var state: [PhotoItem] = Array(PreviewData.photoItems /* .prefix(5) */ )
    @Previewable @State var selected: UUID?
    PhotoStrip(
        items: $state,
        selectedPhotoID: $selected,
        containerWidth: 390
    )
    .padding()
    .frame(maxHeight: .infinity, alignment: .top)
    .onAppear { selected = state.first?.id }
    .grainPreview()
}

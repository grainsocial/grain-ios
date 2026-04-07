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

// MARK: - PhotoStrip

/// Read-only horizontal strip of square photo thumbnails. Tap a cell to select,
/// tap its X to delete. The strip has no reorder gesture — reordering lives
/// exclusively in the grid ("Reorder" mode) to keep the two modes distinct per
/// HIG modality guidance. Because the strip has no drag state, it doesn't need
/// to expose an `isReordering` binding or lock its scroll via ScrollPanLocker.
struct PhotoStrip: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    /// Shared matched-geometry namespace for the photo view inside each cell.
    /// Passed down to PhotoThumbnailCell so the strip and grid views of the same
    /// photo share geometry IDs — prep for the eventual strip↔grid transition.
    var matchedNamespace: Namespace.ID?
    /// Shared namespace for the selection ring matched-geometry effect.
    var selectionNamespace: Namespace.ID?
    /// True for the duration of the strip↔grid mode swap. Currently unused
    /// at the cell level (X buttons stay visible during the morph so they
    /// can ride the matched-geometry transition with the cell, per user
    /// feedback that the disappear/reappear was jarring). Kept on the API
    /// for the editor's convenience and in case future work needs it back.
    var isAnimatingMode: Bool = false
    var onTapped: ((UUID) -> Void)?

    private let thumbSize: CGFloat = 72
    private let spacing: CGFloat = 20
    private let verticalPadding: CGFloat = 22
    private let horizontalPadding: CGFloat = 24

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    // ForEach($items) for safe per-id Bindings — avoids the
                    // pre-existing `items[0]` crash when items is briefly empty
                    // mid-delete.
                    ForEach($items) { $item in
                        let id = item.id
                        PhotoThumbnailCell(
                            item: $item,
                            geometry: CellGeometry(
                                mode: .preview,
                                maskSide: thumbSize,
                                photoAspect: aspect(of: item)
                            ),
                            isSelected: selectedPhotoID == id,
                            matchedNamespace: matchedNamespace,
                            selectionNamespace: selectionNamespace,
                            onTap: {
                                onTapped?(id)
                                withAnimation(.snappy) { selectedPhotoID = id }
                            },
                            onDelete: { handleDelete(itemID: id) }
                        )
                        .id(id)
                        .transition(.walletRemove)
                    }
                }
                .padding(.top, verticalPadding)
                .padding(.bottom, verticalPadding)
                .padding(.horizontal, horizontalPadding)
            }
            .scrollClipDisabled()
            .frame(height: thumbSize + verticalPadding * 2)
            .onChange(of: selectedPhotoID) {
                guard let id = selectedPhotoID else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    /// Photo's natural aspect (w/h) used to build CellGeometry. Mirrors the
    /// `naturalAspect` calc in PhotoThumbnailCell.
    private func aspect(of item: PhotoItem) -> CGFloat {
        let w = item.thumbnail.size.width
        let h = item.thumbnail.size.height
        guard h > 0 else { return 1 }
        return w / h
    }

    // MARK: - Delete logic

    /// When deleting the selected photo: prefer the previous index, fall back
    /// to next, fall back to nil. When deleting a non-selected photo: leave
    /// selection unchanged.
    private func handleDelete(itemID: UUID) {
        if selectedPhotoID == itemID,
           let removedIdx = items.firstIndex(where: { $0.id == itemID })
        {
            if removedIdx > 0 {
                selectedPhotoID = items[removedIdx - 1].id
            } else if removedIdx < items.count - 1 {
                selectedPhotoID = items[removedIdx + 1].id
            } else {
                selectedPhotoID = nil
            }
        }
        withAnimation(.smooth) {
            items.removeAll { $0.id == itemID }
        }
    }
}

#Preview {
    @Previewable @State var state: [PhotoItem] = PreviewData.photoItems
    @Previewable @State var selected: UUID?
    PhotoStrip(items: $state, selectedPhotoID: $selected)
        .padding()
        .onAppear { selected = state.first?.id }
        .preferredColorScheme(.dark)
}

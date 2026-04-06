import SwiftUI

struct ReorderablePhotoStrip: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0
    private let thumbSize: CGFloat = 72
    private let spacing: CGFloat = 8

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(items) { item in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: item.thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: thumbSize, height: thumbSize)

                            Button {
                                withAnimation {
                                    items.removeAll { $0.id == item.id }
                                    if selectedPhotoID == item.id {
                                        selectedPhotoID = items.first?.id
                                    }
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .offset(x: 4, y: -4)
                        }
                        .reorderableThumbnail(
                            isDragging: draggingID == item.id,
                            isSelected: item.id == selectedPhotoID
                        )
                        .zIndex(draggingID == item.id ? 1 : 0)
                        .id(item.id)
                        .offset(x: draggingID == item.id ? dragOffset : 0)
                        .simultaneousGesture(TapGesture().onEnded {
                            guard draggingID == nil else { return }
                            selectedPhotoID = item.id
                        })
                        .gesture(
                            LongPressGesture(minimumDuration: 0.2)
                                .sequenced(before: DragGesture())
                                .onChanged { value in
                                    switch value {
                                    case .second(true, let drag):
                                        if draggingID == nil {
                                            draggingID = item.id
                                        }
                                        if let drag {
                                            dragOffset = drag.translation.width
                                            reorderIfNeeded()
                                        }
                                    default:
                                        break
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                                        draggingID = nil
                                        dragOffset = 0
                                    }
                                }
                        )
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 16)
            }
            .onChange(of: selectedPhotoID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        } // ScrollViewReader
    }

    private func reorderIfNeeded() {
        guard let draggingID,
              let currentIndex = items.firstIndex(where: { $0.id == draggingID })
        else { return }

        let step = thumbSize + spacing
        let steps = Int((dragOffset / step).rounded())

        let targetIndex = max(0, min(items.count - 1, currentIndex + steps))
        if targetIndex != currentIndex {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7, blendDuration: 0)) {
                items.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex)
            }
            dragOffset -= CGFloat(targetIndex - currentIndex) * step
        }
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

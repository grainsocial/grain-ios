import SwiftUI

struct ReorderablePhotoStrip: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0
    private let thumbSize: CGFloat = 72
    private let spacing: CGFloat = 8

    var body: some View {
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
        }
    }

    private func reorderIfNeeded() {
        guard let draggingID,
              let currentIndex = items.firstIndex(where: { $0.id == draggingID })
        else { return }

        let step = thumbSize + spacing
        let steps = Int((dragOffset / step).rounded())

        let targetIndex = max(0, min(items.count - 1, currentIndex + steps))
        if targetIndex != currentIndex {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.65, blendDuration: 0)) {
                items.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex)
            }
            dragOffset -= CGFloat(targetIndex - currentIndex) * step
        }
    }
}

#Preview {
    @Previewable @State var state: [PhotoItem] = ([UIColor.systemBlue, .systemGreen, .systemOrange, .systemPink] as [UIColor]).map { color in
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 100, height: 100)))
        }
        return PhotoItem(thumbnail: thumb, source: .camera(thumb))
    }
    @Previewable @State var selected: UUID?
    ReorderablePhotoStrip(items: $state, selectedPhotoID: $selected)
        .padding()
}

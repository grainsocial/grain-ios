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
                            .clipShape(RoundedRectangle(cornerRadius: 8))

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
                                .foregroundStyle(.white, Color("AccentColor"))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 9, y: -9)
                    }
                    .offset(x: draggingID == item.id ? dragOffset : 0)
                    .opacity(draggingID == item.id ? 0.8 : 1)
                    .scaleEffect(draggingID == item.id ? 1.08 : 1)
                    .zIndex(draggingID == item.id ? 1 : 0)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.25)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { value in
                                switch value {
                                case .second(true, let drag):
                                    if draggingID == nil {
                                        draggingID = item.id
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    draggingID = nil
                                    dragOffset = 0
                                }
                            }
                    )
                }
            }
            .padding(.vertical, 10)
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
            withAnimation(.easeInOut(duration: 0.15)) {
                items.move(
                    fromOffsets: IndexSet(integer: currentIndex),
                    toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex
                )
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

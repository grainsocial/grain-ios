import SwiftUI
import UIKit

// MARK: - UIKit horizontal scroll that works inside Form/List

private struct UIKitHScroll<Content: View>: UIViewRepresentable {
    let content: Content

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.alwaysBounceVertical = false

        let host = context.coordinator.host
        host.view.backgroundColor = .clear
        scroll.addSubview(host.view)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.host.rootView = content
        context.coordinator.host.view.sizeToFit()

        let size = context.coordinator.host.view.systemLayoutSizeFitting(
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: scroll.bounds.height),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .required
        )
        context.coordinator.host.view.frame = CGRect(origin: .zero, size: size)
        scroll.contentSize = size
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content)
    }

    @MainActor class Coordinator {
        let host: UIHostingController<Content>
        init(content: Content) {
            host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
        }
    }
}

// MARK: - Strip View

struct ReorderablePhotoStrip: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0
    private let thumbSize: CGFloat = 72
    private let spacing: CGFloat = 8

    var body: some View {
        UIKitHScroll(content: stripContent)
            .frame(height: thumbSize + 16)
    }

    private var stripContent: some View {
        HStack(spacing: spacing) {
            ForEach(items) { item in
                thumbnailCell(item: item)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .padding(.horizontal, 16)
    }

    private func thumbnailCell(item: PhotoItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: item.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: thumbSize, height: thumbSize)
                .reorderableThumbnail(
                    isDragging: draggingID == item.id,
                    isSelected: item.id == selectedPhotoID
                )

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
            .offset(x: 4, y: -4)
        }
        .zIndex(draggingID == item.id ? 1 : 0)
        .id(item.id)
        .offset(x: draggingID == item.id ? dragOffset : 0)
        .onTapGesture {
            guard draggingID == nil else { return }
            selectedPhotoID = item.id
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

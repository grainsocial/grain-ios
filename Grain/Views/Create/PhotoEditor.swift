import SwiftUI

struct PhotoEditor: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    let sendExif: Bool

    private var selectedIndex: Int? {
        guard let id = selectedPhotoID else { return nil }
        return items.firstIndex(where: { $0.id == id })
    }

    var body: some View {
        ReorderablePhotoStrip(items: $items, selectedPhotoID: $selectedPhotoID)
        if let idx = selectedIndex {
            viewer(selectedIndex: idx)
            altTextField(for: idx)
            exifRow(for: items[idx])
        }
        ReorderablePhotoGrid(items: $items, selectedPhotoID: $selectedPhotoID)
    }

    // MARK: - Zoomable Viewer

    private func viewer(selectedIndex _: Int) -> some View {
        TabView(selection: $selectedPhotoID) {
            ForEach(items) { item in
                LocalZoomableViewer(image: item.thumbnail)
                    .tag(Optional(item.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 280)
    }

    // MARK: - EXIF Row

    @ViewBuilder
    private func exifRow(for item: PhotoItem) -> some View {
        if let exif = item.exifSummary {
            VStack(alignment: .leading, spacing: 2) {
                if let camera = exif.camera {
                    Text(camera).font(.caption)
                }
                HStack {
                    Text([exif.shutterSpeed, exif.iso].compactMap(\.self).joined(separator: "  "))
                        .font(.caption)
                    Spacer()
                    Text([exif.focalLength, exif.aperture].compactMap(\.self).joined(separator: "  "))
                        .font(.caption)
                }
            }
            .foregroundStyle(sendExif ? .primary : .tertiary)
        }
    }

    // MARK: - Alt Text Field

    private func altTextField(for index: Int) -> some View {
        TextField("Describe this photo...", text: $items[index].alt, axis: .vertical)
            .font(.subheadline)
            .lineLimit(2 ... 4)
    }
}

import SwiftUI
import UIKit

struct CaptionsListPrototype: View {
    @State var items: [PhotoItem] = []
    var matchedNamespace: Namespace.ID?
    @State private var sendExif = true

    var body: some View {
        NavigationStack {
            List {
                Toggle("Send EXIF", isOn: $sendExif)
                    .listRowBackground(Color(.systemBackground))

                ForEach($items) { $item in
                    let exifState: ExifState = {
                        guard item.exifSummary != nil else { return .absent }
                        return sendExif ? .active : .inactive
                    }()

                    HStack(alignment: .top, spacing: 12) {
                        Image(uiImage: item.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipped()
                            .cornerRadius(8)
                            .modifier(MatchedPhotoModifier(id: item.id, namespace: matchedNamespace))

                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Add a description for accessibility", text: $item.alt, axis: .vertical)
                                .font(.subheadline)
                                .lineLimit(2 ... 4)

                            ExifChip(state: exifState)
                        }
                    }
                    .padding(.vertical, 10)
                    // Explicit row background prevents the drag ghost from going invisible.
                    .listRowBackground(Color(.systemBackground))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            if let index = items.firstIndex(where: { $0.id == item.id }) {
                                items.remove(at: index)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Captions")
            .navigationBarTitleDisplayMode(.inline)
        } // NavigationStack
    }
}

#Preview {
    let mockExif = ExifSummary(
        camera: "RICOH GR IIIx",
        lens: nil,
        exposure: nil,
        shutterSpeed: "1/250",
        iso: "400",
        focalLength: "40mm",
        aperture: "f/2.8"
    )
    var items = PreviewData.photoItems
    // Assign exif to every other item so both states are visible in the list.
    for i in stride(from: 0, to: items.count, by: 2) {
        items[i].exifSummary = mockExif
    }
    return CaptionsListPrototype(items: items)
        .grainPreview()
        .frame(maxHeight: .infinity, alignment: .top)
}

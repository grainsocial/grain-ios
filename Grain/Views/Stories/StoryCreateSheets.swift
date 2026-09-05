import SwiftUI

/// Half-sheet for picking a story's location from the review stage.
struct StoryLocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var resolvedLocation: (h3: String, name: String, address: [String: AnyCodable]?)?
    let photoLocationResult: NominatimResult?
    let onSelectLocation: (NominatimResult) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LocationPickerRows(
                        resolvedLocation: $resolvedLocation,
                        photoLocationResult: photoLocationResult,
                        onSelectLocation: { result in
                            onSelectLocation(result)
                            dismiss()
                        }
                    )
                }
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Half-sheet for choosing a story's self-applied content labels.
struct StoryContentLabelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLabels: Set<String>

    var body: some View {
        NavigationStack {
            Form {
                ContentLabelPicker(selectedLabels: $selectedLabels, initiallyExpanded: true)
            }
            .navigationTitle("Content warning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview("Location") {
    @Previewable @State var location: (h3: String, name: String, address: [String: AnyCodable]?)?
    Color.black
        .sheet(isPresented: .constant(true)) {
            StoryLocationSheet(resolvedLocation: $location, photoLocationResult: nil) { _ in }
        }
        .previewEnvironments()
        .grainPreview()
}

#Preview("Labels") {
    @Previewable @State var labels: Set = ["nudity"]
    Color.black
        .sheet(isPresented: .constant(true)) {
            StoryContentLabelSheet(selectedLabels: $labels)
        }
        .previewEnvironments()
        .grainPreview()
}

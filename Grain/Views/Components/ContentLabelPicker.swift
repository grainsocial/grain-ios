import SwiftUI

struct ContentLabelPicker: View {
    @Environment(LabelDefinitionsCache.self) private var labelDefs
    @Binding var selectedLabels: Set<String>

    private static let selfLabelValues = ["nudity", "sexual", "gore"]

    private var options: [(value: String, label: String)] {
        Self.selfLabelValues.map { value in
            let name = labelDefs.definitions
                .first(where: { $0.identifier == value })?
                .displayName ?? value.capitalized
            return (value: value, label: name)
        }
    }

    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(options, id: \.value) { option in
                    Button {
                        if selectedLabels.contains(option.value) {
                            selectedLabels.remove(option.value)
                        } else {
                            selectedLabels.insert(option.value)
                        }
                    } label: {
                        HStack {
                            Text(option.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedLabels.contains(option.value) {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            } label: {
                Text("Content Warning")
                    .foregroundStyle(.primary)
            }
        }
        .onChange(of: selectedLabels) {
            if !selectedLabels.isEmpty {
                isExpanded = true
            }
        }
    }
}

#Preview {
    // Pre-select "sexual" so the disclosure group auto-expands on first render
    // and the checkmark row is immediately visible. The cache has no network
    // definitions, so labels fall back to .capitalized ("Nudity", "Sexual", "Gore").
    @Previewable @State var labelsWithSelection: Set = ["sexual"]
    @Previewable @State var labelsEmpty: Set<String> = []

    Form {
        // Expanded — one item pre-checked
        Section(header: Text("Pre-selected (expanded)")) {
            ContentLabelPicker(selectedLabels: $labelsWithSelection)
        }

        // Collapsed — nothing selected
        Section(header: Text("Empty (collapsed)")) {
            ContentLabelPicker(selectedLabels: $labelsEmpty)
        }
    }
    .previewEnvironments()
    .preferredColorScheme(.dark)
    .tint(Color("AccentColor"))
}

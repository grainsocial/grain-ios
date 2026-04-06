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

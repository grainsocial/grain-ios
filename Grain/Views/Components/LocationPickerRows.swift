import SwiftUI

/// Reusable Form rows for location search and selection.
/// Renders a confirmed-location row when `resolvedLocation` is set,
/// or a photo suggestion + debounced search field + results list when it isn't.
struct LocationPickerRows: View {
    @Binding var resolvedLocation: (h3: String, name: String, address: [String: AnyCodable]?)?
    let photoLocationResult: NominatimResult?
    var photoLocationLabel: String = "Use photo location"
    let onSelectLocation: (NominatimResult) -> Void

    @State private var locationQuery = ""
    @State private var locationSuggestions: [NominatimResult] = []
    @State private var isSearchingLocation = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        if let loc = resolvedLocation {
            HStack {
                Label(loc.name, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Button {
                    resolvedLocation = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            if let photoLoc = photoLocationResult {
                Button { selectResult(photoLoc) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(photoLocationLabel)
                                .font(.subheadline)
                            Text(photoLoc.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search for a location...", text: $locationQuery)
                    .textInputAutocapitalization(.never)
                    .onChange(of: locationQuery) {
                        searchTask?.cancel()
                        let query = locationQuery
                        searchTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            await performSearch(query: query)
                        }
                    }
                if isSearchingLocation {
                    ProgressView().controlSize(.small)
                }
            }

            ForEach(locationSuggestions, id: \.placeId) { result in
                Button { selectResult(result) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        if let context = result.context {
                            Text(context)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func selectResult(_ result: NominatimResult) {
        onSelectLocation(result)
        locationQuery = ""
        locationSuggestions = []
    }

    private func performSearch(query: String) async {
        isSearchingLocation = true
        defer { isSearchingLocation = false }
        locationSuggestions = await LocationServices.searchLocation(query: query)
    }
}

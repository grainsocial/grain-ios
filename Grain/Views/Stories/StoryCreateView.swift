import AVFoundation
import PhotosUI
import SwiftUI

struct StoryCreateView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let client: XRPCClient
    var onCreated: (() -> Void)?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var previewImage: UIImage?
    @State private var showCamera = false
    @State private var resolvedLocation: (h3: String, name: String, address: [String: AnyCodable]?)?
    @State private var locationQuery = ""
    @State private var locationSuggestions: [NominatimResult] = []
    @State private var isSearchingLocation = false
    @State private var locationSearchTask: Task<Void, Never>?
    @State private var photoLocationResult: NominatimResult?
    @State private var includeLocation = true
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var postToBluesky = false
    @State private var selectedLabels: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                }

                Section("Location") {
                    if let loc = resolvedLocation {
                        HStack {
                            Label(loc.name, systemImage: "mappin.and.ellipse")
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                resolvedLocation = nil
                                locationQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        if let photoLoc = photoLocationResult {
                            Button { selectLocation(photoLoc) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "location.fill")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Use photo location")
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
                                    locationSearchTask?.cancel()
                                    let query = locationQuery
                                    locationSearchTask = Task {
                                        try? await Task.sleep(for: .milliseconds(300))
                                        guard !Task.isCancelled else { return }
                                        await searchLocation(query: query)
                                    }
                                }
                            if isSearchingLocation {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        ForEach(locationSuggestions, id: \.placeId) { result in
                            Button {
                                selectLocation(result)
                            } label: {
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

                ContentLabelPicker(selectedLabels: $selectedLabels)

                Section {
                    Toggle("Post to Bluesky", isOn: $postToBluesky)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .task {
                if let authContext = await auth.authContext(),
                   let prefs = try? await client.getPreferences(auth: authContext).preferences,
                   let location = prefs.includeLocation
                {
                    includeLocation = location
                }
            }
            .onChange(of: selectedPhoto) {
                Task { await loadPhoto() }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image, _ in
                    handleCameraImage(image)
                }
                .ignoresSafeArea()
            }
            .navigationTitle("New Story")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await createStory() }
                    } label: {
                        if isUploading {
                            ProgressView()
                        } else {
                            Text("Post")
                                .bold()
                        }
                    }
                    .disabled(previewImage == nil || isUploading)
                }
            }
        }
    }

    // MARK: - Camera

    private func handleCameraImage(_ image: UIImage) {
        previewImage = image
        if let data = image.jpegData(compressionQuality: 1.0) {
            photoData = data
        }
        selectedPhoto = nil
        resolvedLocation = nil
        locationQuery = ""
        locationSuggestions = []
        photoLocationResult = nil
    }

    // MARK: - Photo Loading

    private func loadPhoto() async {
        guard let item = selectedPhoto,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            photoData = nil
            previewImage = nil
            return
        }
        photoData = data
        previewImage = image

        resolvedLocation = nil
        locationQuery = ""
        locationSuggestions = []
        photoLocationResult = nil
        if let gps = ImageProcessing.extractGPS(from: data),
           let result = await LocationServices.reverseGeocode(latitude: gps.latitude, longitude: gps.longitude)
        {
            photoLocationResult = result
            if includeLocation {
                selectLocation(result)
            }
        }
    }

    // MARK: - Create

    private func createStory() async {
        guard let authContext = await auth.authContext(),
              let repo = auth.userDID,
              let previewImage else { return }

        isUploading = true
        errorMessage = nil

        do {
            let (resized, size) = ImageProcessing.resizeImage(previewImage, maxDimension: 2000, maxBytes: 900_000)
            let response = try await client.uploadBlob(data: resized, mimeType: "image/jpeg", auth: authContext)

            let blobDict: [String: AnyCodable] = [
                "$type": AnyCodable(response.blob.type ?? "blob"),
                "ref": AnyCodable(["$link": AnyCodable(response.blob.ref?.link ?? "")] as [String: AnyCodable]),
                "mimeType": AnyCodable(response.blob.mimeType ?? "image/jpeg"),
                "size": AnyCodable(response.blob.size ?? 0),
            ]

            var record: [String: AnyCodable] = [
                "media": AnyCodable(blobDict),
                "aspectRatio": AnyCodable([
                    "width": AnyCodable(Int(size.width)),
                    "height": AnyCodable(Int(size.height)),
                ] as [String: AnyCodable]),
                "createdAt": AnyCodable(DateFormatting.nowISO()),
            ]

            if let loc = resolvedLocation {
                record["location"] = AnyCodable([
                    "value": AnyCodable(loc.h3),
                    "name": AnyCodable(loc.name),
                ] as [String: AnyCodable])
                if let addr = loc.address {
                    record["address"] = AnyCodable(addr)
                }
            }
            if !selectedLabels.isEmpty {
                let labelValues = selectedLabels.map { ["val": AnyCodable($0)] as [String: AnyCodable] }
                record["labels"] = AnyCodable([
                    "$type": AnyCodable("com.atproto.label.defs#selfLabels"),
                    "values": AnyCodable(labelValues as [[String: AnyCodable]]),
                ] as [String: AnyCodable])
            }

            let storyResult = try await client.createRecord(
                collection: "social.grain.story",
                repo: repo,
                record: AnyCodable(record),
                auth: authContext
            )

            // Cross-post to Bluesky if toggled
            if postToBluesky, let storyUri = storyResult.uri {
                let rkey = storyUri.split(separator: "/").last.map(String.init) ?? ""
                let postURL = "https://grain.social/profile/\(repo)/story/\(rkey)"
                do {
                    let location: (name: String, address: [String: AnyCodable]?)? = resolvedLocation.map { ($0.name, $0.address) }
                    try await BlueskyPost.create(
                        options: BlueskyPostOptions(
                            url: postURL,
                            location: location,
                            description: nil as String?,
                            images: [(blob: response.blob, alt: "", width: Int(size.width), height: Int(size.height))]
                        ),
                        client: client,
                        repo: repo,
                        auth: authContext
                    )
                } catch {
                    // Don't fail the story creation if cross-post fails
                }
            }

            onCreated?()
            dismiss()
        } catch let XRPCError.httpError(statusCode, body) {
            let bodyStr = body.flatMap { String(data: $0, encoding: .utf8) } ?? "no body"
            errorMessage = "HTTP \(statusCode): \(bodyStr)"
        } catch {
            errorMessage = error.localizedDescription
        }
        isUploading = false
    }

    // MARK: - Location

    private func searchLocation(query: String) async {
        isSearchingLocation = true
        defer { isSearchingLocation = false }
        locationSuggestions = await LocationServices.searchLocation(query: query)
    }

    private func selectLocation(_ result: NominatimResult) {
        let h3 = LocationServices.latLonToH3(latitude: result.latitude, longitude: result.longitude)
        resolvedLocation = (h3: h3, name: result.name, address: result.address)
        locationQuery = ""
        locationSuggestions = []
    }
}

#Preview {
    StoryCreateView(client: XRPCClient(baseURL: AuthManager.serverURL))
        .environment(AuthManager())
}

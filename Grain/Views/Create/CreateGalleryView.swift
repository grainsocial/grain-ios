import PhotosUI
import SwiftUI

struct CreateGalleryView: View {
    @Environment(AuthManager.self) private var auth
    @State private var title = ""
    @State private var description = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoData: [(Data, String)] = [] // (data, mimeType)
    @State private var isUploading = false
    @State private var errorMessage: String?

    let client: XRPCClient

    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 20,
                        matching: .images
                    ) {
                        Label("Select Photos", systemImage: "photo.on.rectangle.angled")
                    }

                    if !selectedPhotos.isEmpty {
                        Text("\(selectedPhotos.count) photo(s) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Gallery")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await createGallery() }
                    } label: {
                        if isUploading {
                            ProgressView()
                        } else {
                            Text("Post")
                                .bold()
                        }
                    }
                    .disabled(title.isEmpty || selectedPhotos.isEmpty || isUploading)
                }
            }
        }
    }

    private func createGallery() async {
        guard let authContext = auth.authContext(), let repo = auth.userDID else { return }
        isUploading = true
        errorMessage = nil

        do {
            // 1. Load photo data from picker
            var uploadedBlobs: [(BlobRef, AspectRatio)] = []
            for item in selectedPhotos {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let mimeType = "image/jpeg"
                let response = try await client.uploadBlob(data: data, mimeType: mimeType, auth: authContext)
                // TODO: Extract actual aspect ratio from image data
                uploadedBlobs.append((response.blob, AspectRatio(width: 4, height: 3)))
            }

            // 2. Create photo records
            let now = ISO8601DateFormatter().string(from: Date())
            var photoUris: [String] = []
            for (blob, aspectRatio) in uploadedBlobs {
                let photoRecord: [String: AnyCodable] = [
                    "$type": AnyCodable("social.grain.photo"),
                    "photo": AnyCodable([
                        "$type": AnyCodable(blob.type ?? "blob"),
                        "ref": AnyCodable(["$link": AnyCodable(blob.ref?.link ?? "")]),
                        "mimeType": AnyCodable(blob.mimeType ?? "image/jpeg"),
                        "size": AnyCodable(blob.size ?? 0)
                    ] as [String: AnyCodable]),
                    "aspectRatio": AnyCodable(["width": AnyCodable(aspectRatio.width), "height": AnyCodable(aspectRatio.height)]),
                    "createdAt": AnyCodable(now)
                ]
                let result = try await client.createRecord(
                    collection: "social.grain.photo",
                    repo: repo,
                    record: AnyCodable(photoRecord),
                    auth: authContext
                )
                if let uri = result.uri { photoUris.append(uri) }
            }

            // 3. Create gallery record
            var galleryRecord: [String: AnyCodable] = [
                "$type": AnyCodable("social.grain.gallery"),
                "title": AnyCodable(title),
                "createdAt": AnyCodable(now)
            ]
            if !description.isEmpty { galleryRecord["description"] = AnyCodable(description) }
            let galleryResult = try await client.createRecord(
                collection: "social.grain.gallery",
                repo: repo,
                record: AnyCodable(galleryRecord),
                auth: authContext
            )

            // 4. Create gallery items linking photos to gallery
            if let galleryUri = galleryResult.uri {
                for (index, photoUri) in photoUris.enumerated() {
                    let itemRecord: [String: AnyCodable] = [
                        "$type": AnyCodable("social.grain.gallery.item"),
                        "gallery": AnyCodable(galleryUri),
                        "item": AnyCodable(photoUri),
                        "position": AnyCodable(index),
                        "createdAt": AnyCodable(now)
                    ]
                    _ = try await client.createRecord(
                        collection: "social.grain.gallery.item",
                        repo: repo,
                        record: AnyCodable(itemRecord),
                        auth: authContext
                    )
                }
            }

            // Reset form
            title = ""
            self.description = ""
            selectedPhotos = []
        } catch {
            errorMessage = error.localizedDescription
        }
        isUploading = false
    }
}

import ImageIO
import os
import PhotosUI
import SwiftUI

private let logger = Logger(subsystem: "social.grain.grain", category: "Create")

struct CreateGalleryView: View {
    @Environment(AuthManager.self) private var auth
    @State private var title = ""
    @State private var description = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoData: [(Data, String)] = [] // (data, mimeType)
    @Environment(\.dismiss) private var dismiss
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var resolvedLocation: (h3: String, name: String, address: [String: AnyCodable]?)?
    @State private var locationQuery = ""
    @State private var locationSuggestions: [NominatimResult] = []
    @State private var isSearchingLocation = false
    @State private var locationSearchTask: Task<Void, Never>?

    let client: XRPCClient
    var onCreated: (() -> Void)?

    private let maxTitle = 100
    private let maxDescription = 1000

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
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Add a title...", text: $title)
                        Text("\(title.count)/\(maxTitle)")
                            .font(.caption2)
                            .foregroundStyle(title.count > maxTitle ? .red : .secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Add a description. Supports @mentions, #hashtags, and links.", text: $description, axis: .vertical)
                            .lineLimit(3...6)
                        Text("\(description.count)/\(maxDescription)")
                            .font(.caption2)
                            .foregroundStyle(description.count > maxDescription ? .red : .secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
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

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .onChange(of: selectedPhotos) {
                Task { await detectLocation() }
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
                    .disabled(title.isEmpty || selectedPhotos.isEmpty || isUploading || title.count > maxTitle || description.count > maxDescription)
                }
            }
        }
    }

    private func detectLocation() async {
        resolvedLocation = nil
        locationQuery = ""
        locationSuggestions = []

        for item in selectedPhotos {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let gps = ImageProcessing.extractGPS(from: data) else { continue }

            if let result = await LocationServices.reverseGeocode(latitude: gps.latitude, longitude: gps.longitude) {
                selectLocation(result)
            }
            break
        }
    }

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

    private func createGallery() async {
        guard let authContext = auth.authContext(), let repo = auth.userDID else { return }
        isUploading = true
        errorMessage = nil

        do {
            // 1. Load, extract EXIF, resize, and upload photos
            struct ProcessedPhoto {
                let blob: BlobRef
                let aspectRatio: AspectRatio
                let exif: [String: AnyCodable]?
            }

            var processed: [ProcessedPhoto] = []
            for item in selectedPhotos {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let original = UIImage(data: data) else { continue }

                let exif = extractExif(from: data)
                let (resized, size) = ImageProcessing.resizeImage(original, maxDimension: 2000, maxBytes: 900_000)
                logger.warning("Uploading \(resized.count) bytes, \(Int(size.width))x\(Int(size.height))")
                let response = try await client.uploadBlob(data: resized, mimeType: "image/jpeg", auth: authContext)
                processed.append(ProcessedPhoto(
                    blob: response.blob,
                    aspectRatio: AspectRatio(width: Int(size.width), height: Int(size.height)),
                    exif: exif
                ))
            }

            // 2. Create photo records + EXIF records
            let now = ISO8601DateFormatter().string(from: Date())
            var photoUris: [String] = []
            for photo in processed {
                let blobDict: [String: AnyCodable] = [
                    "$type": AnyCodable(photo.blob.type ?? "blob"),
                    "ref": AnyCodable(["$link": AnyCodable(photo.blob.ref?.link ?? "")] as [String: AnyCodable]),
                    "mimeType": AnyCodable(photo.blob.mimeType ?? "image/jpeg"),
                    "size": AnyCodable(photo.blob.size ?? 0)
                ]
                let photoRecord: [String: AnyCodable] = [
                    "photo": AnyCodable(blobDict),
                    "aspectRatio": AnyCodable(["width": AnyCodable(photo.aspectRatio.width), "height": AnyCodable(photo.aspectRatio.height)] as [String: AnyCodable]),
                    "createdAt": AnyCodable(now)
                ]
                let result = try await client.createRecord(
                    collection: "social.grain.photo",
                    repo: repo,
                    record: AnyCodable(photoRecord),
                    auth: authContext
                )
                guard let uri = result.uri else { continue }
                photoUris.append(uri)

                // Create EXIF record if we extracted metadata
                if var exif = photo.exif {
                    exif["photo"] = AnyCodable(uri)
                    exif["createdAt"] = AnyCodable(now)
                    _ = try await client.createRecord(
                        collection: "social.grain.photo.exif",
                        repo: repo,
                        record: AnyCodable(exif),
                        auth: authContext
                    )
                }
            }

            // 3. Create gallery record with pre-resolved location
            var galleryRecord: [String: AnyCodable] = [
                "title": AnyCodable(title),
                "createdAt": AnyCodable(now)
            ]
            if !description.isEmpty { galleryRecord["description"] = AnyCodable(description) }
            if let loc = resolvedLocation {
                galleryRecord["location"] = AnyCodable([
                    "value": AnyCodable(loc.h3),
                    "name": AnyCodable(loc.name)
                ] as [String: AnyCodable])
                if let addr = loc.address {
                    galleryRecord["address"] = AnyCodable(addr)
                }
            }
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

            // Done — dismiss and refresh
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

    // MARK: - EXIF Extraction (gallery-specific, not shared)

    private func extractExif(from data: Data) -> [String: AnyCodable]? {
        let scale = 1_000_000

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            logger.warning("No image properties found")
            return nil
        }

        let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let exifAux = properties[kCGImagePropertyExifAuxDictionary as String] as? [String: Any]
        var result: [String: AnyCodable] = [:]

        if let make = tiffDict?[kCGImagePropertyTIFFMake as String] as? String {
            result["make"] = AnyCodable(make.trimmingCharacters(in: .whitespaces))
        }
        if let model = tiffDict?[kCGImagePropertyTIFFModel as String] as? String {
            result["model"] = AnyCodable(model.trimmingCharacters(in: .whitespaces))
        }
        if let lensMake = exifAux?["LensMake"] as? String ?? exifDict?["LensMake"] as? String ?? tiffDict?[kCGImagePropertyTIFFMake as String] as? String {
            result["lensMake"] = AnyCodable(lensMake.trimmingCharacters(in: .whitespaces))
        }
        if let lensModel = exifAux?["LensModel"] as? String ?? exifDict?[kCGImagePropertyExifLensModel as String] as? String {
            result["lensModel"] = AnyCodable(lensModel.trimmingCharacters(in: .whitespaces))
        }
        if let exposureTime = exifDict?[kCGImagePropertyExifExposureTime as String] as? Double {
            result["exposureTime"] = AnyCodable(Int(exposureTime * Double(scale)))
        }
        if let fNumber = exifDict?[kCGImagePropertyExifFNumber as String] as? Double {
            result["fNumber"] = AnyCodable(Int(fNumber * Double(scale)))
        }
        if let isoRaw = exifDict?[kCGImagePropertyExifISOSpeedRatings as String] as? [Any],
           let iso = (isoRaw.first as? NSNumber)?.intValue {
            result["iSO"] = AnyCodable(iso * scale)
        }
        if let focal35 = exifDict?[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Int {
            result["focalLengthIn35mmFormat"] = AnyCodable(focal35 * scale)
        } else if let focal35 = exifDict?[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Double {
            result["focalLengthIn35mmFormat"] = AnyCodable(Int(focal35) * scale)
        }
        if let flash = exifDict?[kCGImagePropertyExifFlash as String] as? Int {
            let flashStr: String
            switch flash {
            case 0: flashStr = "Off, Did not fire"
            case 1: flashStr = "On, Fired"
            case 5: flashStr = "On, Return not detected"
            case 7: flashStr = "On, Return detected"
            case 16: flashStr = "Off, Did not fire"
            case 24: flashStr = "Off, Auto"
            case 25: flashStr = "On, Auto"
            default: flashStr = "Unknown (\(flash))"
            }
            result["flash"] = AnyCodable(flashStr)
        }
        if let dateStr = exifDict?[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            if let date = formatter.date(from: dateStr) {
                result["dateTimeOriginal"] = AnyCodable(ISO8601DateFormatter().string(from: date))
            }
        }

        return result.isEmpty ? nil : result
    }
}

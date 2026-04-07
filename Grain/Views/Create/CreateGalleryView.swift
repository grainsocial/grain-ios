import AVFoundation
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
    @Environment(\.dismiss) private var dismiss
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var resolvedLocation: (h3: String, name: String, address: [String: AnyCodable]?)?
    @State private var locationQuery = ""
    @State private var locationSuggestions: [NominatimResult] = []
    @State private var isSearchingLocation = false
    @State private var locationSearchTask: Task<Void, Never>?
    @State private var showCamera = false
    @State private var photoItems: [PhotoItem] = []
    @State private var mentionState = MentionAutocompleteState()
    @State private var postToBluesky = false
    @State private var selectedLabels: Set<String> = []
    @State private var selectedPhotoID: UUID?
    @State private var photoLocationResult: NominatimResult?
    @State private var sendExif = true
    @State private var includeLocation = true
    @State private var imageZoomState = ImageZoomState()
    /// True while a photo is in the picked-up state inside PhotoEditor. Drives
    /// .scrollDisabled on the Form so the user's drag translation isn't eaten by
    /// the Form's pan recognizer. Gated on the picked-up state only — the 0.18s
    /// arming window before pickup still scrolls normally, so tapping on a cell
    /// feels instant.
    @State private var isReordering = false

    let client: XRPCClient
    var onCreated: (() -> Void)?

    private let maxTitle = 100
    private let maxDescription = 1000

    var body: some View {
        Form {
            photosSection
            gallerySection
            photoEditorSection
            cameraDataSection
            ContentLabelPicker(selectedLabels: $selectedLabels)
            Section {
                Toggle("Post to Bluesky", isOn: $postToBluesky)
            }
            errorSection
        }
        .scrollDisabled(isReordering)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            MentionSuggestionOverlay(state: mentionState) { suggestion in
                mentionState.complete(handle: suggestion.handle, in: &description)
            }
        }
        .onChange(of: selectedPhotos) {
            Task {
                await loadPickerPhotos()
                if let id = selectedPhotoID, !photoItems.contains(where: { $0.id == id }) {
                    selectedPhotoID = photoItems.first?.id
                } else if selectedPhotoID == nil {
                    selectedPhotoID = photoItems.first?.id
                }
                await detectLocation()
            }
        }
        // Re-derive the suggested location whenever the *first* photo changes
        // (reorder, removal, etc.) so "Use first photo location" stays accurate.
        .onChange(of: photoItems.first?.id) {
            Task { await detectLocation() }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image, metadata in
                let thumb = PhotoItem.makeThumbnail(from: image)
                let exif = metadata.flatMap { makeExifSummary(from: $0) }
                let item = PhotoItem(thumbnail: thumb, source: .camera(image, metadata: metadata), exifSummary: exif)
                photoItems.append(item)
                if selectedPhotoID == nil { selectedPhotoID = item.id }
            }
            .ignoresSafeArea()
        }
        .task {
            if let authContext = await auth.authContext(),
               let prefs = try? await client.getPreferences(auth: authContext).preferences
            {
                if let exif = prefs.includeExif { sendExif = exif }
                if let location = prefs.includeLocation { includeLocation = location }
            }
        }
        .navigationTitle("New Gallery")
        .navigationBarTitleDisplayMode(.inline)
        // Hiding the back button ALSO disables the interactive pop swipe. We
        // reuse the same isReordering flag that drives scroll lock so a
        // finger-near-the-left-edge drag during reorder doesn't accidentally
        // pop the view. The button reappears the instant the drag releases.
        .navigationBarBackButtonHidden(isReordering)
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
                .disabled(title.isEmpty || photoItems.isEmpty || isUploading || title.count > maxTitle || description.count > maxDescription)
            }
        }
        .environment(imageZoomState)
        .modifier(ImageZoomOverlay(zoomState: imageZoomState))
    }

    // MARK: - Form Sections

    private var photosSection: some View {
        Section("Photos") {
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 20,
                matching: .images
            ) {
                Label("Select Photos", systemImage: "photo.on.rectangle.angled")
            }

            Button {
                showCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera")
            }
        }
    }

    @ViewBuilder
    private var photoEditorSection: some View {
        if !photoItems.isEmpty {
            PhotoEditor(
                items: $photoItems,
                selectedPhotoID: $selectedPhotoID,
                isReordering: $isReordering,
                sendExif: sendExif
            )
        }
    }

    private var gallerySection: some View {
        Section("Gallery") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Add a title (required)...", text: $title)
                Text("\(title.count)/\(maxTitle)")
                    .font(.caption2)
                    .foregroundStyle(title.count > maxTitle ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Add a description. Supports @mentions, #hashtags, and links.", text: $description, axis: .vertical)
                    .lineLimit(3 ... 6)
                    .onChange(of: description) { mentionState.update(text: description) }
                Text("\(description.count)/\(maxDescription)")
                    .font(.caption2)
                    .foregroundStyle(description.count > maxDescription ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            locationRow

            if !photoItems.isEmpty {
                let filled = photoItems.count(where: { !$0.alt.trimmingCharacters(in: .whitespaces).isEmpty })
                HStack {
                    Label("Alt Text", systemImage: "text.below.photo")
                    Spacer()
                    Text("\(filled)/\(photoItems.count)")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var locationRow: some View {
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
                            Text("Use first photo location")
                                .font(.subheadline)
                            Text(photoLoc.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            locationSearchField
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

    private var locationSearchField: some View {
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
    }

    @ViewBuilder
    private var cameraDataSection: some View {
        if !photoItems.isEmpty {
            Section {
                Toggle("Include camera data", isOn: $sendExif)
            } footer: {
                Text("Camera make, model, lens, and exposure settings.")
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Photo Loading

    private func loadPickerPhotos() async {
        // Build set of picker item IDs currently in selectedPhotos
        let selectedIDs = Set(selectedPhotos.compactMap(\.itemIdentifier))

        // Remove picker items that are no longer in the selection
        photoItems.removeAll { item in
            guard case let .picker(pickerItem) = item.source else { return false }
            guard let id = pickerItem.itemIdentifier else { return true }
            return !selectedIDs.contains(id)
        }

        // Find which picker items are already represented
        let existingIDs = Set(photoItems.compactMap { item -> String? in
            guard case let .picker(pickerItem) = item.source else { return nil }
            return pickerItem.itemIdentifier
        })

        let newSelections = selectedPhotos.filter {
            !($0.itemIdentifier.map { existingIDs.contains($0) } ?? false)
        }
        guard !newSelections.isEmpty else { return }

        // Load all new items concurrently, preserving selection order
        var loaded: [(index: Int, item: PhotoItem)] = []
        await withTaskGroup(of: (Int, PhotoItem?).self) { group in
            for (index, pickerItem) in newSelections.enumerated() {
                group.addTask {
                    guard let data = try? await pickerItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return (index, nil) }
                    let thumb = PhotoItem.makeThumbnail(from: image)
                    let exif = makeExifSummary(from: data)
                    return (index, PhotoItem(thumbnail: thumb, source: .picker(pickerItem), exifSummary: exif))
                }
            }
            for await (index, item) in group {
                if let item { loaded.append((index, item)) }
            }
        }

        for (_, item) in loaded.sorted(by: { $0.index < $1.index }) {
            photoItems.append(item)
        }
    }

    private func detectLocation() async {
        // Always derive from the *currently first* photo so reordering re-runs detection.
        photoLocationResult = nil
        guard let first = photoItems.first else { return }

        var gps: (latitude: Double, longitude: Double)?
        switch first.source {
        case let .picker(pickerItem):
            if let data = try? await pickerItem.loadTransferable(type: Data.self) {
                gps = ImageProcessing.extractGPS(from: data)
            }
        case .camera:
            return
        }

        guard let gps else { return }

        if let result = await LocationServices.reverseGeocode(latitude: gps.latitude, longitude: gps.longitude) {
            photoLocationResult = result
            if includeLocation, resolvedLocation == nil {
                selectLocation(result)
            }
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

    // MARK: - Create Gallery

    private func createGallery() async {
        guard let authContext = await auth.authContext(), let repo = auth.userDID else { return }
        isUploading = true
        errorMessage = nil

        do {
            let altTexts = photoItems.map(\.alt)
            let processed = try await processGalleryPhotos(items: photoItems, client: client, authContext: authContext, skipExif: !sendExif)
            let now = DateFormatting.nowISO()
            let photoUris = try await createGalleryPhotoRecords(
                processed: processed,
                altTexts: altTexts,
                now: now,
                repo: repo,
                client: client,
                authContext: authContext,
                includeExif: sendExif
            )

            // 3. Create gallery record with pre-resolved location
            var galleryRecord: [String: AnyCodable] = [
                "title": AnyCodable(title),
                "createdAt": AnyCodable(now),
            ]
            if !description.isEmpty { galleryRecord["description"] = AnyCodable(description) }
            if !selectedLabels.isEmpty {
                let labelValues = selectedLabels.map { ["val": AnyCodable($0)] as [String: AnyCodable] }
                galleryRecord["labels"] = AnyCodable([
                    "$type": AnyCodable("com.atproto.label.defs#selfLabels"),
                    "values": AnyCodable(labelValues as [[String: AnyCodable]]),
                ] as [String: AnyCodable])
            }
            if let loc = resolvedLocation {
                galleryRecord["location"] = AnyCodable([
                    "value": AnyCodable(loc.h3),
                    "name": AnyCodable(loc.name),
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
                        "createdAt": AnyCodable(now),
                    ]
                    _ = try await client.createRecord(
                        collection: "social.grain.gallery.item",
                        repo: repo,
                        record: AnyCodable(itemRecord),
                        auth: authContext
                    )
                }
            }

            // Cross-post to Bluesky if toggled
            if postToBluesky, let galleryUri = galleryResult.uri {
                let rkey = galleryUri.split(separator: "/").last.map(String.init) ?? ""
                let postURL = "https://grain.social/profile/\(repo)/gallery/\(rkey)"
                let bskyImages = zip(processed, altTexts).map { photo, alt in
                    (blob: photo.blob, alt: alt, width: photo.aspectRatio.width, height: photo.aspectRatio.height)
                }
                do {
                    try await BlueskyPost.create(
                        options: BlueskyPostOptions(
                            url: postURL,
                            location: resolvedLocation.map { ($0.name, $0.address) },
                            description: description.isEmpty ? nil : description,
                            images: bskyImages
                        ),
                        client: client,
                        repo: repo,
                        auth: authContext
                    )
                } catch {
                    logger.error("Bluesky cross-post failed: \(error)")
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
}

// MARK: - Photo Item Model

struct ExifSummary {
    var camera: String?
    var lens: String?
    var exposure: String?
    var shutterSpeed: String?
    var iso: String?
    var focalLength: String?
    var aperture: String?
}

struct PhotoItem: Identifiable {
    let id = UUID()
    let thumbnail: UIImage
    let source: PhotoSource
    var alt: String = ""
    var exifSummary: ExifSummary?

    static func makeThumbnail(from image: UIImage, maxSize: CGFloat = 150) -> UIImage {
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

enum PhotoSource: @unchecked Sendable {
    case picker(PhotosPickerItem)
    case camera(UIImage, metadata: [String: Any]?)
}

// MARK: - Gallery Upload Helpers

private struct ProcessedPhoto {
    let blob: BlobRef
    let aspectRatio: AspectRatio
    let exif: [String: AnyCodable]?
}

private func processGalleryPhotos(
    items: [PhotoItem],
    client: XRPCClient,
    authContext: AuthContext,
    skipExif: Bool = false
) async throws -> [ProcessedPhoto] {
    var processed: [ProcessedPhoto] = []
    for item in items {
        switch item.source {
        case let .picker(pickerItem):
            guard let data = try await pickerItem.loadTransferable(type: Data.self),
                  let original = UIImage(data: data) else { continue }
            let exif = skipExif ? nil : extractGalleryExif(from: data)
            let (resized, size) = ImageProcessing.resizeImage(original, maxDimension: 2000, maxBytes: 900_000)
            logger.info("Uploading \(resized.count) bytes, \(Int(size.width))x\(Int(size.height))")
            let response = try await client.uploadBlob(data: resized, mimeType: "image/jpeg", auth: authContext)
            processed.append(ProcessedPhoto(
                blob: response.blob,
                aspectRatio: AspectRatio(width: Int(size.width), height: Int(size.height)),
                exif: exif
            ))

        case let .camera(image, metadata):
            let exif = skipExif ? nil : extractExifFromMetadata(metadata)
            let (resized, size) = ImageProcessing.resizeImage(image, maxDimension: 2000, maxBytes: 900_000)
            let response = try await client.uploadBlob(data: resized, mimeType: "image/jpeg", auth: authContext)
            processed.append(ProcessedPhoto(
                blob: response.blob,
                aspectRatio: AspectRatio(width: Int(size.width), height: Int(size.height)),
                exif: exif
            ))
        }
    }
    return processed
}

private func createGalleryPhotoRecords(
    processed: [ProcessedPhoto],
    altTexts: [String],
    now: String,
    repo: String,
    client: XRPCClient,
    authContext: AuthContext,
    includeExif: Bool
) async throws -> [String] {
    var photoUris: [String] = []
    for (index, photo) in processed.enumerated() {
        let blobDict: [String: AnyCodable] = [
            "$type": AnyCodable(photo.blob.type ?? "blob"),
            "ref": AnyCodable(["$link": AnyCodable(photo.blob.ref?.link ?? "")] as [String: AnyCodable]),
            "mimeType": AnyCodable(photo.blob.mimeType ?? "image/jpeg"),
            "size": AnyCodable(photo.blob.size ?? 0),
        ]
        var photoRecord: [String: AnyCodable] = [
            "photo": AnyCodable(blobDict),
            "aspectRatio": AnyCodable(["width": AnyCodable(photo.aspectRatio.width), "height": AnyCodable(photo.aspectRatio.height)] as [String: AnyCodable]),
            "createdAt": AnyCodable(now),
        ]
        let alt = altTexts[index].trimmingCharacters(in: .whitespacesAndNewlines)
        if !alt.isEmpty {
            photoRecord["alt"] = AnyCodable(alt)
        }
        let result = try await client.createRecord(
            collection: "social.grain.photo",
            repo: repo,
            record: AnyCodable(photoRecord),
            auth: authContext
        )
        guard let uri = result.uri else { continue }
        photoUris.append(uri)

        if includeExif, var exif = photo.exif {
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
    return photoUris
}

// MARK: - EXIF Extraction (gallery-specific, not shared)

private func flashDescription(for flash: Int) -> String {
    switch flash {
    case 0: "Off, Did not fire"
    case 1: "On, Fired"
    case 5: "On, Return not detected"
    case 7: "On, Return detected"
    case 16: "Off, Did not fire"
    case 24: "Off, Auto"
    case 25: "On, Auto"
    default: "Unknown (\(flash))"
    }
}

private func extractCameraInfo(
    exifDict: [String: Any]?,
    tiffDict: [String: Any]?,
    exifAux: [String: Any]?,
    into result: inout [String: AnyCodable]
) {
    if let make = tiffDict?[kCGImagePropertyTIFFMake as String] as? String {
        result["make"] = AnyCodable(make.trimmingCharacters(in: .whitespaces))
    }
    if let model = tiffDict?[kCGImagePropertyTIFFModel as String] as? String {
        result["model"] = AnyCodable(model.trimmingCharacters(in: .whitespaces))
    }
    let lensMake = exifAux?["LensMake"] as? String
        ?? exifDict?["LensMake"] as? String
        ?? tiffDict?[kCGImagePropertyTIFFMake as String] as? String
    if let lensMake {
        result["lensMake"] = AnyCodable(lensMake.trimmingCharacters(in: .whitespaces))
    }
    let lensModel = exifAux?["LensModel"] as? String
        ?? exifDict?[kCGImagePropertyExifLensModel as String] as? String
    if let lensModel {
        result["lensModel"] = AnyCodable(lensModel.trimmingCharacters(in: .whitespaces))
    }
}

private func extractExposureInfo(
    exifDict: [String: Any]?,
    scale: Int,
    into result: inout [String: AnyCodable]
) {
    if let exposureTime = exifDict?[kCGImagePropertyExifExposureTime as String] as? Double {
        result["exposureTime"] = AnyCodable(Int(exposureTime * Double(scale)))
    }
    if let fNumber = exifDict?[kCGImagePropertyExifFNumber as String] as? Double {
        result["fNumber"] = AnyCodable(Int(fNumber * Double(scale)))
    }
    if let isoRaw = exifDict?[kCGImagePropertyExifISOSpeedRatings as String] as? [Any],
       let iso = (isoRaw.first as? NSNumber)?.intValue
    {
        result["iSO"] = AnyCodable(iso * scale)
    }
    if let focal35 = exifDict?[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Int {
        result["focalLengthIn35mmFormat"] = AnyCodable(focal35 * scale)
    } else if let focal35 = exifDict?[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Double {
        result["focalLengthIn35mmFormat"] = AnyCodable(Int(focal35) * scale)
    }
    if let flash = exifDict?[kCGImagePropertyExifFlash as String] as? Int {
        result["flash"] = AnyCodable(flashDescription(for: flash))
    }
    if let dateStr = exifDict?[kCGImagePropertyExifDateTimeOriginal as String] as? String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let date = formatter.date(from: dateStr) {
            result["dateTimeOriginal"] = AnyCodable(ISO8601DateFormatter().string(from: date))
        }
    }
}

private func makeExifSummary(from metadata: [String: Any]) -> ExifSummary? {
    let exifDict = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let tiffDict = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
    let exifAux = metadata[kCGImagePropertyExifAuxDictionary as String] as? [String: Any]
    return buildExifSummary(exifDict: exifDict, tiffDict: tiffDict, exifAux: exifAux)
}

private func makeExifSummary(from data: Data) -> ExifSummary? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    else { return nil }
    return makeExifSummary(from: properties)
}

private func buildExifSummary(exifDict: [String: Any]?, tiffDict: [String: Any]?, exifAux: [String: Any]?) -> ExifSummary? {
    var summary = ExifSummary()

    let make = (tiffDict?[kCGImagePropertyTIFFMake as String] as? String)?.trimmingCharacters(in: .whitespaces)
    let model = (tiffDict?[kCGImagePropertyTIFFModel as String] as? String)?.trimmingCharacters(in: .whitespaces)
    if let model {
        summary.camera = (make.map { model.lowercased().hasPrefix($0.lowercased()) } == true) ? model : [make, model].compactMap(\.self).joined(separator: " ")
    }

    let lens = (exifAux?["LensModel"] as? String ?? exifDict?[kCGImagePropertyExifLensModel as String] as? String)?.trimmingCharacters(in: .whitespaces)
    summary.lens = lens

    if let et = exifDict?[kCGImagePropertyExifExposureTime as String] as? Double {
        summary.shutterSpeed = et < 1 ? "1/\(Int((1 / et).rounded()))s" : "\(et)s"
    }
    if let fn = exifDict?[kCGImagePropertyExifFNumber as String] as? Double {
        summary.aperture = formatAperture(fn)
    }
    if let isoRaw = exifDict?[kCGImagePropertyExifISOSpeedRatings as String] as? [Any],
       let iso = (isoRaw.first as? NSNumber)?.intValue
    {
        summary.iso = "ISO \(iso)"
    }
    if let focal = exifDict?[kCGImagePropertyExifFocalLenIn35mmFilm as String] {
        let mm = (focal as? Int) ?? Int((focal as? Double) ?? 0)
        if mm > 0 { summary.focalLength = "\(mm)mm" }
    }
    let parts = [summary.shutterSpeed, summary.iso, summary.focalLength, summary.aperture].compactMap(\.self)
    if !parts.isEmpty { summary.exposure = parts.joined(separator: "  ") }

    guard summary.camera != nil || summary.lens != nil || summary.exposure != nil else { return nil }
    return summary
}

private func extractExifFromMetadata(_ metadata: [String: Any]?) -> [String: AnyCodable]? {
    guard let metadata else { return nil }
    let exifDict = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let tiffDict = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
    let exifAux = metadata[kCGImagePropertyExifAuxDictionary as String] as? [String: Any]
    var result: [String: AnyCodable] = [:]
    extractCameraInfo(exifDict: exifDict, tiffDict: tiffDict, exifAux: exifAux, into: &result)
    extractExposureInfo(exifDict: exifDict, scale: 1_000_000, into: &result)
    return result.isEmpty ? nil : result
}

private func extractGalleryExif(from data: Data) -> [String: AnyCodable]? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    else {
        logger.warning("No image properties found")
        return nil
    }

    let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
    let exifAux = properties[kCGImagePropertyExifAuxDictionary as String] as? [String: Any]
    var result: [String: AnyCodable] = [:]

    extractCameraInfo(exifDict: exifDict, tiffDict: tiffDict, exifAux: exifAux, into: &result)
    extractExposureInfo(exifDict: exifDict, scale: 1_000_000, into: &result)

    return result.isEmpty ? nil : result
}

#Preview {
    @Previewable @State var photos = PreviewData.photoItems
    @Previewable @State var selectedID: UUID?
    NavigationStack {
        CreateGalleryViewPreview(photoItems: $photos, selectedPhotoID: $selectedID)
    }
    .environment(AuthManager())
    .environment(LabelDefinitionsCache())
    .onAppear { selectedID = photos.first?.id }
}

/// Thin wrapper that exposes photoItems for preview injection
private struct CreateGalleryViewPreview: View {
    @Binding var photoItems: [PhotoItem]
    @Binding var selectedPhotoID: UUID?

    var body: some View {
        Form {
            Section("Photos") {
                Label("5 photos selected", systemImage: "photo.on.rectangle.angled")
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("Add a title (required)...", text: .constant("Golden Hour, Kyoto"))
                TextField("Add a description...", text: .constant("Shot on Leica M6 with Kodak Portra 400. #analog #japan #35mm"), axis: .vertical)
                    .lineLimit(3 ... 6)
            } header: {
                Text("Gallery")
            }
            Section {
                PhotoEditor(
                    items: $photoItems,
                    selectedPhotoID: $selectedPhotoID,
                    isReordering: .constant(false),
                    sendExif: true
                )
            }
        }
        .navigationTitle("New Gallery")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") {} }
            ToolbarItem(placement: .topBarTrailing) { Button("Post") {}.bold() }
        }
    }
}

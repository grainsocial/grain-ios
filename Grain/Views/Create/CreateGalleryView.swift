import AVFoundation
import ImageIO
import os
import PhotosUI
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "social.grain.grain", category: "Create")
private let createSignposter = OSSignposter(subsystem: "social.grain.grain", category: "PhotoLoading.TaskGroup")

/// Limits concurrent photo-load tasks to avoid overwhelming the Swift cooperative thread pool.
private actor LoadThrottle {
    private let maxConcurrent: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    func acquire(spid: OSSignpostID) async {
        if active < maxConcurrent {
            active += 1
            let a = active
            createSignposter.emitEvent("ThrottleAcquired", id: spid, "active=\(a),waiters=0")
        } else {
            let a = active, w = waiters.count
            let waitState = createSignposter.beginInterval("ThrottleWait", id: spid, "active=\(a),waiters=\(w)")
            await withCheckedContinuation { self.waiters.append($0) }
            let a2 = active
            createSignposter.endInterval("ThrottleWait", waitState, "active=\(a2)")
        }
    }

    func release(spid: OSSignpostID) {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
            let a = active, w = waiters.count
            createSignposter.emitEvent("ThrottleHandoff", id: spid, "active=\(a),waiters=\(w)")
        } else {
            active -= 1
            let a = active
            createSignposter.emitEvent("ThrottleReleased", id: spid, "active=\(a)")
        }
    }
}

struct CreateGalleryView: View {
    @Environment(AuthManager.self) private var auth
    @State private var title = ""
    @State private var description = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @Environment(\.dismiss) private var dismiss
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var resolvedLocation: (h3: String, name: String, address: [String: AnyCodable]?)?
    @State private var showCamera = false
    @State private var photoItems: [PhotoItem] = []
    @State private var mentionState = MentionAutocompleteState()
    @State private var postToBluesky = false
    @State private var selectedLabels: Set<String> = []
    @State private var selectedPhotoID: UUID?
    @State private var photoLoadTask: Task<Void, Never>?
    /// Picker item identifiers that the user removed via the editor's X button.
    /// loadPickerPhotos skips these so deleted photos don't reappear.
    /// Cleared when the user explicitly re-selects items in the picker.
    @State private var editorRemovedIDs: Set<String> = []
    @State private var lastPickerCount = 0
    @State private var photoLocationResult: NominatimResult?
    @State private var sendExif = true
    @State private var includeLocation = true
    @State private var imageZoomState = ImageZoomState()
    /// True from the moment a cell is touched (arming window) through the end of
    /// the drag. Drives .scrollDisabled on the Form so neither the pre-fire hold
    /// nor the drag itself lets the Form scroll underneath the reorder gesture.
    @State private var isReordering = false
    /// True for the duration of a strip↔grid↔captions mode morph inside
    /// GalleryEditor. Drives `.scrollDisabled` alongside `isReordering` so
    /// UIKit's UICollectionView doesn't adjust scroll offset mid-morph —
    /// that adjustment shifts matched-geometry source/destination frames
    /// into different scroll contexts, producing wrong-direction morphs.
    @State private var isAnimatingMode = false
    @State private var editorMode: EditorMode = .preview
    @State private var showDiscardAlert = false

    let client: XRPCClient
    var onCreated: (() -> Void)?

    private let maxTitle = 100
    private let maxDescription = 1000

    private var hasChanges: Bool {
        !photoItems.isEmpty || !title.isEmpty || !description.isEmpty ||
            resolvedLocation != nil || !selectedLabels.isEmpty
    }

    var body: some View {
        // The Form is wrapped in an outer ZStack so `ImageZoomOverlay` attaches at
        // the ZStack level rather than to the Form directly. Applied to the Form,
        // its `.overlay { ... }` content lives inside the Form's own clipping
        // context (Form is a UICollectionView under the hood) which can leave the
        // zoomed image visually beneath sibling chrome on some transitions. Mounting
        // the overlay one level above guarantees it composites on top of every-
        // thing, mirroring how FeedView nests its zoom overlay above ScrollView.
        ZStack {
            Form {
                photosSection
                gallerySection
                photoEditorSection
                postPreviewSection
                cameraDataSection
                ContentLabelPicker(selectedLabels: $selectedLabels)
                Section {
                    Toggle("Post to Bluesky", isOn: $postToBluesky)
                } footer: {
                    Text("Includes title, description, location, and the first 4 photos.")
                }
                errorSection
            }
            // Lock the Form's vertical scroll while the zoom overlay is up so a
            // pinch that drifts vertically can't scroll the page underneath the
            // overlay. Also stays locked during reorder, same as before.
            .scrollDisabled(isReordering || isAnimatingMode || imageZoomState.showOverlay)
            .scrollDismissesKeyboard(.interactively)
            .background(SheetGestureDisabler(isDisabled: isReordering))
        }
        .interactiveDismissDisabled(isReordering)
        .safeAreaInset(edge: .bottom) {
            MentionSuggestionOverlay(state: mentionState) { suggestion in
                mentionState.complete(handle: suggestion.handle, in: &description)
            }
        }
        .onChange(of: selectedPhotos) {
            // If the user added items in the picker, clear any editor-removed
            // IDs that they re-selected so those photos load again.
            if selectedPhotos.count > lastPickerCount {
                let currentIDs = Set(selectedPhotos.compactMap(\.itemIdentifier))
                editorRemovedIDs.subtract(currentIDs)
            }
            lastPickerCount = selectedPhotos.count

            createSignposter.emitEvent("TaskSpawned", "source=selectedPhotos,count=\(selectedPhotos.count)")
            photoLoadTask?.cancel()
            photoLoadTask = Task {
                await loadPickerPhotos()
                guard !Task.isCancelled else { return }
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
            createSignposter.emitEvent("TaskSpawned", "source=firstPhotoChange,itemCount=\(photoItems.count)")
            Task { await detectLocation() }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image, metadata in
                let thumb = PhotoItem.makeThumbnail(from: image)
                let carousel = PhotoItem.makeCarouselPreview(from: image, width: UIScreen.main.bounds.width)
                let exif = metadata.flatMap { makeExifSummary(from: $0) }
                let item = PhotoItem(thumbnail: thumb, carouselPreview: carousel, source: .camera(image, metadata: metadata), exifSummary: exif)
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if hasChanges {
                        showDiscardAlert = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(hasChanges ? Color.accentColor : .primary)
                }
            }
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
                .buttonStyle(.glassProminent)
                .disabled(title.isEmpty || photoItems.isEmpty || isUploading || title.count > maxTitle || description.count > maxDescription)
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .alert("Discard gallery?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
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
                selectionBehavior: .continuousAndOrdered,
                matching: .images,
                photoLibrary: .shared()
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
            GalleryEditor(
                items: $photoItems,
                selectedPhotoID: $selectedPhotoID,
                isReordering: $isReordering,
                isAnimatingMode: $isAnimatingMode,
                mode: $editorMode,
                sendExif: sendExif,
                onDeleteItem: { item in
                    guard case let .picker(pickerItem) = item.source,
                          let id = pickerItem.itemIdentifier else { return }
                    editorRemovedIDs.insert(id)
                    selectedPhotos.removeAll { $0.itemIdentifier == id }
                }
            )
        }
    }

    @ViewBuilder
    private var postPreviewSection: some View {
        if editorMode == .preview, !photoItems.isEmpty {
            Section {
                PhotoCarouselView(
                    items: photoItems,
                    selectedPhotoID: $selectedPhotoID,
                    sendExif: sendExif
                )
                .id(photoItems.count)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.black)
            } header: {
                Text("Preview")
            }
            .transition(.opacity)
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

    private var locationRow: some View {
        LocationPickerRows(
            resolvedLocation: $resolvedLocation,
            photoLocationResult: photoLocationResult,
            photoLocationLabel: "Use first photo location",
            onSelectLocation: selectLocation
        )
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
            let isExisting = $0.itemIdentifier.map { existingIDs.contains($0) } ?? false
            let isRemoved = $0.itemIdentifier.map { editorRemovedIDs.contains($0) } ?? false
            return !isExisting && !isRemoved
        }
        guard !newSelections.isEmpty else { return }

        // Load all new items concurrently, preserving selection order.
        // Capture screen width here (main actor) before task bodies run on
        // background threads where UIScreen.main is unavailable.
        let batchState = createSignposter.beginInterval("LoadPickerBatch", id: createSignposter.makeSignpostID(), "count=\(newSelections.count)")
        let carouselWidth = UIScreen.main.bounds.width
        var loaded: [(index: Int, item: PhotoItem)] = []
        let throttle = LoadThrottle(maxConcurrent: 8)
        await withTaskGroup(of: (Int, PhotoItem?).self) { group in
            for (index, pickerItem) in newSelections.enumerated() {
                let spid = createSignposter.makeSignpostID()
                group.addTask {
                    await throttle.acquire(spid: spid)
                    defer { Task { await throttle.release(spid: spid) } }
                    let state = createSignposter.beginInterval("LoadPhoto", id: spid, "index=\(index)")
                    guard let data = try? await pickerItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data)
                    else {
                        createSignposter.endInterval("LoadPhoto", state, "result=nil")
                        return (index, nil)
                    }
                    let thumb = PhotoItem.makeThumbnail(from: image)
                    let carousel = PhotoItem.makeCarouselPreview(from: image, width: carouselWidth)
                    let exif = makeExifSummary(from: data)
                    createSignposter.endInterval("LoadPhoto", state, "result=ok")
                    return (index, PhotoItem(thumbnail: thumb, carouselPreview: carousel, source: .picker(pickerItem), exifSummary: exif))
                }
            }
            for await (index, item) in group {
                if let item { loaded.append((index, item)) }
            }
        }
        createSignposter.endInterval("LoadPickerBatch", batchState, "loaded=\(loaded.count)")

        // Dedup: with .continuousAndOrdered the picker fires onChange per-item,
        // so a previous load may have already added some of these.
        let alreadyLoaded = Set(photoItems.compactMap { item -> String? in
            guard case let .picker(p) = item.source else { return nil }
            return p.itemIdentifier
        })
        let deduped = loaded.sorted(by: { $0.index < $1.index }).map(\.item).filter { item in
            guard case let .picker(p) = item.source else { return true }
            return !(p.itemIdentifier.map { alreadyLoaded.contains($0) } ?? false)
        }
        photoItems += deduped
    }

    private func detectLocation() async {
        // Always derive from the *currently first* photo so reordering re-runs detection.
        photoLocationResult = nil
        guard let first = photoItems.first else { return }

        let state = createSignposter.beginInterval("DetectLocation", id: createSignposter.makeSignpostID())
        var gps: (latitude: Double, longitude: Double)?
        switch first.source {
        case let .picker(pickerItem):
            if let data = try? await pickerItem.loadTransferable(type: Data.self) {
                gps = ImageProcessing.extractGPS(from: data)
            }
        case .camera:
            createSignposter.endInterval("DetectLocation", state, "source=camera,skipped")
            return
        }

        guard let gps else {
            createSignposter.endInterval("DetectLocation", state, "result=noGPS")
            return
        }

        if let result = await LocationServices.reverseGeocode(latitude: gps.latitude, longitude: gps.longitude) {
            photoLocationResult = result
            if includeLocation, resolvedLocation == nil {
                selectLocation(result)
            }
        }
        createSignposter.endInterval("DetectLocation", state, "result=ok")
    }

    private func selectLocation(_ result: NominatimResult) {
        let h3 = LocationServices.latLonToH3(latitude: result.latitude, longitude: result.longitude)
        resolvedLocation = (h3: h3, name: result.name, address: result.address)
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
                            title: title.isEmpty ? nil : title,
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
    /// Screen-width image for the carousel. Built at creation time via
    /// `UIGraphicsImageRenderer`, which forces a full decode during the draw
    /// call — so the resulting UIImage is backed by a decoded bitmap and
    /// displays with zero decode work. Kept in memory for the editor session
    /// so the carousel never stalls on first draw regardless of scroll speed.
    let carouselPreview: UIImage
    let source: PhotoSource
    var alt: String = ""
    var exifSummary: ExifSummary?

    /// Thumbnail's natural width-to-height ratio. Computed once from `thumbnail.size`
    /// and used everywhere a cell needs aspect geometry — single source of truth.
    var naturalAspect: CGFloat {
        let h = thumbnail.size.height
        guard h > 0 else { return 1 }
        return thumbnail.size.width / h
    }

    static func makeThumbnail(from image: UIImage, maxSize: CGFloat = 150) -> UIImage {
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Downscale `image` so its width matches `width` (default: screen width),
    /// preserving aspect ratio. The renderer applies UIScreen.main.scale so
    /// the output is pixel-perfect at 1× zoom in the carousel without
    /// upscaling on any standard iPhone.
    static func makeCarouselPreview(from image: UIImage, width: CGFloat) -> UIImage {
        let scale = min(width / image.size.width, 1)
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
    .previewEnvironments()
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
                GalleryEditor(
                    items: $photoItems,
                    selectedPhotoID: $selectedPhotoID,
                    isReordering: .constant(false),
                    isAnimatingMode: .constant(false),
                    mode: .constant(.preview),
                    sendExif: true
                )
            }
        }
        .navigationTitle("New Gallery")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") {} }
            ToolbarItem(placement: .topBarTrailing) { Button("Post") {}.bold() }
        }
        .grainPreview()
    }
}

// MARK: - Sheet gesture disabler

/// Disables the `UISheetPresentationController`'s pan gesture while active so
/// the card cannot move at all — `interactiveDismissDisabled` only prevents
/// the dismiss *completion*, not the downward *motion*. Used during photo
/// reorder so the sheet stays perfectly still while a photo is picked up.
private struct SheetGestureDisabler: UIViewRepresentable {
    let isDisabled: Bool

    func makeUIView(context _: Context) -> UIView {
        UIView()
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        // Capture before hopping to async so we get the value at call time.
        let disabled = isDisabled
        DispatchQueue.main.async {
            // Walk the responder chain from our UIView up to the first
            // UIViewController whose presentationController is the sheet.
            var responder: UIResponder? = uiView
            while let r = responder {
                if let vc = r as? UIViewController,
                   vc.presentationController is UISheetPresentationController,
                   let presentedView = vc.presentationController?.presentedView
                {
                    for gesture in presentedView.gestureRecognizers ?? [] where gesture is UIPanGestureRecognizer {
                        gesture.isEnabled = !disabled
                    }
                    return
                }
                responder = r.next
            }
        }
    }
}

import AVFoundation
import ImageIO
import os
import PhotosUI
import SwiftUI
import UIKit

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
            let activeCount = active
            createSignposter.emitEvent("ThrottleAcquired", id: spid, "active=\(activeCount),waiters=0")
        } else {
            let activeCount = active, waiterCount = waiters.count
            let waitState = createSignposter.beginInterval("ThrottleWait", id: spid, "active=\(activeCount),waiters=\(waiterCount)")
            await withCheckedContinuation { self.waiters.append($0) }
            let activeAfterWait = active
            createSignposter.endInterval("ThrottleWait", waitState, "active=\(activeAfterWait)")
        }
    }

    func release(spid: OSSignpostID) {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
            let activeCount = active, waiterCount = waiters.count
            createSignposter.emitEvent("ThrottleHandoff", id: spid, "active=\(activeCount),waiters=\(waiterCount)")
        } else {
            active -= 1
            let activeCount = active
            createSignposter.emitEvent("ThrottleReleased", id: spid, "active=\(activeCount)")
        }
    }
}

struct CreateGalleryView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(GalleryUploadCenter.self) private var uploadCenter
    @State private var title = ""
    @State private var description = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @Environment(\.dismiss) private var dismiss
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
    /// Set when this sheet's Post button is tapped, cleared once the gallery is
    /// live or the user chooses to finish it later.
    @State private var isSubmitting = false

    let client: XRPCClient
    var onCreated: (() -> Void)?

    private let maxTitle = 100
    private let maxDescription = 1000

    private var hasChanges: Bool {
        !photoItems.isEmpty || !title.isEmpty || !description.isEmpty ||
            resolvedLocation != nil || !selectedLabels.isEmpty
    }

    /// True from the tap on Post until the gallery is live or the user steps
    /// away from a failure.
    ///
    /// Gated on `isSubmitting` rather than on the stage alone: the upload
    /// center is app-wide, and a gallery finishing in the background must not
    /// throw an overlay over a create sheet the user just opened.
    private var isPublishing: Bool {
        guard isSubmitting else { return false }
        switch uploadCenter.stage {
        case .idle, .finished: return false
        default: return true
        }
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
            }
            // Lock the Form's vertical scroll while the zoom overlay is up so a
            // pinch that drifts vertically can't scroll the page underneath the
            // overlay. Also stays locked during reorder, same as before.
            .scrollDisabled(isReordering || isAnimatingMode || imageZoomState.showOverlay)
            .scrollDismissesKeyboard(.interactively)
            .background(SheetGestureDisabler(isDisabled: isReordering))

            if isPublishing {
                GalleryPublishOverlay(
                    stage: uploadCenter.stage,
                    onRetry: { Task { await retryPublish() } },
                    onPostLater: {
                        // The draft stays on disk; the app picks it back up on
                        // the next launch or foreground.
                        uploadCenter.setAside()
                        isSubmitting = false
                        dismiss()
                    }
                )
            }
        }
        .animation(.smooth, value: isPublishing)
        .interactiveDismissDisabled(isReordering || isPublishing)
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
                if selectedPhotoID == nil {
                    selectedPhotoID = item.id
                }
            }
            .ignoresSafeArea()
        }
        .task {
            if let authContext = await auth.authContext(),
               let prefs = try? await client.getPreferences(auth: authContext).preferences
            {
                if let exif = prefs.includeExif {
                    sendExif = exif
                }
                if let location = prefs.includeLocation {
                    includeLocation = location
                }
            }
        }
        .navigationTitle("New gallery")
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
                    Text("Post")
                        .bold()
                }
                .buttonStyle(.glassProminent)
                .disabled(title.isEmpty || photoItems.isEmpty || isPublishing || title.count > maxTitle || description.count > maxDescription)
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .onDisappear {
            // A failure the user walked away from shouldn't greet the next
            // gallery they start.
            uploadCenter.clearFailure()
        }
        .alert("Discard gallery?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
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
                Label("Select photos", systemImage: "photo.on.rectangle.angled")
            }

            Button {
                showCamera = true
            } label: {
                Label("Take photo", systemImage: "camera")
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
                    Label("Alt text", systemImage: "text.below.photo")
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
}

// MARK: - Photo loading & submission

extension CreateGalleryView {
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
                if let item {
                    loaded.append((index, item))
                }
            }
        }
        createSignposter.endInterval("LoadPickerBatch", batchState, "loaded=\(loaded.count)")

        // Dedup: with .continuousAndOrdered the picker fires onChange per-item,
        // so a previous load may have already added some of these.
        let alreadyLoaded = Set(photoItems.compactMap { item -> String? in
            guard case let .picker(pickerItem) = item.source else { return nil }
            return pickerItem.itemIdentifier
        })
        let deduped = loaded.sorted(by: { $0.index < $1.index }).map(\.item).filter { item in
            guard case let .picker(pickerItem) = item.source else { return true }
            return !(pickerItem.itemIdentifier.map { alreadyLoaded.contains($0) } ?? false)
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

    /// Hand the gallery to `GalleryUploadCenter`, which owns everything from
    /// here: resizing the photos onto disk, uploading blobs with retries, and
    /// committing every record in one atomic write. All this view does is
    /// collect the fields and react to the result.
    private func createGallery() async {
        guard let repo = auth.userDID else { return }
        isSubmitting = true
        let published = await uploadCenter.publish(
            items: photoItems,
            repo: repo,
            title: title,
            description: description,
            labels: Array(selectedLabels),
            location: resolvedLocation.map {
                GalleryDraft.Location(h3: $0.h3, name: $0.name, address: $0.address)
            },
            includeExif: sendExif,
            postToBluesky: postToBluesky,
            client: client,
            auth: auth
        )
        if published {
            isSubmitting = false
            onCreated?()
            dismiss()
        }
    }

    private func retryPublish() async {
        if await uploadCenter.retry(client: client, auth: auth) {
            isSubmitting = false
            onCreated?()
            dismiss()
        }
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
        let height = thumbnail.size.height
        guard height > 0 else { return 1 }
        return thumbnail.size.width / height
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

// MARK: - EXIF summaries for the editor

// These feed the on-screen `ExifInfoView`. The parallel extraction that
// builds the `social.grain.photo.exif` record lives in `GalleryDraftBuilder`.

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
        if mm > 0 {
            summary.focalLength = "\(mm)mm"
        }
    }
    let parts = [summary.shutterSpeed, summary.iso, summary.focalLength, summary.aperture].compactMap(\.self)
    if !parts.isEmpty {
        summary.exposure = parts.joined(separator: "  ")
    }

    guard summary.camera != nil || summary.lens != nil || summary.exposure != nil else { return nil }
    return summary
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
        .navigationTitle("New gallery")
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
            while let current = responder {
                if let vc = current as? UIViewController,
                   vc.presentationController is UISheetPresentationController,
                   let presentedView = vc.presentationController?.presentedView
                {
                    for gesture in presentedView.gestureRecognizers ?? [] where gesture is UIPanGestureRecognizer {
                        gesture.isEnabled = !disabled
                    }
                    return
                }
                responder = current.next
            }
        }
    }
}

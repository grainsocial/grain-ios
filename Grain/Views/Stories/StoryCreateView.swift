import PhotosUI
import SwiftUI

/// Camera-first story composer. Opens on a live viewfinder with a shutter
/// button; once a photo is taken (or picked from the library) it swaps to a
/// review stage where location, content labels, and cross-posting are set
/// from chips over the photo.
struct StoryCreateView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let client: XRPCClient
    var onCreated: (() -> Void)?

    @State private var camera: StoryCamera
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var resolvedLocation: (h3: String, name: String, address: [String: AnyCodable]?)?
    @State private var photoLocationResult: NominatimResult?
    @State private var includeLocation = true
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var postToBluesky = false
    @State private var selectedLabels: Set<String> = []
    @State private var showLocationSheet = false
    @State private var showLabelSheet = false

    /// `camera` defaults to the real one. A test hands in one whose permission
    /// answer it controls, since the simulator can't reach the ready state.
    init(client: XRPCClient, camera: StoryCamera = StoryCamera(), onCreated: (() -> Void)? = nil) {
        self.client = client
        self.onCreated = onCreated
        _camera = State(initialValue: camera)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // The capture stage stays mounted underneath the review stage.
            // Tearing down the viewfinder and re-attaching its preview layer
            // to the running session stalls the main thread for a beat, which
            // made retake feel sluggish.
            StoryCaptureStage(
                camera: camera,
                selectedPhoto: $selectedPhoto,
                errorMessage: previewImage == nil ? errorMessage : nil,
                onCapture: handleCameraImage,
                onCaptureFailed: { errorMessage = "Couldn't take the photo. Try again." },
                onCancel: { dismiss() }
            )
            .accessibilityHidden(previewImage != nil)

            if let previewImage {
                StoryReviewStage(
                    image: previewImage,
                    locationName: resolvedLocation?.name,
                    labelSummary: labelSummary,
                    postToBluesky: $postToBluesky,
                    errorMessage: errorMessage,
                    isUploading: isUploading,
                    onRetake: discardPhoto,
                    onEditLocation: { showLocationSheet = true },
                    onClearLocation: { resolvedLocation = nil },
                    onEditLabels: { showLabelSheet = true },
                    onClearLabels: { selectedLabels = [] },
                    onPost: { Task { await createStory() } }
                )
                .background(Color.black.ignoresSafeArea())
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: previewImage == nil)
        .preferredColorScheme(.dark)
        .task {
            if let authContext = await auth.authContext(),
               let prefs = try? await client.getPreferences(auth: authContext).preferences,
               let location = prefs.includeLocation
            {
                includeLocation = location
            }
        }
        .task {
            guard !isPreview else { return }
            await camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: selectedPhoto) {
            Task { await loadPhoto() }
        }
        .sheet(isPresented: $showLocationSheet) {
            StoryLocationSheet(
                resolvedLocation: $resolvedLocation,
                photoLocationResult: photoLocationResult,
                onSelectLocation: selectLocation
            )
        }
        .sheet(isPresented: $showLabelSheet) {
            StoryContentLabelSheet(selectedLabels: $selectedLabels)
        }
    }

    private var labelSummary: String? {
        guard !selectedLabels.isEmpty else { return nil }
        return selectedLabels.sorted().map(\.capitalized).joined(separator: ", ")
    }

    // MARK: - Camera

    private func handleCameraImage(_ image: UIImage) {
        previewImage = image
        selectedPhoto = nil
        resolvedLocation = nil
        photoLocationResult = nil
        errorMessage = nil
    }

    private func discardPhoto() {
        previewImage = nil
        selectedPhoto = nil
        resolvedLocation = nil
        photoLocationResult = nil
        errorMessage = nil
    }

    // MARK: - Photo Loading

    private func loadPhoto() async {
        guard let item = selectedPhoto,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        previewImage = image
        errorMessage = nil

        resolvedLocation = nil
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
        guard let previewImage else { return }

        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        let draft = StoryDraft(
            image: previewImage,
            location: resolvedLocation.map { StoryDraft.Location(h3: $0.h3, name: $0.name, address: $0.address) },
            labels: selectedLabels,
            postToBluesky: postToBluesky
        )
        switch await StoryService.publish(draft, client: client, auth: auth) {
        case .success:
            onCreated?()
            dismiss()
        case let .failure(error):
            errorMessage = StoryService.message(for: error)
        }
    }

    // MARK: - Location

    private func selectLocation(_ result: NominatimResult) {
        let h3 = LocationServices.latLonToH3(latitude: result.latitude, longitude: result.longitude)
        resolvedLocation = (h3: h3, name: result.name, address: result.address)
    }
}

#Preview("Capture") {
    StoryCreateView(client: .preview)
        .previewEnvironments()
        .grainPreview()
}

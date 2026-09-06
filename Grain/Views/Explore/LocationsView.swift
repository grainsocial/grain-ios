import CoreLocation
import SwiftUI

/// Every place, on a map that never goes away, with a sheet over it.
///
/// The map fills the window and its camera is the screen's state: nothing you
/// open moves it. The sheet peeks over the bottom third and drags up; by
/// default it holds the index tiles, and picking a place — a pin, a tile —
/// swaps them for that place's galleries while the camera flies there. The
/// arrow in the sheet brings the index back with the map untouched, and a tap
/// on another pin just swaps places. A push that came back to a map that had
/// forgotten where it was made every second look start over.
///
/// A gallery opens over the whole screen, as on Android: the sheet steps
/// aside for the push and comes back when the map does, with the place and
/// the camera exactly as they were.
struct LocationsView: View {
    /// A chip on explore names a place; the screen then opens on it, the map
    /// flying there instead of framing the world.
    struct InitialPlace: Hashable {
        var cell: String?
        var name: String?
        var galleryCount = 0
    }

    @Environment(AuthManager.self) private var auth
    @Environment(Router.self) private var router
    @State private var viewModel: LocationsViewModel
    @State private var camera: MapCameraRequest?
    @State private var sheetPresented = false
    @State private var fitted = false
    /// How deep this screen sits in the tab's stack, taken when it first
    /// appears. The sheet belongs up only while nothing is pushed over it.
    @State private var depth: Int?

    let client: XRPCClient
    let initialPlace: InitialPlace

    /// How much of the window the sheet takes when it is out of the way.
    private static let peekFraction: CGFloat = 0.38
    /// How far up it can be dragged: a strip of the map stays visible above it.
    private static let maxFraction: CGFloat = 0.88
    /// The web fits with `maxZoom: 5`: the index opens on the world.
    private static let fitMaxZoom = 5.0
    /// City scale: far enough in that a picked place reads as somewhere.
    private static let placeZoom = 9.0

    init(client: XRPCClient, initialPlace: InitialPlace = InitialPlace(), viewModel: LocationsViewModel? = nil) {
        self.client = client
        self.initialPlace = initialPlace
        _viewModel = State(initialValue: viewModel ?? LocationsViewModel(client: client))
    }

    private var openedOnPlace: Bool {
        initialPlace.cell != nil && initialPlace.name != nil
    }

    private var marker: MapMarker? {
        guard let place = viewModel.selected, let coordinate = place.coordinate else { return nil }
        return MapMarker(coordinate: coordinate, label: localityOf(place.name))
    }

    var body: some View {
        GeometryReader { proxy in
            GrainMapView(
                pins: viewModel.pins,
                marker: marker,
                camera: camera,
                interactive: true,
                // The camera frames the part above the sheet and below the
                // bar, so a fit or a fly-to lands in view rather than under
                // either.
                contentInsets: UIEdgeInsets(
                    top: proxy.safeAreaInsets.top,
                    left: 0,
                    bottom: proxy.size.height * Self.peekFraction,
                    right: 0
                ),
                onSelectPin: { pin in
                    select(cell: pin.h3Index, name: pin.name, galleryCount: pin.galleryCount)
                }
            )
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Not `onAppear` alone: a swipe back from a gallery fires it the
        // moment the gesture starts, with the gallery still on the stack, and
        // a sheet presented into a pop that might be cancelled fought the
        // transition and left the screen stuck. The path only changes once a
        // pop completes, so it is what decides.
        .onAppear { syncSheet() }
        .onDisappear { sheetPresented = false }
        .onChange(of: router.path.count) { syncSheet() }
        .sheet(isPresented: $sheetPresented) { sheet }
        .task {
            guard !isPreview else { return }
            let context = await auth.authContext()
            if let cell = initialPlace.cell, let name = initialPlace.name {
                viewModel.select(cell: cell, name: name, galleryCount: initialPlace.galleryCount, auth: context)
            }
            await viewModel.load(auth: context)
        }
        // Once, when the pins arrive: the index opens on the world, and after
        // that the camera is the reader's. Not when the screen opened on a
        // place, whose fly-to the fit would land on top of.
        .onChange(of: viewModel.pins) {
            guard !fitted, !viewModel.pins.isEmpty, !openedOnPlace else { return }
            fitted = true
            camera = MapCameraRequest(move: .fit(maxZoom: Self.fitMaxZoom))
        }
        // Fly to a picked place, keeping whatever zoom the reader had worked
        // their way down to unless it is too far out to show a city.
        .onChange(of: viewModel.selected?.h3Index, initial: true) {
            guard let coordinate = viewModel.selected?.coordinate else { return }
            camera = MapCameraRequest(move: .fly(latitude: coordinate.latitude, longitude: coordinate.longitude, minZoom: Self.placeZoom))
        }
    }

    /// The credentials are a hop away, and a tap handler can't wait for
    /// them — so the sheet swaps first and the galleries follow.
    private func select(cell: String, name: String, galleryCount: Int) {
        Task {
            await viewModel.select(cell: cell, name: name, galleryCount: galleryCount, auth: auth.authContext())
        }
    }

    /// The push goes on the tab's stack, so the gallery has the whole
    /// window; the sheet would otherwise sit over it. `syncSheet` brings the
    /// sheet back once the gallery is popped.
    private func openGallery(_ uri: String) {
        router.push(.gallery(uri: uri))
        sheetPresented = false
    }

    /// Present the sheet when this screen is the top of the stack, and only
    /// then. Presenting waits a beat for the pop's animation to finish;
    /// dismissing is immediate.
    private func syncSheet() {
        let count = router.path.count
        if depth == nil {
            depth = count
        }
        guard count == depth else {
            sheetPresented = false
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard router.path.count == depth else { return }
            sheetPresented = true
        }
    }

    private var sheet: some View {
        Group {
            if let place = viewModel.selected {
                PlaceSheet(place: place, onBack: viewModel.clearSelection, onOpenGallery: openGallery) {
                    await viewModel.loadMoreGalleries(auth: auth.authContext())
                }
            } else {
                IndexSheet(viewModel: viewModel) { place in
                    select(cell: place.h3Index, name: place.name, galleryCount: place.galleryCount)
                }
            }
        }
        .presentationDetents([.fraction(Self.peekFraction), .fraction(Self.maxFraction)])
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(Self.peekFraction)))
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }
}

/// The index: a heading and the top thirty as tiles.
struct IndexSheet: View {
    let viewModel: LocationsViewModel
    let onSelect: (LocationItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeading(title: "Locations", meta: nil, onBack: nil)
                if viewModel.places.isEmpty {
                    SheetState(loading: viewModel.isLoading, text: viewModel.failed ? "Couldn't load locations." : "No locations yet.")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                        // Unkeyed by cell on purpose: two places can legitimately
                        // share one, and the web's keyed list threw on exactly that.
                        ForEach(Array(viewModel.places.enumerated()), id: \.offset) { _, place in
                            BrowseTile(
                                title: place.name,
                                meta: counted(place.galleryCount, "gallery", "galleries"),
                                thumbs: place.thumbs ?? []
                            ) {
                                onSelect(place)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// One place: its name over a grid of its galleries, paged.
struct PlaceSheet: View {
    let place: SelectedPlace
    let onBack: () -> Void
    let onOpenGallery: (String) -> Void
    let onLoadMore: () async -> Void

    @State private var width: CGFloat = 0
    private static let columns = 3
    private static let spacing: CGFloat = 2

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeading(title: place.name, meta: counted(place.galleryCount, "gallery", "galleries"), onBack: onBack)
                if place.galleries.isEmpty {
                    SheetState(loading: place.isLoading, text: "No galleries here yet.")
                } else {
                    let cellWidth = max((width - Self.spacing * CGFloat(Self.columns - 1)) / CGFloat(Self.columns), 0)
                    let cellSize = CGSize(width: cellWidth, height: cellWidth * 4 / 3)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: Self.columns),
                        spacing: Self.spacing
                    ) {
                        ForEach(place.galleries) { gallery in
                            GalleryThumbnailCell(gallery: gallery, cellSize: cellSize) {
                                onOpenGallery(gallery.uri)
                            }
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .onAppear {
                                if gallery.id == place.galleries.last?.id {
                                    Task { await onLoadMore() }
                                }
                            }
                        }
                    }
                    if place.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
            }
        }
        // Keyed on the place so a swap starts the grid at the top rather than
        // wherever the last place was scrolled to.
        .id(place.h3Index)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

private struct SheetHeading: View {
    let title: String
    let meta: String?
    let onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All locations")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                if let meta {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, onBack == nil ? 16 : 6)
        .padding(.trailing, 16)
        // Room under the drag indicator and over the grid, so the heading
        // reads as the sheet's own rather than the first row's.
        .padding(.top, 26)
        .padding(.bottom, 18)
    }
}

private struct SheetState: View {
    let loading: Bool
    let text: String

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

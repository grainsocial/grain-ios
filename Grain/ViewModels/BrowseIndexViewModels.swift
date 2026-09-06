import CoreLocation
import Foundation

/// The cameras index: the top thirty by photo count, a tile each.
@Observable
@MainActor
final class CamerasViewModel {
    var cameras: [CameraItem] = []
    var isLoading = true
    var failed = false

    private let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
    }

    func load(auth: AuthContext? = nil) async {
        failed = false
        do {
            cameras = try await client.getCameras(auth: auth).cameras ?? []
        } catch {
            failed = true
        }
        isLoading = false
    }
}

/// One place on the index map.
struct LocationPin: Identifiable, Equatable, Sendable {
    let name: String
    let h3Index: String
    let galleryCount: Int
    let coordinate: CLLocationCoordinate2D
    var id: String {
        h3Index
    }

    static func == (lhs: LocationPin, rhs: LocationPin) -> Bool {
        lhs.h3Index == rhs.h3Index && lhs.name == rhs.name && lhs.galleryCount == rhs.galleryCount
    }
}

/// The place the sheet is showing, with its galleries paged behind it.
///
/// `coordinate` is nil where the cell can't be resolved, and the map then
/// stays where it was rather than flying to the wrong place.
struct SelectedPlace: Equatable {
    let name: String
    let h3Index: String
    let galleryCount: Int
    let coordinate: CLLocationCoordinate2D?
    var galleries: [GrainGallery] = []
    var isLoading = true
    var isLoadingMore = false

    var isEmpty: Bool {
        !isLoading && galleries.isEmpty
    }

    static func == (lhs: SelectedPlace, rhs: SelectedPlace) -> Bool {
        lhs.h3Index == rhs.h3Index && lhs.galleries.map(\.uri) == rhs.galleries.map(\.uri)
            && lhs.isLoading == rhs.isLoading && lhs.isLoadingMore == rhs.isLoadingMore
    }
}

/// The locations index: every place as a pin on a map, the top thirty as
/// tiles in a sheet over it, and whichever one is picked as a sheet of its
/// galleries.
///
/// Two shapes from one endpoint, asked for at once. Places are spatial, so the
/// map is the index and the tiles are the same list for anyone who would
/// rather read — but thumbnails cost the appview a query per place, so only
/// the ranked thirty carry them.
///
/// Picking a place doesn't leave the screen: the map is where the exploring
/// happens, and a push that came back to a map that had forgotten where it
/// was made every second look start over.
@Observable
@MainActor
final class LocationsViewModel {
    var places: [LocationItem] = []
    var pins: [LocationPin] = []
    var selected: SelectedPlace?
    var isLoading = true
    var failed = false

    private let client: XRPCClient
    private var galleriesTask: Task<Void, Never>?
    private var galleryCursor: String?

    init(client: XRPCClient) {
        self.client = client
    }

    func load(auth: AuthContext? = nil) async {
        failed = false
        async let topReq = client.getLocations(auth: auth)
        async let pinsReq = client.getLocations(pins: true, auth: auth)

        do {
            places = try await topReq.locations ?? []
        } catch {
            failed = true
        }
        // The map is scenery over the list, so its failure is silent: the
        // tiles still say where everything is.
        if let all = try? await pinsReq.locations {
            pins = all.compactMap { place in
                LocationServices.h3ToCoordinate(place.h3Index).map {
                    LocationPin(name: place.name, h3Index: place.h3Index, galleryCount: place.galleryCount, coordinate: $0)
                }
            }
        }
        isLoading = false
    }

    /// Show `name`'s galleries in the sheet. Picking the place already shown
    /// is a no-op rather than a reload, so a second tap on the pin you are
    /// looking at doesn't blank the sheet.
    func select(cell: String, name: String, galleryCount: Int, auth: AuthContext? = nil) {
        if selected?.h3Index == cell {
            return
        }
        galleriesTask?.cancel()
        galleryCursor = nil
        selected = SelectedPlace(
            name: name,
            h3Index: cell,
            galleryCount: galleryCount,
            coordinate: LocationServices.h3ToCoordinate(cell)
        )
        galleriesTask = Task {
            do {
                let response = try await client.getFeed(feed: "location", location: cell, name: name, auth: auth)
                guard !Task.isCancelled, selected?.h3Index == cell else { return }
                galleryCursor = response.cursor
                selected?.galleries = response.items ?? []
                selected?.isLoading = false
            } catch {
                guard !Task.isCancelled, selected?.h3Index == cell else { return }
                selected?.isLoading = false
            }
        }
    }

    /// Back to the index, with the map left where it is.
    func clearSelection() {
        galleriesTask?.cancel()
        selected = nil
    }

    func loadMoreGalleries(auth: AuthContext? = nil) async {
        guard let place = selected, let cursor = galleryCursor, !place.isLoadingMore, !place.isLoading else { return }
        selected?.isLoadingMore = true
        do {
            let response = try await client.getFeed(feed: "location", cursor: cursor, location: place.h3Index, name: place.name, auth: auth)
            guard selected?.h3Index == place.h3Index else { return }
            galleryCursor = response.cursor
            selected?.galleries.append(contentsOf: response.items ?? [])
        } catch {}
        if selected?.h3Index == place.h3Index {
            selected?.isLoadingMore = false
        }
    }
}

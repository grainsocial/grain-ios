import Foundation

struct GetLocationsResponse: Codable, Sendable {
    var locations: [LocationItem]?
}

/// One place in the explore index.
///
/// `h3Index` is the densest cell in the group and what the location feed is
/// asked for; `h3Cells` is every cell whose galleries fold into this place.
/// Both `h3Cells` and `thumbs` are absent in the `pins` shape, which carries
/// only what a map plots.
struct LocationItem: Codable, Sendable, Identifiable {
    let name: String
    let h3Index: String
    let galleryCount: Int
    var h3Cells: [String]?
    /// Up to four recent covers, newest first, for an index tile's mosaic.
    var thumbs: [String]?
    var id: String {
        h3Index
    }

    init(name: String, h3Index: String, galleryCount: Int, h3Cells: [String]? = nil, thumbs: [String]? = nil) {
        self.name = name
        self.h3Index = h3Index
        self.galleryCount = galleryCount
        self.h3Cells = h3Cells
        self.thumbs = thumbs
    }
}

struct GetCamerasResponse: Codable, Sendable {
    var cameras: [CameraItem]?
}

/// One camera in the explore index, with up to four recent photos for its tile.
struct CameraItem: Codable, Sendable, Identifiable {
    let camera: String
    let photoCount: Int
    var thumbs: [String]?
    var id: String {
        camera
    }

    init(camera: String, photoCount: Int, thumbs: [String]? = nil) {
        self.camera = camera
        self.photoCount = photoCount
        self.thumbs = thumbs
    }
}

extension XRPCClient {
    /// The top thirty places by gallery count, each with a few thumbnails — or,
    /// with `pins`, every place with nothing but a name, a cell and a count.
    /// The full shape is about a kilobyte a place, so a map of all of them
    /// asks for the lean one.
    func getLocations(pins: Bool = false, auth: AuthContext? = nil) async throws -> GetLocationsResponse {
        try await query(
            "social.grain.gallery.getLocations",
            params: pins ? ["pins": "true"] : [:],
            auth: auth,
            as: GetLocationsResponse.self
        )
    }

    /// The top thirty cameras by photo count, each with a few thumbnails.
    func getCameras(auth: AuthContext? = nil) async throws -> GetCamerasResponse {
        try await query("social.grain.gallery.getCameras", auth: auth, as: GetCamerasResponse.self)
    }
}

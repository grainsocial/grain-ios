import Foundation

struct GetLocationsResponse: Codable, Sendable {
    var locations: [LocationItem]?
}

struct LocationItem: Codable, Sendable, Identifiable {
    let name: String
    let h3Index: String
    let galleryCount: Int
    var id: String {
        h3Index
    }
}

struct GetCamerasResponse: Codable, Sendable {
    var cameras: [CameraItem]?
}

struct CameraItem: Codable, Sendable, Identifiable {
    let camera: String
    let photoCount: Int
    var id: String {
        camera
    }
}

extension XRPCClient {
    func getLocations(auth: AuthContext? = nil) async throws -> GetLocationsResponse {
        try await query("social.grain.unspecced.getLocations", auth: auth, as: GetLocationsResponse.self)
    }

    func getCameras(auth: AuthContext? = nil) async throws -> GetCamerasResponse {
        try await query("social.grain.unspecced.getCameras", auth: auth, as: GetCamerasResponse.self)
    }
}

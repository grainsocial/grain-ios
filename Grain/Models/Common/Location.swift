import Foundation

/// H3-encoded location (community.lexicon.location.hthree)
struct H3Location: Codable, Sendable {
    let value: String
    var name: String?
}

/// Street address (community.lexicon.location.address)
struct Address: Codable, Sendable {
    let country: String
    var postalCode: String?
    var region: String?
    var locality: String?
    var street: String?
    var name: String?
}

/// Geo coordinate (community.lexicon.location.geo)
struct GeoLocation: Codable, Sendable {
    let latitude: String
    let longitude: String
    var altitude: String?
    var name: String?
}

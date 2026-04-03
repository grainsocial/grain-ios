import Foundation
import SwiftyH3

struct NominatimResult {
    let placeId: Int
    let latitude: Double
    let longitude: Double
    let name: String
    let context: String?
    let address: [String: AnyCodable]?

    init?(from json: [String: Any]) {
        guard let placeId = json["place_id"] as? Int else { return nil }
        self.placeId = placeId

        if let lat = json["lat"] as? String, let lon = json["lon"] as? String,
           let latD = Double(lat), let lonD = Double(lon) {
            self.latitude = latD
            self.longitude = lonD
        } else if let lat = json["lat"] as? Double, let lon = json["lon"] as? Double {
            self.latitude = lat
            self.longitude = lon
        } else {
            return nil
        }

        let addr = json["address"] as? [String: Any]
        let city = addr?["city"] as? String ?? addr?["town"] as? String ?? addr?["village"] as? String

        if let placeName = json["name"] as? String, !placeName.isEmpty {
            self.name = placeName
        } else {
            var parts: [String] = []
            if let city { parts.append(city) }
            if let state = addr?["state"] as? String { parts.append(state) }
            if let country = addr?["country"] as? String { parts.append(country) }
            self.name = parts.isEmpty
                ? (json["display_name"] as? String ?? "Unknown").components(separatedBy: ",").first ?? "Unknown"
                : parts.joined(separator: ", ")
        }

        var contextParts: [String] = []
        if let city { contextParts.append(city) }
        if let state = addr?["state"] as? String { contextParts.append(state) }
        if let country = addr?["country"] as? String { contextParts.append(country) }
        self.context = contextParts.isEmpty ? nil : contextParts.joined(separator: ", ")

        if let countryCode = (addr?["country_code"] as? String)?.uppercased() {
            var a: [String: AnyCodable] = ["country": AnyCodable(countryCode)]
            if let city { a["locality"] = AnyCodable(city) }
            if let state = addr?["state"] as? String { a["region"] = AnyCodable(state) }
            if let road = addr?["road"] as? String {
                if let houseNumber = addr?["house_number"] as? String {
                    a["street"] = AnyCodable("\(houseNumber) \(road)")
                } else {
                    a["street"] = AnyCodable(road)
                }
            }
            if let postcode = addr?["postcode"] as? String { a["postalCode"] = AnyCodable(postcode) }
            self.address = a
        } else {
            self.address = nil
        }
    }
}

enum LocationServices {
    /// Convert lat/lon to H3 index string at resolution 10.
    static func latLonToH3(latitude: Double, longitude: Double) -> String {
        let latLng = H3LatLng(latitudeDegs: latitude, longitudeDegs: longitude)
        guard let cell = try? latLng.cell(at: .res10) else { return "" }
        return cell.description
    }

    /// Coarsen an H3 index to city level (resolution 5).
    static func h3ToCity(_ h3Index: String) -> String {
        guard let cell = H3Cell(h3Index),
              let res = try? cell.resolution,
              res.rawValue > 5,
              let parent = try? cell.parent(at: .res5) else { return h3Index }
        return parent.description
    }

    /// Reverse geocode coordinates via Nominatim.
    static func reverseGeocode(latitude: Double, longitude: Double) async -> NominatimResult? {
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "addressdetails", value: "1"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("grain-app/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return NominatimResult(from: json)
    }

    /// Search for locations via Nominatim.
    static func searchLocation(query: String) async -> [NominatimResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "addressdetails", value: "1"),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("grain-app/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return json.compactMap { NominatimResult(from: $0) }
    }
}

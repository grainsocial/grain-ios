import CoreLocation
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
           let latD = Double(lat), let lonD = Double(lon)
        {
            latitude = latD
            longitude = lonD
        } else if let lat = json["lat"] as? Double, let lon = json["lon"] as? Double {
            latitude = lat
            longitude = lon
        } else {
            return nil
        }

        let addr = json["address"] as? [String: Any]
        let city = addr?["city"] as? String ?? addr?["town"] as? String ?? addr?["village"] as? String

        var locationParts: [String] = []
        if let city { locationParts.append(city) }
        if let state = addr?["state"] as? String { locationParts.append(state) }
        if let country = addr?["country"] as? String { locationParts.append(country) }

        if let placeName = json["name"] as? String, !placeName.isEmpty {
            name = placeName
        } else {
            name = locationParts.isEmpty
                ? (json["display_name"] as? String ?? "Unknown").components(separatedBy: ",").first ?? "Unknown"
                : locationParts.joined(separator: ", ")
        }

        context = locationParts.isEmpty ? nil : locationParts.joined(separator: ", ")

        if let countryCode = (addr?["country_code"] as? String)?.uppercased() {
            var addressFields: [String: AnyCodable] = ["country": AnyCodable(countryCode)]
            if let city { addressFields["locality"] = AnyCodable(city) }
            if let state = addr?["state"] as? String { addressFields["region"] = AnyCodable(state) }
            if let road = addr?["road"] as? String {
                if let houseNumber = addr?["house_number"] as? String {
                    addressFields["street"] = AnyCodable("\(houseNumber) \(road)")
                } else {
                    addressFields["street"] = AnyCodable(road)
                }
            }
            if let postcode = addr?["postcode"] as? String { addressFields["postalCode"] = AnyCodable(postcode) }
            address = addressFields
        } else {
            address = nil
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

    /// Convert an H3 index string to a CLLocationCoordinate2D.
    static func h3ToCoordinate(_ h3Index: String) -> CLLocationCoordinate2D? {
        guard let cell = H3Cell(h3Index),
              let center = try? cell.center else { return nil }
        return center.coordinates
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }

        return json.compactMap { NominatimResult(from: $0) }
    }
}

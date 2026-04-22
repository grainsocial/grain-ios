@testable import Grain
import XCTest

final class NominatimResultTests: XCTestCase {
    /// Reverse-geocoding a spot in Kansas City returns a `county` field. It must not
    /// leak into the stored `name` — we want "Kansas City, Missouri, United States",
    /// not "Kansas City, Jackson County, Missouri, United States".
    func testReverseGeocode_KansasCity_ExcludesCounty() {
        let json: [String: Any] = [
            "place_id": 12345,
            "lat": "39.0997",
            "lon": "-94.5786",
            "display_name": "Kansas City, Jackson County, Missouri, 64108, United States",
            "address": [
                "city": "Kansas City",
                "county": "Jackson County",
                "state": "Missouri",
                "country": "United States",
                "country_code": "us",
                "postcode": "64108",
            ],
        ]

        let result = NominatimResult(from: json)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "Kansas City, Missouri, United States")
        XCTAssertFalse(result?.name.contains("County") ?? true,
                       "Name must not include county")
    }

    /// POI with a `name` from Nominatim should use that name as-is.
    func testReverseGeocode_POI_UsesPlaceName() {
        let json: [String: Any] = [
            "place_id": 54321,
            "lat": "37.7749",
            "lon": "-122.4194",
            "name": "Blue Bottle Coffee",
            "display_name": "Blue Bottle Coffee, Mint Plaza, San Francisco, California, United States",
            "address": [
                "amenity": "Blue Bottle Coffee",
                "city": "San Francisco",
                "county": "San Francisco County",
                "state": "California",
                "country": "United States",
                "country_code": "us",
            ],
        ]

        let result = NominatimResult(from: json)
        XCTAssertEqual(result?.name, "Blue Bottle Coffee")
    }

    /// Structured address dict must contain locality/region/country — never county.
    func testReverseGeocode_AddressExcludesCounty() {
        let json: [String: Any] = [
            "place_id": 12345,
            "lat": "39.0997",
            "lon": "-94.5786",
            "display_name": "anything",
            "address": [
                "city": "Kansas City",
                "county": "Jackson County",
                "state": "Missouri",
                "country": "United States",
                "country_code": "us",
            ],
        ]

        let result = NominatimResult(from: json)
        XCTAssertEqual(result?.address?["locality"]?.stringValue, "Kansas City")
        XCTAssertEqual(result?.address?["region"]?.stringValue, "Missouri")
        XCTAssertEqual(result?.address?["country"]?.stringValue, "US")
        XCTAssertNil(result?.address?["county"])
    }
}

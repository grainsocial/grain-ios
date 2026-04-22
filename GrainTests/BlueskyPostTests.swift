@testable import Grain
import XCTest

final class BlueskyPostTests: XCTestCase {
    private let url = "https://grain.social/profile/did:plc:abc/gallery/xyz"

    /// POI with distinct name — append locality, region, country
    func testBuildPostText_POILocation_IncludesFullContext() {
        let text = BlueskyPost.buildPostText(
            url: url,
            title: "2025-10-12",
            location: (
                name: "Overlook Mountain Fire Tower",
                address: [
                    "locality": AnyCodable("Town of Woodstock"),
                    "region": AnyCodable("New York"),
                    "country": AnyCodable("US"),
                ]
            ),
            description: nil
        )

        XCTAssertEqual(text, """
        2025-10-12

        📍 Overlook Mountain Fire Tower, Town of Woodstock, New York, US

        #GrainSocial \(url)
        """)
    }

    /// Coffee shop POI — primary label differs from locality, so locality is kept.
    func testBuildPostText_POICafe_IncludesLocality() {
        let text = BlueskyPost.buildPostText(
            url: url,
            title: nil,
            location: (
                name: "Blue Bottle Coffee",
                address: [
                    "locality": AnyCodable("Oakland"),
                    "region": AnyCodable("California"),
                    "country": AnyCodable("US"),
                ]
            ),
            description: nil
        )

        XCTAssertTrue(text.contains("📍 Blue Bottle Coffee, Oakland, California, US"),
                      "Got: \(text)")
    }

    /// Nominatim city fallback — `name` already contains locality/region/country.
    /// Must NOT duplicate by appending region + country.
    func testBuildPostText_CityName_DoesNotDuplicate() {
        let text = BlueskyPost.buildPostText(
            url: url,
            title: "2025-09-14",
            location: (
                name: "New York, New York, United States",
                address: [
                    "locality": AnyCodable("New York"),
                    "region": AnyCodable("New York"),
                    "country": AnyCodable("US"),
                ]
            ),
            description: nil
        )

        XCTAssertEqual(text, """
        2025-09-14

        📍 New York, US

        #GrainSocial \(url)
        """)
    }

    /// `name` already includes the state abbreviation. Must not repeat it.
    func testBuildPostText_NameWithStateAbbrev_DoesNotDuplicate() {
        let text = BlueskyPost.buildPostText(
            url: url,
            title: nil,
            location: (
                name: "Seattle, WA",
                address: [
                    "locality": AnyCodable("Seattle"),
                    "region": AnyCodable("WA"),
                    "country": AnyCodable("US"),
                ]
            ),
            description: nil
        )

        XCTAssertTrue(text.contains("📍 Seattle, WA, US"), "Got: \(text)")
        XCTAssertFalse(text.contains("Seattle, WA, Seattle"))
        XCTAssertFalse(text.contains("WA, WA"))
    }

    /// Real story from moll.blue: `name` contains county baked in by older client.
    /// Must render as "Kansas City, Missouri, US" — no county, no duplication.
    func testBuildPostText_NameWithEmbeddedCounty_SkipsCounty() {
        let text = BlueskyPost.buildPostText(
            url: url,
            title: nil,
            location: (
                name: "Kansas City, Jackson County, Missouri, United States",
                address: [
                    "locality": AnyCodable("Kansas City"),
                    "region": AnyCodable("Missouri"),
                    "country": AnyCodable("US"),
                ]
            ),
            description: nil
        )

        XCTAssertTrue(text.contains("📍 Kansas City, Missouri, US"), "Got: \(text)")
        XCTAssertFalse(text.contains("County"), "Got: \(text)")
    }

    /// POI where region differs from the primary label.
    func testBuildPostText_CityWithDistinctRegion_IncludesRegion() {
        let text = BlueskyPost.buildPostText(
            url: url,
            title: nil,
            location: (
                name: "Albany, New York, United States",
                address: [
                    "locality": AnyCodable("Albany"),
                    "region": AnyCodable("New York"),
                    "country": AnyCodable("US"),
                ]
            ),
            description: nil
        )

        XCTAssertTrue(text.contains("📍 Albany, New York, US"),
                      "Got: \(text)")
    }

    func testBuildPostText_TitleAndDescription_JoinedWithComma() {
        let text = BlueskyPost.buildPostText(
            url: url,
            title: "Sunset at the Beach",
            location: nil,
            description: "A lovely evening"
        )

        XCTAssertTrue(text.hasPrefix("Sunset at the Beach, A lovely evening"))
    }

    /// Legacy community.lexicon.location.hthree records have no address.
    /// Name should be preserved as-is — don't strip context after first comma.
    func testBuildPostText_LegacyHthreeRecord_PreservesFullName() {
        let text = BlueskyPost.buildPostText(
            url: url,
            title: nil,
            location: (name: "Eindhoven, North Brabant, Netherlands", address: nil),
            description: nil
        )

        XCTAssertTrue(text.contains("📍 Eindhoven, North Brabant, Netherlands"),
                      "Got: \(text)")
    }

    func testBuildPostText_NoLocationNoContent_ProducesCleanSuffix() {
        let text = BlueskyPost.buildPostText(
            url: url,
            title: nil,
            location: nil,
            description: nil
        )

        XCTAssertEqual(text, "\n#GrainSocial \(url)")
    }

    func testBuildPostText_AddressOnlyCountry_StillRenders() {
        let text = BlueskyPost.buildPostText(
            url: url,
            title: "Trip",
            location: (
                name: "Eiffel Tower",
                address: ["country": AnyCodable("FR")]
            ),
            description: nil
        )

        XCTAssertTrue(text.contains("📍 Eiffel Tower, FR"))
    }
}

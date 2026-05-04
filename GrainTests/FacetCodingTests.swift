@testable import Grain
import XCTest

final class FacetCodingTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: - Decoding

    func testDecodeMention() throws {
        let json = Data("""
        {"$type": "app.bsky.richtext.facet#mention", "did": "did:plc:abc123"}
        """.utf8)
        let feature = try decoder.decode(FacetFeature.self, from: json)
        if case let .mention(did) = feature {
            XCTAssertEqual(did, "did:plc:abc123")
        } else {
            XCTFail("Expected mention, got \(feature)")
        }
    }

    func testDecodeLink() throws {
        let json = Data("""
        {"$type": "app.bsky.richtext.facet#link", "uri": "https://example.com"}
        """.utf8)
        let feature = try decoder.decode(FacetFeature.self, from: json)
        if case let .link(uri) = feature {
            XCTAssertEqual(uri, "https://example.com")
        } else {
            XCTFail("Expected link, got \(feature)")
        }
    }

    func testDecodeTag() throws {
        let json = Data("""
        {"$type": "app.bsky.richtext.facet#tag", "tag": "photography"}
        """.utf8)
        let feature = try decoder.decode(FacetFeature.self, from: json)
        if case let .tag(tag) = feature {
            XCTAssertEqual(tag, "photography")
        } else {
            XCTFail("Expected tag, got \(feature)")
        }
    }

    func testDecodeUnknownTypeThrows() {
        let json = Data("""
        {"$type": "app.bsky.richtext.facet#unknown", "data": "stuff"}
        """.utf8)
        XCTAssertThrowsError(try decoder.decode(FacetFeature.self, from: json))
    }

    // MARK: - Encoding round-trips

    func testMentionRoundTrip() throws {
        let original = FacetFeature.mention(did: "did:plc:xyz")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(FacetFeature.self, from: data)
        if case let .mention(did) = decoded {
            XCTAssertEqual(did, "did:plc:xyz")
        } else {
            XCTFail("Round-trip failed")
        }
    }

    func testLinkRoundTrip() throws {
        let original = FacetFeature.link(uri: "https://grain.social")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(FacetFeature.self, from: data)
        if case let .link(uri) = decoded {
            XCTAssertEqual(uri, "https://grain.social")
        } else {
            XCTFail("Round-trip failed")
        }
    }

    func testTagRoundTrip() throws {
        let original = FacetFeature.tag(tag: "streetphoto")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(FacetFeature.self, from: data)
        if case let .tag(tag) = decoded {
            XCTAssertEqual(tag, "streetphoto")
        } else {
            XCTFail("Round-trip failed")
        }
    }

    // MARK: - Full Facet

    func testDecodeFacetWithFeatures() throws {
        let json = Data("""
        {
            "index": {"byteStart": 0, "byteEnd": 10},
            "features": [
                {"$type": "app.bsky.richtext.facet#mention", "did": "did:plc:test"}
            ]
        }
        """.utf8)
        let facet = try decoder.decode(Facet.self, from: json)
        XCTAssertEqual(facet.index.byteStart, 0)
        XCTAssertEqual(facet.index.byteEnd, 10)
        XCTAssertEqual(facet.features.count, 1)
    }

    // MARK: - toAnyCodableDict (record write shape)

    /// Round-trips a Facet through `toAnyCodableDict` → JSON → Facet. Guards the
    /// wire format used when persisting comment/gallery records — backend mention
    /// notifications depend on this shape matching `app.bsky.richtext.facet`.
    func testToAnyCodableDictRoundTripsAllFeatureTypes() throws {
        let original = Facet(
            index: Facet.ByteSlice(byteStart: 5, byteEnd: 42),
            features: [
                .mention(did: "did:plc:abc"),
                .link(uri: "https://example.com"),
                .tag(tag: "photography"),
            ]
        )
        let dict = original.toAnyCodableDict()
        let json = try encoder.encode(AnyCodable(dict))
        let decoded = try decoder.decode(Facet.self, from: json)

        XCTAssertEqual(decoded.index.byteStart, 5)
        XCTAssertEqual(decoded.index.byteEnd, 42)
        XCTAssertEqual(decoded.features.count, 3)

        guard case let .mention(did) = decoded.features[0] else {
            return XCTFail("Expected mention at index 0")
        }
        XCTAssertEqual(did, "did:plc:abc")

        guard case let .link(uri) = decoded.features[1] else {
            return XCTFail("Expected link at index 1")
        }
        XCTAssertEqual(uri, "https://example.com")

        guard case let .tag(tag) = decoded.features[2] else {
            return XCTFail("Expected tag at index 2")
        }
        XCTAssertEqual(tag, "photography")
    }
}

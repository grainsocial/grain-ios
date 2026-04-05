@testable import Grain
import XCTest

final class FacetCodingTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: - Decoding

    func testDecodeMention() throws {
        let json = """
        {"$type": "app.bsky.richtext.facet#mention", "did": "did:plc:abc123"}
        """.data(using: .utf8)!
        let feature = try decoder.decode(FacetFeature.self, from: json)
        if case let .mention(did) = feature {
            XCTAssertEqual(did, "did:plc:abc123")
        } else {
            XCTFail("Expected mention, got \(feature)")
        }
    }

    func testDecodeLink() throws {
        let json = """
        {"$type": "app.bsky.richtext.facet#link", "uri": "https://example.com"}
        """.data(using: .utf8)!
        let feature = try decoder.decode(FacetFeature.self, from: json)
        if case let .link(uri) = feature {
            XCTAssertEqual(uri, "https://example.com")
        } else {
            XCTFail("Expected link, got \(feature)")
        }
    }

    func testDecodeTag() throws {
        let json = """
        {"$type": "app.bsky.richtext.facet#tag", "tag": "photography"}
        """.data(using: .utf8)!
        let feature = try decoder.decode(FacetFeature.self, from: json)
        if case let .tag(tag) = feature {
            XCTAssertEqual(tag, "photography")
        } else {
            XCTFail("Expected tag, got \(feature)")
        }
    }

    func testDecodeUnknownTypeThrows() {
        let json = """
        {"$type": "app.bsky.richtext.facet#unknown", "data": "stuff"}
        """.data(using: .utf8)!
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
        let json = """
        {
            "index": {"byteStart": 0, "byteEnd": 10},
            "features": [
                {"$type": "app.bsky.richtext.facet#mention", "did": "did:plc:test"}
            ]
        }
        """.data(using: .utf8)!
        let facet = try decoder.decode(Facet.self, from: json)
        XCTAssertEqual(facet.index.byteStart, 0)
        XCTAssertEqual(facet.index.byteEnd, 10)
        XCTAssertEqual(facet.features.count, 1)
    }
}

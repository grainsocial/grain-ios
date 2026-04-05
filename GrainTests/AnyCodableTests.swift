@testable import Grain
import XCTest

final class AnyCodableTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Init variants

    func testInitWithString() throws {
        let value = AnyCodable("hello")
        let data = try encoder.encode(value)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(json, "\"hello\"")
    }

    func testInitWithInt() throws {
        let value = AnyCodable(42)
        let data = try encoder.encode(value)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(json, "42")
    }

    func testInitWithBool() throws {
        let value = AnyCodable(true)
        let data = try encoder.encode(value)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(json, "true")
    }

    func testInitWithDouble() throws {
        let value = AnyCodable(3.14)
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(AnyCodable.self, from: data)
        // Round-trip through JSON, re-encode to verify
        let reEncoded = try XCTUnwrap(try String(data: encoder.encode(decoded), encoding: .utf8))
        XCTAssertTrue(reEncoded.contains("3.14"))
    }

    func testInitWithStringDict() throws {
        let value = AnyCodable(["key": "value"] as [String: String])
        let data = try encoder.encode(value)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"key\""))
        XCTAssertTrue(json.contains("\"value\""))
    }

    func testInitWithUnknownTypeFallsToNull() throws {
        let value = AnyCodable(Date())
        let data = try encoder.encode(value)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(json, "null")
    }

    // MARK: - Decoding from JSON

    func testDecodeNull() throws {
        let json = "null".data(using: .utf8)!
        let value = try decoder.decode(AnyCodable.self, from: json)
        // Re-encode should produce null
        let reEncoded = try XCTUnwrap(try String(data: encoder.encode(value), encoding: .utf8))
        XCTAssertEqual(reEncoded, "null")
    }

    func testDecodeString() throws {
        let json = "\"test\"".data(using: .utf8)!
        let value = try decoder.decode(AnyCodable.self, from: json)
        let reEncoded = try XCTUnwrap(try String(data: encoder.encode(value), encoding: .utf8))
        XCTAssertEqual(reEncoded, "\"test\"")
    }

    func testDecodeArray() throws {
        let json = "[1,2,3]".data(using: .utf8)!
        let value = try decoder.decode(AnyCodable.self, from: json)
        let reEncoded = try XCTUnwrap(try String(data: encoder.encode(value), encoding: .utf8))
        XCTAssertEqual(reEncoded, "[1,2,3]")
    }

    func testDecodeNestedDict() throws {
        let json = """
        {"outer": {"inner": "value"}}
        """.data(using: .utf8)!
        let value = try decoder.decode(AnyCodable.self, from: json)
        XCTAssertNotNil(value.dictValue)
        XCTAssertNotNil(value.dictValue?["outer"]?.dictValue)
    }

    // MARK: - dictValue

    func testDictValueReturnsNilForNonDict() {
        let value = AnyCodable("not a dict")
        XCTAssertNil(value.dictValue)
    }

    func testDictValueReturnsDictForDict() {
        let value = AnyCodable(["key": AnyCodable("val")])
        XCTAssertNotNil(value.dictValue)
        XCTAssertEqual(value.dictValue?.count, 1)
    }
}

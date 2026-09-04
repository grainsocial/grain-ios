@testable import Grain
import XCTest

final class TIDTests: GrainTestCase {
    func testNextIsThirteenValidCharacters() {
        let tid = TID.next()
        XCTAssertEqual(tid.count, 13)
        XCTAssertTrue(TID.isValid(tid), "\(tid) should be a valid record key")
    }

    /// Two keys minted in the same microsecond must still differ, or two photos
    /// in one gallery could collide on the same record.
    func testNextIsStrictlyIncreasing() {
        let keys = (0 ..< 500).map { _ in TID.next() }
        XCTAssertEqual(Set(keys).count, keys.count, "TIDs must be unique")
        XCTAssertEqual(keys, keys.sorted(), "TIDs must sort in creation order")
    }

    /// The high bit stays clear, so a TID never starts past 'j'.
    func testLeadingCharacterNeverSetsHighBit() throws {
        for _ in 0 ..< 200 {
            let first = try XCTUnwrap(TID.next().first)
            XCTAssertTrue("234567abcdefghij".contains(first), "unexpected leading character \(first)")
        }
    }

    func testEncodeIsStableForKnownInput() {
        let encoded = TID.encode(micros: 0, clockID: 0)
        XCTAssertEqual(encoded, "2222222222222")
        XCTAssertEqual(TID.encode(micros: 0, clockID: 1), "2222222222223")
    }

    func testEncodeSortsByTimestamp() {
        let earlier = TID.encode(micros: 1_700_000_000_000_000, clockID: 512)
        let later = TID.encode(micros: 1_700_000_000_000_001, clockID: 0)
        XCTAssertLessThan(earlier, later)
    }

    func testIsValidRejectsMalformedKeys() {
        XCTAssertFalse(TID.isValid(""))
        XCTAssertFalse(TID.isValid("short"))
        XCTAssertTrue(TID.isValid("3jzfcijpj2z2a"), "13 characters is the valid length")
        XCTAssertFalse(TID.isValid("3jzfcijpj2z2aa"), "14 characters")
        XCTAssertFalse(TID.isValid("3jzfcijpj2z2"), "12 characters")
        XCTAssertFalse(TID.isValid("zzzzzzzzzzzzz"), "leading character sets the high bit")
        XCTAssertFalse(TID.isValid("3jzfcijpj2z2A"), "uppercase is not in the alphabet")
        XCTAssertFalse(TID.isValid("3jzfcijpj2z21"), "'1' is not in the alphabet")
    }
}

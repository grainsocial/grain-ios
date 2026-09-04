@testable import Grain
import XCTest

/// Count formatting appears under every gallery and on every profile, and the
/// digit proxy is what stops those counts from shifting the layout when they
/// tick over. Both are pure string work, so they are cheap to pin down exactly.
final class StringExtensionsTests: XCTestCase {
    // MARK: - compactCount

    func testCountsBelowAThousandAreLeftAlone() {
        XCTAssertEqual(0.compactCount, "0")
        XCTAssertEqual(7.compactCount, "7")
        XCTAssertEqual(999.compactCount, "999")
    }

    func testRoundThousandsDropTheDecimal() {
        XCTAssertEqual(1000.compactCount, "1K")
        XCTAssertEqual(12000.compactCount, "12K")
    }

    func testUnevenThousandsKeepOneDecimal() {
        XCTAssertEqual(1500.compactCount, "1.5K")
        XCTAssertEqual(9900.compactCount, "9.9K")
    }

    func testRoundMillionsDropTheDecimal() {
        XCTAssertEqual(1_000_000.compactCount, "1M")
        XCTAssertEqual(3_000_000.compactCount, "3M")
    }

    func testUnevenMillionsKeepOneDecimal() {
        XCTAssertEqual(2_500_000.compactCount, "2.5M")
    }

    /// The thousands branch has to lose to the millions branch, or 1M reads as
    /// "1000K".
    func testTheMillionsBranchWinsAtExactlyAMillion() {
        XCTAssertEqual(999_000.compactCount, "999K")
        XCTAssertEqual(1_000_000.compactCount, "1M")
    }

    /// Counts are never negative in practice, but the formatter still has to
    /// return something printable rather than an abbreviated negative.
    func testNegativeCountsAreLeftAlone() {
        XCTAssertEqual((-5).compactCount, "-5")
    }

    // MARK: - digitWidthProxy

    /// The proxy exists to reserve width, so it must be the same length as the
    /// string it stands in for, with only digits replaced.
    func testDigitsBecomeEightsAndNothingElseChanges() {
        XCTAssertEqual("1.5K".digitWidthProxy, "8.8K")
        XCTAssertEqual("2025-01-02".digitWidthProxy, "8888-88-88")
        XCTAssertEqual("1,234 favorites".digitWidthProxy, "8,888 favorites")
    }

    func testStringsWithoutDigitsAreUnchanged() {
        XCTAssertEqual("".digitWidthProxy, "")
        XCTAssertEqual("Favorites".digitWidthProxy, "Favorites")
    }

    func testProxyPreservesLength() {
        for sample in ["0", "999", "12.3M", "3 hours ago"] {
            XCTAssertEqual(sample.digitWidthProxy.count, sample.count, "Proxy for \(sample) changed length")
        }
    }

    /// Non-ASCII digits aren't in the "0"..."9" range, so they pass through —
    /// worth pinning so a future rewrite doesn't silently start mangling them.
    func testNonASCIIDigitsPassThrough() {
        XCTAssertEqual("٣".digitWidthProxy, "٣")
    }
}

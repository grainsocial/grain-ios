@testable import Grain
import XCTest

final class DateFormattingTests: XCTestCase {
    // MARK: - parse()

    func testParseFractionalSeconds() {
        let date = DateFormatting.parse("2024-06-15T12:30:45.123Z")
        XCTAssertNotNil(date)
    }

    func testParseWithoutFractionalSeconds() {
        let date = DateFormatting.parse("2024-06-15T12:30:45Z")
        XCTAssertNotNil(date)
    }

    func testParseInvalidStringReturnsNil() {
        XCTAssertNil(DateFormatting.parse("not-a-date"))
        XCTAssertNil(DateFormatting.parse(""))
        XCTAssertNil(DateFormatting.parse("2024-13-40"))
    }

    func testParseRoundTrip() throws {
        // Generate an ISO string, parse it back, verify it's close to now
        let iso = DateFormatting.nowISO()
        let parsed = DateFormatting.parse(iso)
        XCTAssertNotNil(parsed)
        // Should be within 1 second of now
        let interval = try abs(XCTUnwrap(parsed?.timeIntervalSinceNow))
        XCTAssertLessThan(interval, 1.0)
    }

    // MARK: - relativeTime()

    func testRelativeTimeNow() {
        let iso = DateFormatting.nowISO()
        let result = DateFormatting.relativeTime(iso)
        XCTAssertEqual(result, "now")
    }

    func testRelativeTimeInvalidReturnsEmpty() {
        XCTAssertEqual(DateFormatting.relativeTime("garbage"), "")
    }

    func testRelativeTimeMinutesAgo() {
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        let iso = isoString(from: fiveMinutesAgo)
        let result = DateFormatting.relativeTime(iso)
        XCTAssertEqual(result, "5m")
    }

    func testRelativeTimeHoursAgo() {
        let threeHoursAgo = Date().addingTimeInterval(-12600) // 3.5h, well within the 3h bucket
        let iso = isoString(from: threeHoursAgo)
        let result = DateFormatting.relativeTime(iso)
        XCTAssertEqual(result, "3h")
    }

    func testRelativeTimeDaysAgo() {
        let twoDaysAgo = Date().addingTimeInterval(-180_000) // 50 hours, well within the 2d bucket
        let iso = isoString(from: twoDaysAgo)
        let result = DateFormatting.relativeTime(iso)
        XCTAssertEqual(result, "2d")
    }

    func testRelativeTimeWeeksAgo() {
        let twoWeeksAgo = Date().addingTimeInterval(-1_300_000) // ~2.17 weeks, well within the 2w bucket
        let iso = isoString(from: twoWeeksAgo)
        let result = DateFormatting.relativeTime(iso)
        XCTAssertEqual(result, "2w")
    }

    // MARK: - Helpers

    private func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

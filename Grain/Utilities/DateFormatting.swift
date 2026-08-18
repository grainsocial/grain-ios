import Foundation

enum DateFormatting {
    /// Formatters are expensive to build — each stands up an underlying
    /// CFDateFormatter/ICU instance — and these used to be allocated per call,
    /// with `parse` building *two* for any timestamp lacking fractional seconds.
    /// Profiling a feed scroll measured that at 184ms across 1039 calls: 65% of
    /// all gallery card body-evaluation time.
    ///
    /// The two `ISO8601DateFormatter`s need `nonisolated(unsafe)` because that
    /// type isn't marked `Sendable`, though it is documented as thread-safe for
    /// formatting and parsing so long as its configuration isn't mutated
    /// afterwards — and these are configured once here and only ever read.
    /// (`DateFormatter` below *is* `Sendable`, so it needs no annotation.)
    /// `StoryStatusCache` caches its own formatters the same way, avoiding the
    /// annotation only by being `@MainActor`.
    private nonisolated(unsafe) static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// Produce an ISO 8601 string with fractional seconds (matches JS `toISOString()`).
    static func nowISO(date: Date = Date()) -> String {
        iso8601WithFractionalSeconds.string(from: date)
    }

    /// Parse an ISO 8601 string with or without fractional seconds.
    static func parse(_ string: String) -> Date? {
        iso8601WithFractionalSeconds.date(from: string) ?? iso8601.date(from: string)
    }

    /// Relative time string like "2h", "3d", "1w", or "Mar 5".
    static func relativeTime(_ dateString: String) -> String {
        guard let date = parse(dateString) else { return "" }
        return relativeTime(date)
    }

    /// Relative time from a `Date` value.
    static func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "now"
        }
        if interval < 3600 {
            return "\(Int(interval / 60))m"
        }
        if interval < 86400 {
            return "\(Int(interval / 3600))h"
        }
        if interval < 604_800 {
            return "\(Int(interval / 86400))d"
        }
        if interval < 2_592_000 {
            return "\(Int(interval / 604_800))w"
        }
        return monthDay.string(from: date)
    }
}

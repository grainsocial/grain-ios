import Foundation

enum DateFormatting {
    /// Produce an ISO 8601 string with fractional seconds (matches JS `toISOString()`).
    static func nowISO() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    /// Parse an ISO 8601 string with or without fractional seconds.
    static func parse(_ string: String) -> Date? {
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    /// Relative time string like "2h", "3d", "1w", or "Mar 5".
    static func relativeTime(_ dateString: String) -> String {
        guard let date = parse(dateString) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604_800 { return "\(Int(interval / 86400))d" }
        if interval < 2_592_000 { return "\(Int(interval / 604_800))w" }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }
}

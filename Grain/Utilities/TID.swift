import Foundation

/// AT Protocol record key — a "timestamp identifier".
///
/// Grain assigns these client-side before a gallery is published rather than
/// letting the PDS pick them. That is what makes a publish safe to repeat: an
/// interrupted upload retried five seconds later writes to the *same* record
/// keys, so it overwrites its own half-finished work instead of leaving a
/// second gallery behind.
///
/// Format is 13 characters of sortable base32 packing a 64-bit value: a zero
/// high bit, 53 bits of microseconds since the UNIX epoch, then a 10-bit clock
/// identifier that keeps two devices writing in the same microsecond apart.
enum TID {
    private static let alphabet = Array("234567abcdefghijklmnopqrstuvwxyz")
    /// Characters that can appear first — anything higher would set the high bit.
    private static let leadingAlphabet = Set("234567abcdefghij")

    private static let lock = NSLock()
    private nonisolated(unsafe) static var lastMicros: UInt64 = 0
    private static let clockID = UInt64.random(in: 0 ..< 1024)

    /// A fresh TID that sorts after every TID this process has already issued,
    /// even if the clock hasn't ticked between two calls.
    static func next() -> String {
        lock.lock()
        let now = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        let micros = max(now, lastMicros + 1)
        lastMicros = micros
        lock.unlock()
        return encode(micros: micros, clockID: clockID)
    }

    static func encode(micros: UInt64, clockID: UInt64) -> String {
        var value = ((micros & 0x1F_FFFF_FFFF_FFFF) << 10) | (clockID & 0x3FF)
        var chars = [Character](repeating: alphabet[0], count: 13)
        for index in stride(from: 12, through: 0, by: -1) {
            chars[index] = alphabet[Int(value & 0x1F)]
            value >>= 5
        }
        return String(chars)
    }

    /// Whether `string` is a syntactically valid record key we could have written.
    static func isValid(_ string: String) -> Bool {
        guard string.count == 13, let first = string.first else { return false }
        return leadingAlphabet.contains(first) && string.allSatisfy { alphabet.contains($0) }
    }
}

extension String {
    /// Returns the string with every digit replaced by "8", reserving the
    /// maximum possible width for any value sharing the same character structure.
    /// Use as a hidden layout proxy alongside the real text.
    var digitWidthProxy: String {
        reduce(into: "") { $0.append(("0" ... "9").contains($1) ? "8" : $1) }
    }
}

import Foundation

extension Int {
    /// Compact count formatting: 1K, 1.2M, etc.
    var compactCount: String {
        if self >= 1_000_000 {
            let v = Double(self) / 1_000_000
            return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))M" : NSString(format: "%.1fM", v) as String
        }
        if self >= 1000 {
            let v = Double(self) / 1000
            return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))K" : NSString(format: "%.1fK", v) as String
        }
        return "\(self)"
    }
}

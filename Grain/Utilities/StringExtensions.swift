extension String {
    /// Returns the string with every digit replaced by "8", reserving the
    /// maximum possible width for any value sharing the same character structure.
    /// Use as a hidden layout proxy alongside the real text.
    var digitWidthProxy: String {
        reduce(into: "") { $0.append(("0" ... "9").contains($1) ? "8" : $1) }
    }
}

import Foundation
import NaturalLanguage

/// Detects whether a caption is in a language the reader probably doesn't read,
/// which drives the "translate" affordance under a gallery description.
///
/// This exists as an actor because `NLLanguageRecognizer` is far too slow to run
/// inline during a scroll: profiling measured 2.6ms average and 13.4ms worst
/// case per call, against a 16.7ms frame budget — a single bad call could drop a
/// frame on its own. Running it off the main actor keeps it out of the way, and
/// memoizing by text means the repeated work disappears too, since the same
/// captions come back every time a card leaves and re-enters the lazy stack.
actor LanguageDetector {
    static let shared = LanguageDetector()

    private var cache: [String: Bool] = [:]

    /// Cap chosen to comfortably cover a long scrolling session without letting
    /// the cache grow unbounded. Cleared wholesale rather than evicting LRU —
    /// a rebuild is cheap now that it's off the main thread.
    private static let cacheLimit = 500

    func isForeign(_ text: String) -> Bool {
        if let cached = cache[text] {
            return cached
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        var result = false
        if let detected = recognizer.dominantLanguage?.rawValue {
            let preferred = Locale.preferredLanguages.first ?? "en"
            result = !preferred.hasPrefix(detected)
        }

        if cache.count >= Self.cacheLimit {
            cache.removeAll(keepingCapacity: true)
        }
        cache[text] = result
        return result
    }
}

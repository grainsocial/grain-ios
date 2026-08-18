import os
import SwiftUI

/// Compiled once rather than per call. Building an `NSRegularExpression` is not
/// cheap, and the regex fallback below compiles four of them — previously on
/// every single body evaluation.
private enum LinkPatterns {
    static let url = try? NSRegularExpression(pattern: #"https?://[^\s<>\[\]()]+"#)
    static let bareDomain = try? NSRegularExpression(
        pattern: #"(?<![/@\w.])([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}(/[^\s<>\[\]()]*)?"#
    )
    static let mention = try? NSRegularExpression(
        pattern: #"@([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"#
    )
    static let hashtag = try? NSRegularExpression(pattern: #"#(\p{L}[\p{L}\p{N}_]*)"#)
}

/// Memoizes regex segmentation, which is pure with respect to `text`.
///
/// Worth caching because the same string gets segmented repeatedly:
/// `ExpandableDescriptionView` renders it up to three times to measure
/// truncation, and cards re-parse from scratch every time they re-enter the
/// lazy stack. Profiling measured 430 parses across only ~108 description cards.
private enum SegmentCache {
    private static let store = OSAllocatedUnfairLock(initialState: [String: [Segment]]())
    private static let limit = 500

    static func segments(for text: String, build: (String) -> [Segment]) -> [Segment] {
        if let cached = store.withLock({ $0[text] }) {
            return cached
        }
        let built = build(text)
        store.withLock { cache in
            if cache.count >= limit {
                cache.removeAll(keepingCapacity: true)
            }
            cache[text] = built
        }
        return built
    }
}

/// Renders text with tappable links, mentions, and hashtags.
/// Uses facets if provided, otherwise falls back to regex parsing.
struct RichTextView: View {
    let text: String
    var facets: [Facet]?
    var font: Font = .subheadline
    var color: Color = .primary
    var onMentionTap: ((String) -> Void)?
    var onHashtagTap: ((String) -> Void)?

    private var attributedString: AttributedString {
        // Only the regex path is cached — it's the expensive one, and it depends
        // on nothing but `text`. Facet segmentation is already cheap and would
        // need the facets in the cache key.
        let segments: [Segment] = if let facets, !facets.isEmpty {
            segmentsFromFacets(text: text, facets: facets)
        } else {
            SegmentCache.segments(for: text) { segmentsFromRegex(text: $0) }
        }

        var result = AttributedString()
        for segment in segments {
            var part: AttributedString
            switch segment {
            case let .plain(str):
                part = AttributedString(str)
                part.foregroundColor = color
            case let .link(str, url):
                part = AttributedString(str)
                if let linkURL = URL(string: url) {
                    part.link = linkURL
                }
                part.foregroundColor = Color.accentColor
            case let .mention(str, did):
                part = AttributedString(str)
                let encoded = did.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? did
                part.link = URL(string: "grain-mention://\(encoded)")
                part.foregroundColor = Color.accentColor
            case let .hashtag(str, tag):
                part = AttributedString(str)
                let encoded = tag.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? tag
                part.link = URL(string: "grain-hashtag://\(encoded)")
                part.foregroundColor = Color.accentColor
            }
            part.font = font
            result.append(part)
        }
        return result
    }

    var body: some View {
        Text(attributedString)
            .tint(Color.accentColor)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "grain-mention" {
                    let did = url.host()?.removingPercentEncoding ?? ""
                    if !did.isEmpty {
                        onMentionTap?(did)
                    }
                    return .handled
                }
                if url.scheme == "grain-hashtag" {
                    let tag = url.host()?.removingPercentEncoding ?? ""
                    if !tag.isEmpty {
                        onHashtagTap?(tag)
                    }
                    return .handled
                }
                // Regular URLs — open in Safari
                return .systemAction
            })
    }

    // MARK: - Facet-based parsing

    private func segmentsFromFacets(text: String, facets: [Facet]) -> [Segment] {
        let utf8 = Array(text.utf8)
        let sorted = facets.sorted { $0.index.byteStart < $1.index.byteStart }
        var segments: [Segment] = []
        var cursor = 0

        for facet in sorted {
            let start = facet.index.byteStart
            let end = min(facet.index.byteEnd, utf8.count)
            guard start >= cursor, end > start else { continue }

            if start > cursor {
                let plain = String(bytes: utf8[cursor ..< start], encoding: .utf8) ?? ""
                segments.append(.plain(plain))
            }

            let slice = String(bytes: utf8[start ..< end], encoding: .utf8) ?? ""
            if let feature = facet.features.first {
                switch feature {
                case let .link(uri):
                    segments.append(.link(slice, url: uri))
                case let .mention(did):
                    segments.append(.mention(slice, did: did))
                case let .tag(tag):
                    segments.append(.hashtag(slice, tag: tag))
                }
            } else {
                segments.append(.plain(slice))
            }
            cursor = end
        }

        if cursor < utf8.count {
            let remaining = String(bytes: utf8[cursor...], encoding: .utf8) ?? ""
            segments.append(.plain(remaining))
        }

        return segments
    }

    // MARK: - Regex fallback

    private struct Match {
        let range: Range<String.Index>
        let segment: Segment
    }

    /// Collects non-overlapping matches of `pattern`, building each segment from
    /// the matched substring. Ranges already claimed by an earlier pattern win,
    /// so call order sets priority.
    private func appendMatches(
        of regex: NSRegularExpression?,
        in text: String,
        to matches: inout [Match],
        segment: (String) -> Segment
    ) {
        guard let regex else { return }
        let nsRange = NSRange(text.startIndex..., in: text)
        for matchResult in regex.matches(in: text, range: nsRange) {
            guard let range = Range(matchResult.range, in: text),
                  !matches.contains(where: { $0.range.overlaps(range) })
            else { continue }
            matches.append(Match(range: range, segment: segment(String(text[range]))))
        }
    }

    private func segmentsFromRegex(text: String) -> [Segment] {
        var matches: [Match] = []
        appendMatches(of: LinkPatterns.url, in: text, to: &matches) { .link($0, url: $0) }
        appendMatches(of: LinkPatterns.bareDomain, in: text, to: &matches) { .link($0, url: "https://\($0)") }
        appendMatches(of: LinkPatterns.mention, in: text, to: &matches) { .mention($0, did: String($0.dropFirst())) }
        appendMatches(of: LinkPatterns.hashtag, in: text, to: &matches) { .hashtag($0, tag: String($0.dropFirst())) }

        matches.sort { $0.range.lowerBound < $1.range.lowerBound }

        var segments: [Segment] = []
        var cursor = text.startIndex

        for match in matches {
            if match.range.lowerBound > cursor {
                segments.append(.plain(String(text[cursor ..< match.range.lowerBound])))
            }
            segments.append(match.segment)
            cursor = match.range.upperBound
        }

        if cursor < text.endIndex {
            segments.append(.plain(String(text[cursor...])))
        }

        return segments
    }
}

private enum Segment {
    case plain(String)
    case link(String, url: String)
    case mention(String, did: String)
    case hashtag(String, tag: String)
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        RichTextView(text: "Plain text with no links.")
        RichTextView(
            text: "Check out @alice.grain.social and the #35mm tag.",
            onMentionTap: { _ in },
            onHashtagTap: { _ in }
        )
        RichTextView(text: "Visit https://grain.social for more.")
    }
    .padding()
    .preferredColorScheme(.dark)
    .tint(Color.accentColor)
}

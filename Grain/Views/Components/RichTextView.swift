import SwiftUI

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
        let segments: [Segment] = if let facets, !facets.isEmpty {
            segmentsFromFacets(text: text, facets: facets)
        } else {
            segmentsFromRegex(text: text)
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
                part.foregroundColor = Color("AccentColor")
            case let .mention(str, did):
                part = AttributedString(str)
                let encoded = did.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? did
                part.link = URL(string: "grain-mention://\(encoded)")
                part.foregroundColor = Color("AccentColor")
            case let .hashtag(str, tag):
                part = AttributedString(str)
                let encoded = tag.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? tag
                part.link = URL(string: "grain-hashtag://\(encoded)")
                part.foregroundColor = Color("AccentColor")
            }
            part.font = font
            result.append(part)
        }
        return result
    }

    var body: some View {
        Text(attributedString)
            .tint(Color("AccentColor"))
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

    private func segmentsFromRegex(text: String) -> [Segment] {
        let urlPattern = #"https?://[^\s<>\[\]()]+"#
        let mentionPattern = #"@([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"#
        let hashtagPattern = #"#([a-zA-Z][a-zA-Z0-9_]*)"#

        struct Match {
            let range: Range<String.Index>
            let segment: Segment
        }

        var matches: [Match] = []

        if let regex = try? NSRegularExpression(pattern: urlPattern) {
            let nsRange = NSRange(text.startIndex..., in: text)
            for matchResult in regex.matches(in: text, range: nsRange) {
                if let range = Range(matchResult.range, in: text) {
                    let str = String(text[range])
                    matches.append(Match(range: range, segment: .link(str, url: str)))
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: mentionPattern) {
            let nsRange = NSRange(text.startIndex..., in: text)
            for matchResult in regex.matches(in: text, range: nsRange) {
                if let range = Range(matchResult.range, in: text) {
                    if matches.contains(where: { $0.range.overlaps(range) }) { continue }
                    let str = String(text[range])
                    matches.append(Match(range: range, segment: .mention(str, did: String(str.dropFirst()))))
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: hashtagPattern) {
            let nsRange = NSRange(text.startIndex..., in: text)
            for matchResult in regex.matches(in: text, range: nsRange) {
                if let range = Range(matchResult.range, in: text) {
                    if matches.contains(where: { $0.range.overlaps(range) }) { continue }
                    let str = String(text[range])
                    matches.append(Match(range: range, segment: .hashtag(str, tag: String(str.dropFirst()))))
                }
            }
        }

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
}

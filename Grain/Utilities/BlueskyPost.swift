import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "BlueskyPost")

struct BlueskyPostOptions {
    let url: String
    let location: (name: String, address: [String: AnyCodable]?)?
    let description: String?
    let images: [(blob: BlobRef, alt: String, width: Int, height: Int)]
}

enum BlueskyPost {

    /// Create a cross-post to Bluesky with images, location, and description.
    /// Mirrors the web client's `createBskyPost()` in `bsky-post.ts`.
    static func create(
        options: BlueskyPostOptions,
        client: XRPCClient,
        repo: String,
        auth: AuthContext
    ) async throws {
        logger.info("Creating Bluesky cross-post for \(options.url)")
        logger.info("  images: \(options.images.count), location: \(options.location?.name ?? "none"), description: \(options.description ?? "none")")

        // 1. Build post text (same format as web)
        let postText = buildPostText(
            url: options.url,
            location: options.location,
            description: options.description
        )
        logger.info("  postText: \(postText)")

        // 2. Parse facets for URLs, mentions, and hashtags (same as web)
        let facets = await parseTextToFacets(postText)
        logger.info("  facets: \(facets.count)")

        // 3. Build image embed from already-uploaded blob refs
        // Web client uploads separately, but blob refs are repo-scoped and reusable
        var imageEmbeds: [[String: AnyCodable]] = []
        for img in options.images.prefix(4) {
            let blobDict: [String: AnyCodable] = [
                "$type": AnyCodable(img.blob.type ?? "blob"),
                "ref": AnyCodable(["$link": AnyCodable(img.blob.ref?.link ?? "")] as [String: AnyCodable]),
                "mimeType": AnyCodable(img.blob.mimeType ?? "image/jpeg"),
                "size": AnyCodable(img.blob.size ?? 0)
            ]
            imageEmbeds.append([
                "image": AnyCodable(blobDict),
                "alt": AnyCodable(img.alt),
                "aspectRatio": AnyCodable([
                    "width": AnyCodable(img.width),
                    "height": AnyCodable(img.height)
                ] as [String: AnyCodable])
            ])
            logger.info("  image blob: type=\(img.blob.type ?? "nil"), ref=\(img.blob.ref?.link ?? "nil"), size=\(img.blob.size ?? 0)")
        }

        // 4. Build the record — must match web's structure exactly:
        //    { text, facets?, embed?, tags: ["grainsocial"], createdAt }
        var record: [String: AnyCodable] = [
            "text": AnyCodable(postText),
            "tags": AnyCodable(["grainsocial"] as [String]),
            "createdAt": AnyCodable(DateFormatting.nowISO())
        ]

        if !facets.isEmpty {
            let facetDicts: [[String: AnyCodable]] = facets.map { facet in
                let featureDicts: [[String: AnyCodable]] = facet.features.map { feature in
                    switch feature {
                    case .link(let uri):
                        return ["$type": AnyCodable("app.bsky.richtext.facet#link"), "uri": AnyCodable(uri)]
                    case .mention(let did):
                        return ["$type": AnyCodable("app.bsky.richtext.facet#mention"), "did": AnyCodable(did)]
                    case .tag(let tag):
                        return ["$type": AnyCodable("app.bsky.richtext.facet#tag"), "tag": AnyCodable(tag)]
                    }
                }
                return [
                    "index": AnyCodable([
                        "byteStart": AnyCodable(facet.index.byteStart),
                        "byteEnd": AnyCodable(facet.index.byteEnd)
                    ] as [String: AnyCodable]),
                    "features": AnyCodable(featureDicts as [[String: AnyCodable]])
                ]
            }
            record["facets"] = AnyCodable(facetDicts as [[String: AnyCodable]])
        }

        if !imageEmbeds.isEmpty {
            record["embed"] = AnyCodable([
                "$type": AnyCodable("app.bsky.embed.images"),
                "images": AnyCodable(imageEmbeds as [[String: AnyCodable]])
            ] as [String: AnyCodable])
        }

        // 5. Log the full JSON for debugging
        if let jsonData = try? JSONEncoder().encode(AnyCodable(record)),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            logger.info("  record JSON: \(jsonStr)")
        }

        // 6. Create the record
        logger.info("  calling dev.hatk.createRecord with collection=app.bsky.feed.post, repo=\(repo)")
        let result = try await client.createRecord(
            collection: "app.bsky.feed.post",
            repo: repo,
            record: AnyCodable(record),
            auth: auth
        )

        logger.info("Bluesky cross-post created: uri=\(result.uri ?? "nil"), cid=\(result.cid ?? "nil")")
    }

    // MARK: - Text Building

    /// Build post text matching web format:
    /// 📍 Location Name
    /// Locality, Region, Country
    ///
    /// Description (truncated to fit 300 graphemes)
    ///
    /// https://grain.social/profile/did/gallery/rkey
    ///
    /// #grainsocial
    static func buildPostText(
        url: String,
        location: (name: String, address: [String: AnyCodable]?)?,
        description: String?
    ) -> String {
        var lines: [String] = []

        if let location {
            lines.append("📍 \(location.name)")
            if let address = location.address {
                var parts: [String] = []
                if let locality = address["locality"]?.stringValue { parts.append(locality) }
                if let region = address["region"]?.stringValue { parts.append(region) }
                if let country = address["country"]?.stringValue { parts.append(country) }
                if !parts.isEmpty {
                    lines.append(parts.joined(separator: ", "))
                }
            }
        }

        // Lexicon constraints: maxGraphemes=300, maxLength=3000 bytes
        // Swift .count is grapheme count (same as Intl.Segmenter)
        let suffix = "\n\n\(url)\n\n#grainsocial"
        let prefixText = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        let overheadGraphemes = (prefixText + suffix).count
        let overheadBytes = (prefixText + suffix).utf8.count
        let maxDescGraphemes = 300 - overheadGraphemes
        let maxDescBytes = 3000 - overheadBytes

        if let desc = description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            var truncated = desc
            // Truncate to fit grapheme limit
            if truncated.count > maxDescGraphemes {
                truncated = String(truncated.prefix(max(0, maxDescGraphemes - 1))) + "…"
            }
            // Truncate further to fit byte limit
            while truncated.utf8.count > maxDescBytes && !truncated.isEmpty {
                truncated = String(truncated.dropLast(2)) + "…"
            }
            if !truncated.isEmpty {
                lines.append("")
                lines.append(truncated)
            }
        }

        lines.append("")
        lines.append(url)
        lines.append("")
        lines.append("#grainsocial")

        return lines.joined(separator: "\n")
    }

    // MARK: - Facet Parsing

    /// Parse URLs, mentions, and hashtags into Bluesky facets with byte offsets.
    /// Matches web's `parseTextToFacets()` in `rich-text.ts` — same regex patterns,
    /// same priority order (URLs > mentions > hashtags), same byte offset calculation.
    static func parseTextToFacets(_ text: String) async -> [Facet] {
        guard !text.isEmpty else { return [] }

        var facets: [Facet] = []
        var claimed = Set<Int>()

        func byteOffset(for charIndex: String.Index) -> Int {
            text.utf8.distance(from: text.utf8.startIndex, to: charIndex)
        }

        func isRangeClaimed(_ start: Int, _ end: Int) -> Bool {
            for i in start..<end where claimed.contains(i) { return true }
            return false
        }

        func claimRange(_ start: Int, _ end: Int) {
            for i in start..<end { claimed.insert(i) }
        }

        let nsText = text as NSString

        // URLs (highest priority, same as web)
        let urlPattern = try! NSRegularExpression(pattern: #"https?://[^\s<>\[\]()]+"#)
        for match in urlPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let range = Range(match.range, in: text) else { continue }
            let byteStart = byteOffset(for: range.lowerBound)
            let byteEnd = byteOffset(for: range.upperBound)
            guard !isRangeClaimed(byteStart, byteEnd) else { continue }
            claimRange(byteStart, byteEnd)
            facets.append(Facet(
                index: Facet.ByteSlice(byteStart: byteStart, byteEnd: byteEnd),
                features: [.link(uri: String(text[range]))]
            ))
        }

        // Mentions (same regex as web — resolve handle to DID via public Bluesky API)
        let mentionPattern = try! NSRegularExpression(
            pattern: #"@([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"#
        )
        for match in mentionPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let range = Range(match.range, in: text) else { continue }
            let byteStart = byteOffset(for: range.lowerBound)
            let byteEnd = byteOffset(for: range.upperBound)
            guard !isRangeClaimed(byteStart, byteEnd) else { continue }

            let fullMatch = String(text[range])
            let handle = String(fullMatch.dropFirst()) // remove @
            if let did = await resolveHandle(handle) {
                claimRange(byteStart, byteEnd)
                facets.append(Facet(
                    index: Facet.ByteSlice(byteStart: byteStart, byteEnd: byteEnd),
                    features: [.mention(did: did)]
                ))
            }
        }

        // Hashtags (same regex as web)
        let hashtagPattern = try! NSRegularExpression(pattern: #"#([a-zA-Z][a-zA-Z0-9_]*)"#)
        for match in hashtagPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let fullRange = Range(match.range, in: text),
                  let tagRange = Range(match.range(at: 1), in: text) else { continue }
            let byteStart = byteOffset(for: fullRange.lowerBound)
            let byteEnd = byteOffset(for: fullRange.upperBound)
            guard !isRangeClaimed(byteStart, byteEnd) else { continue }
            claimRange(byteStart, byteEnd)
            facets.append(Facet(
                index: Facet.ByteSlice(byteStart: byteStart, byteEnd: byteEnd),
                features: [.tag(tag: String(text[tagRange]))]
            ))
        }

        facets.sort { $0.index.byteStart < $1.index.byteStart }
        return facets
    }

    // MARK: - Handle Resolution

    /// Resolve a Bluesky handle to a DID via the public API.
    /// Same as web's `resolveHandle()` in `bsky-post.ts`.
    private static func resolveHandle(_ handle: String) async -> String? {
        guard let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://public.api.bsky.app/xrpc/com.atproto.identity.resolveHandle?handle=\(encoded)") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return nil }
            let json = try JSONDecoder().decode([String: String].self, from: data)
            return json["did"]
        } catch {
            logger.debug("Failed to resolve handle @\(handle): \(error)")
            return nil
        }
    }
}

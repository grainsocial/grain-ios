import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "BlueskyPost")

struct BlueskyPostOptions {
    let url: String
    let title: String?
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
            title: options.title,
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
                "size": AnyCodable(img.blob.size ?? 0),
            ]
            imageEmbeds.append([
                "image": AnyCodable(blobDict),
                "alt": AnyCodable(img.alt),
                "aspectRatio": AnyCodable([
                    "width": AnyCodable(img.width),
                    "height": AnyCodable(img.height),
                ] as [String: AnyCodable]),
            ])
            logger.info("  image blob: type=\(img.blob.type ?? "nil"), ref=\(img.blob.ref?.link ?? "nil"), size=\(img.blob.size ?? 0)")
        }

        // 4. Build the record — must match web's structure exactly:
        //    { text, facets?, embed?, tags: ["grainsocial"], createdAt }
        var record: [String: AnyCodable] = [
            "text": AnyCodable(postText),
            "tags": AnyCodable(["grainsocial"] as [String]),
            "createdAt": AnyCodable(DateFormatting.nowISO()),
        ]

        if !facets.isEmpty {
            let facetDicts: [[String: AnyCodable]] = facets.map { facet in
                let featureDicts: [[String: AnyCodable]] = facet.features.map { feature in
                    switch feature {
                    case let .link(uri):
                        ["$type": AnyCodable("app.bsky.richtext.facet#link"), "uri": AnyCodable(uri)]
                    case let .mention(did):
                        ["$type": AnyCodable("app.bsky.richtext.facet#mention"), "did": AnyCodable(did)]
                    case let .tag(tag):
                        ["$type": AnyCodable("app.bsky.richtext.facet#tag"), "tag": AnyCodable(tag)]
                    }
                }
                return [
                    "index": AnyCodable([
                        "byteStart": AnyCodable(facet.index.byteStart),
                        "byteEnd": AnyCodable(facet.index.byteEnd),
                    ] as [String: AnyCodable]),
                    "features": AnyCodable(featureDicts as [[String: AnyCodable]]),
                ]
            }
            record["facets"] = AnyCodable(facetDicts as [[String: AnyCodable]])
        }

        if !imageEmbeds.isEmpty {
            record["embed"] = AnyCodable([
                "$type": AnyCodable("app.bsky.embed.images"),
                "images": AnyCodable(imageEmbeds as [[String: AnyCodable]]),
            ] as [String: AnyCodable])
        }

        // 5. Log the full JSON for debugging
        if let jsonData = try? JSONEncoder().encode(AnyCodable(record)),
           let jsonStr = String(data: jsonData, encoding: .utf8)
        {
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

    /// Build post text:
    /// Title, description…
    ///
    /// 📍 Location Name, Region, Country
    ///
    /// #GrainSocial see full post here (link)
    static func buildPostText(
        url: String,
        title: String?,
        location: (name: String, address: [String: AnyCodable]?)?,
        description: String?
    ) -> String {
        // Build location line (shortened: name, region, country)
        var locationLine: String?
        if let location {
            var parts = [location.name]
            if let address = location.address {
                if let region = address["region"]?.stringValue { parts.append(region) }
                if let country = address["country"]?.stringValue { parts.append(country) }
            }
            locationLine = "📍 \(parts.joined(separator: ", "))"
        }

        // Build suffix (location + hashtag + link)
        var suffixLines: [String] = []
        if let locationLine {
            suffixLines.append("")
            suffixLines.append(locationLine)
        }
        suffixLines.append("")
        suffixLines.append("#GrainSocial \(url)")
        let suffix = suffixLines.joined(separator: "\n")

        // Lexicon constraints: maxGraphemes=300, maxLength=3000 bytes
        let overheadGraphemes = suffix.count
        let overheadBytes = suffix.utf8.count
        let maxContentGraphemes = 300 - overheadGraphemes
        let maxContentBytes = 3000 - overheadBytes

        // Build title + description content
        var content = ""
        let titleText = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let descText = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !titleText.isEmpty, !descText.isEmpty {
            content = "\(titleText), \(descText)"
        } else if !titleText.isEmpty {
            content = titleText
        } else if !descText.isEmpty {
            content = descText
        }

        // Truncate to fit
        if !content.isEmpty {
            if content.count > maxContentGraphemes {
                content = String(content.prefix(max(0, maxContentGraphemes - 1))) + "…"
            }
            while content.utf8.count > maxContentBytes, !content.isEmpty {
                content = String(content.dropLast(2)) + "…"
            }
        }

        var lines: [String] = []
        if !content.isEmpty { lines.append(content) }
        lines.append(contentsOf: suffixLines)

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
            for i in start ..< end where claimed.contains(i) {
                return true
            }
            return false
        }

        func claimRange(_ start: Int, _ end: Int) {
            for i in start ..< end {
                claimed.insert(i)
            }
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
        let hashtagPattern = try! NSRegularExpression(pattern: #"#(\p{L}[\p{L}\p{N}_]*)"#)
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
              let url = URL(string: "https://public.api.bsky.app/xrpc/com.atproto.identity.resolveHandle?handle=\(encoded)")
        else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode) else { return nil }
            let json = try JSONDecoder().decode([String: String].self, from: data)
            return json["did"]
        } catch {
            logger.debug("Failed to resolve handle @\(handle): \(error)")
            return nil
        }
    }
}

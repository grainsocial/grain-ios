import Foundation
import os
import UIKit

private let logger = Logger(subsystem: "social.grain.grain", category: "BlueskyPost")

/// Facet regexes, compiled once. The patterns are literals so they can't
/// actually fail to compile — `try?` rather than `try!` keeps the linter happy,
/// and a nil here just means that facet type is skipped.
private enum FacetPattern {
    static let url = try? NSRegularExpression(pattern: #"https?://[^\s<>\[\]()]+"#)
    static let mention = try? NSRegularExpression(
        pattern: #"@([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"#
    )
    static let hashtag = try? NSRegularExpression(pattern: #"#(\p{L}[\p{L}\p{N}_]*)"#)
}

struct BlueskyPostOptions {
    let url: String
    let title: String?
    let images: [(blob: BlobRef, alt: String, width: Int, height: Int)]
    /// The gallery's OpenGraph card, drawn by grain-serve: the thumb of the
    /// link card a post with more than four photos embeds instead of images.
    var cardURL: URL?
}

enum BlueskyPost {
    /// Bluesky embeds at most four images; a gallery with more becomes a link card.
    static let maxEmbeddedImages = 4

    /// Create a cross-post to Bluesky: the title and link, with the photos.
    /// Mirrors the web client's `createBskyPost()` in `bsky-post.ts`.
    ///
    /// Up to four photos are embedded as images. A gallery with more is
    /// embedded as a link card to it, its thumb the gallery's OpenGraph card
    /// (`cardURL`), so the post neither drops photos silently nor misleads.
    ///
    /// Pass `rkey` when the caller might run this more than once — a resumed
    /// gallery publish, say. With a record key of our own the write becomes an
    /// overwrite instead of a second post on the user's timeline.
    static func create(
        options: BlueskyPostOptions,
        client: XRPCClient,
        repo: String,
        auth: AuthContext,
        rkey: String? = nil,
        createdAt: String = DateFormatting.nowISO()
    ) async throws {
        logger.info("Creating Bluesky cross-post for \(options.url)")
        logger.info("  images: \(options.images.count)")

        // 1. Build post text (same format as web)
        let postText = buildPostText(url: options.url, title: options.title)
        logger.info("  postText: \(postText)")

        // 2. Parse facets for URLs, mentions, and hashtags (same as web)
        let facets = await parseTextToFacets(postText)
        logger.info("  facets: \(facets.count)")

        // 3. Build the embed. Image blob refs are repo-scoped and reusable, so
        // the photos the gallery already uploaded are embedded as they are.
        let embed: [String: AnyCodable]? = if options.images.count > maxEmbeddedImages {
            await externalEmbed(options: options, client: client, auth: auth)
        } else if options.images.isEmpty {
            nil
        } else {
            imagesEmbed(options.images)
        }

        // 4. Build the record — must match web's structure exactly:
        //    { text, facets?, embed?, tags: ["grainsocial"], createdAt }
        var record: [String: AnyCodable] = [
            "text": AnyCodable(postText),
            "tags": AnyCodable(["grainsocial"] as [String]),
            "createdAt": AnyCodable(createdAt),
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

        if let embed {
            record["embed"] = AnyCodable(embed)
        }

        // 5. Log the full JSON for debugging
        if let jsonData = try? JSONEncoder().encode(AnyCodable(record)),
           let jsonStr = String(data: jsonData, encoding: .utf8)
        {
            logger.info("  record JSON: \(jsonStr)")
        }

        // 6. Write the record
        let result: CreateRecordResponse
        if let rkey {
            logger.info("  calling com.atproto.repo.putRecord with collection=app.bsky.feed.post, repo=\(repo), rkey=\(rkey)")
            result = try await client.putRecord(
                collection: "app.bsky.feed.post",
                rkey: rkey,
                record: AnyCodable(record),
                repo: repo,
                auth: auth
            )
        } else {
            logger.info("  calling com.atproto.repo.createRecord with collection=app.bsky.feed.post, repo=\(repo)")
            result = try await client.createRecord(
                collection: "app.bsky.feed.post",
                repo: repo,
                record: AnyCodable(record),
                auth: auth
            )
        }

        logger.info("Bluesky cross-post created: uri=\(result.uri ?? "nil"), cid=\(result.cid ?? "nil")")
    }

    // MARK: - Embeds

    private static func blobDict(_ blob: BlobRef) -> [String: AnyCodable] {
        [
            "$type": AnyCodable(blob.type ?? "blob"),
            "ref": AnyCodable(["$link": AnyCodable(blob.ref?.link ?? "")] as [String: AnyCodable]),
            "mimeType": AnyCodable(blob.mimeType ?? "image/jpeg"),
            "size": AnyCodable(blob.size ?? 0),
        ]
    }

    private static func imagesEmbed(_ images: [(blob: BlobRef, alt: String, width: Int, height: Int)]) -> [String: AnyCodable] {
        let embedded: [[String: AnyCodable]] = images.map { img in
            [
                "image": AnyCodable(blobDict(img.blob)),
                "alt": AnyCodable(img.alt),
                "aspectRatio": AnyCodable([
                    "width": AnyCodable(img.width),
                    "height": AnyCodable(img.height),
                ] as [String: AnyCodable]),
            ]
        }
        return [
            "$type": AnyCodable("app.bsky.embed.images"),
            "images": AnyCodable(embedded as [[String: AnyCodable]]),
        ]
    }

    /// A link card to the gallery. Its thumb is the gallery's OpenGraph card,
    /// re-encoded as JPEG under Bluesky's 1 MB cap for external thumbs; when
    /// the card can't be fetched or uploaded the card goes without a thumb
    /// rather than failing the cross-post.
    private static func externalEmbed(options: BlueskyPostOptions, client: XRPCClient, auth: AuthContext) async -> [String: AnyCodable] {
        let title = options.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var external: [String: AnyCodable] = [
            "uri": AnyCodable(options.url),
            "title": AnyCodable(title.isEmpty ? "Gallery on Grain" : title),
            "description": AnyCodable("\(options.images.count) photos on Grain"),
        ]
        if let cardURL = options.cardURL {
            do {
                let (data, response) = try await NetworkEnvironment.session.data(from: cardURL)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                      let image = UIImage(data: data)
                else {
                    throw URLError(.badServerResponse)
                }
                let (jpeg, _) = ImageProcessing.resizeImage(image, maxDimension: 1200, maxBytes: 900_000)
                let upload = try await client.uploadBlob(data: jpeg, mimeType: "image/jpeg", auth: auth)
                external["thumb"] = AnyCodable(blobDict(upload.blob))
            } catch {
                logger.error("Bluesky cross-post card thumb failed: \(error.localizedDescription)")
            }
        }
        return [
            "$type": AnyCodable("app.bsky.embed.external"),
            "external": AnyCodable(external),
        ]
    }

    // MARK: - Text Building

    /// Build post text, the same as web's:
    ///
    ///     Title
    ///
    ///     #GrainSocial (link)
    ///
    /// or just the hashtag and link with no title.
    static func buildPostText(url: String, title: String?) -> String {
        let suffix = "#GrainSocial \(url)"
        let separator = "\n\n"

        // Lexicon constraints: maxGraphemes=300, maxLength=3000 bytes.
        // The budget has to pay for the newlines that join the title to the
        // suffix as well as the suffix itself, or a truncated post overruns.
        let maxContentGraphemes = 300 - suffix.count - separator.count
        let maxContentBytes = 3000 - suffix.utf8.count - separator.utf8.count

        var content = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Truncate to fit. A budget too small to hold even the ellipsis means
        // the suffix alone fills the post, so the title is dropped entirely.
        if !content.isEmpty {
            if maxContentGraphemes < 1 || maxContentBytes < 3 {
                content = ""
            } else {
                if content.count > maxContentGraphemes {
                    content = String(content.prefix(maxContentGraphemes - 1)) + "…"
                }
                while content.utf8.count > maxContentBytes, content.count > 1 {
                    content = String(content.dropLast(2)) + "…"
                }
            }
        }

        return content.isEmpty ? suffix : content + separator + suffix
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
        for match in FacetPattern.url?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? [] {
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
        for match in FacetPattern.mention?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? [] {
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
        for match in FacetPattern.hashtag?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? [] {
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
            let (data, response) = try await NetworkEnvironment.session.data(from: url)
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

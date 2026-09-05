import Foundation
import UIKit

/// Everything the composer has settled on before posting a story.
struct StoryDraft {
    struct Location {
        let h3: String
        let name: String
        let address: [String: AnyCodable]?
    }

    let image: UIImage
    var location: Location?
    var labels: Set<String> = []
    var postToBluesky = false

    /// The `social.grain.story` record for an already-uploaded blob.
    ///
    /// Pure so the shape can be pinned by a test without a server: the media
    /// and aspect ratio always, location and address only when set, and the
    /// self-label wrapper only when there is at least one label.
    func record(blob: BlobRef, size: CGSize, createdAt: String) -> [String: AnyCodable] {
        let blobDict: [String: AnyCodable] = [
            "$type": AnyCodable(blob.type ?? "blob"),
            "ref": AnyCodable(["$link": AnyCodable(blob.ref?.link ?? "")] as [String: AnyCodable]),
            "mimeType": AnyCodable(blob.mimeType ?? "image/jpeg"),
            "size": AnyCodable(blob.size ?? 0),
        ]

        var record: [String: AnyCodable] = [
            "media": AnyCodable(blobDict),
            "aspectRatio": AnyCodable([
                "width": AnyCodable(Int(size.width)),
                "height": AnyCodable(Int(size.height)),
            ] as [String: AnyCodable]),
            "createdAt": AnyCodable(createdAt),
        ]

        if let location {
            record["location"] = AnyCodable([
                "value": AnyCodable(location.h3),
                "name": AnyCodable(location.name),
            ] as [String: AnyCodable])
            if let address = location.address {
                record["address"] = AnyCodable(address)
            }
        }
        if !labels.isEmpty {
            let values = labels.sorted().map { ["val": AnyCodable($0)] as [String: AnyCodable] }
            record["labels"] = AnyCodable([
                "$type": AnyCodable("com.atproto.label.defs#selfLabels"),
                "values": AnyCodable(values as [[String: AnyCodable]]),
            ] as [String: AnyCodable])
        }
        return record
    }
}

/// Publishing `social.grain.story` records.
///
/// This used to be inline in the composer, where the only test that could
/// reach it was a render. Uploading, writing the record, and the best-effort
/// Bluesky cross-post now live here so each step can be pinned on its own.
enum StoryService {
    static let collection = "social.grain.story"

    /// Uploads the photo, writes the story, and cross-posts if asked.
    ///
    /// The cross-post runs after the story is already live and is deliberately
    /// best-effort: Bluesky being down must not fail a story the PDS accepted.
    @discardableResult
    static func publish(
        _ draft: StoryDraft,
        client: XRPCClient,
        repo: String,
        auth: AuthContext
    ) async throws -> CreateRecordResponse {
        let (resized, size) = ImageProcessing.resizeImage(draft.image, maxDimension: 2000, maxBytes: 900_000)
        let upload = try await client.uploadBlob(data: resized, mimeType: "image/jpeg", auth: auth)

        let result = try await client.createRecord(
            collection: collection,
            repo: repo,
            record: AnyCodable(draft.record(blob: upload.blob, size: size, createdAt: DateFormatting.nowISO())),
            auth: auth
        )

        if draft.postToBluesky, let uri = result.uri {
            let rkey = uri.split(separator: "/").last.map(String.init) ?? ""
            let options = BlueskyPostOptions(
                url: "https://grain.social/profile/\(repo)/story/\(rkey)",
                title: nil,
                location: draft.location.map { ($0.name, $0.address) },
                description: nil,
                images: [(blob: upload.blob, alt: "", width: Int(size.width), height: Int(size.height))]
            )
            do {
                try await BlueskyPost.create(options: options, client: client, repo: repo, auth: auth)
            } catch {
                // The story is live; a failed cross-post must not undo that.
            }
        }
        return result
    }

    /// Resolves credentials, publishes, and reports the outcome.
    ///
    /// Callers get a `Result` because there is no sensible default for a failed
    /// post — the composer has to say something.
    @MainActor
    static func publish(
        _ draft: StoryDraft,
        client: XRPCClient,
        auth: AuthManager
    ) async -> Result<Void, Error> {
        guard let context = await auth.authContext(), let repo = auth.userDID else {
            return .failure(StoryPublishError.notSignedIn)
        }
        do {
            try await publish(draft, client: client, repo: repo, auth: context)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// What the composer shows for a failed publish. A rejected request keeps
    /// the status and body, which is what makes a server complaint diagnosable.
    static func message(for error: Error) -> String {
        if case let XRPCError.httpError(statusCode, body) = error {
            let bodyText = body.flatMap { String(data: $0, encoding: .utf8) } ?? "no body"
            return "HTTP \(statusCode): \(bodyText)"
        }
        return error.localizedDescription
    }
}

/// The one failure `StoryService.publish` can hit before it reaches the network.
enum StoryPublishError: LocalizedError, Equatable {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "You're signed out. Sign in and try again."
        }
    }
}

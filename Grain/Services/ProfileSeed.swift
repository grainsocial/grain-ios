import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "ProfileSeed")

/// A grain profile made from the account's Bluesky profile once it signs
/// in, as grain-serve makes one for the web (`login/profile.rs`). The app
/// signs in at the account's own PDS, so grain-serve never sees the
/// sign-in: the app does it, in the background, so a sign-in never waits
/// on it and never fails by it.
///
/// An account whose `social.grain.actor.profile` has a `displayName` is
/// left as it is. Otherwise its `app.bsky.actor.profile` gives the grain
/// profile its `displayName`, `description` and `avatar` (the blob as the
/// Bluesky profile names it), with the `createdAt` of the grain profile
/// there is, or now. One there is is put over, swapped on its CID; else one
/// is made at `self`. Both are read from the account's PDS, and the write
/// is then indexed.
enum ProfileSeed {
    static let grain = "social.grain.actor.profile"
    static let bluesky = "app.bsky.actor.profile"

    /// What `seed` did.
    enum Outcome: Equatable {
        /// The grain profile has a name already.
        case named
        /// There is no Bluesky profile to make one from.
        case noBluesky
        /// A grain profile was made.
        case made
        /// The grain profile there was was put over.
        case put
    }

    /// Seed the profile, logging only how it failed.
    static func run(client: XRPCClient, auth: AuthContext) async {
        do {
            let outcome = try await seed(client: client, auth: auth)
            logger.info("profile seed: \(String(describing: outcome), privacy: .public)")
        } catch {
            logger.info("seeding a profile from Bluesky failed: \(error)")
        }
    }

    static func seed(client: XRPCClient, auth: AuthContext) async throws -> Outcome {
        let existing = try await read(grain, client: client, auth: auth)
        if let name = existing?.value?.dictValue?["displayName"]?.stringValue, !name.isEmpty {
            return .named
        }
        guard let bsky = try await read(bluesky, client: client, auth: auth)?.value?.dictValue else {
            return .noBluesky
        }
        let record = AnyCodable(fromBluesky(bsky, grain: existing?.value?.dictValue))
        if let existing {
            _ = try await client.putRecord(collection: grain, rkey: "self", record: record, swapRecord: existing.cid, auth: auth)
            return .put
        }
        _ = try await client.createRecord(collection: grain, repo: auth.did, rkey: "self", record: record, auth: auth)
        return .made
    }

    /// The grain profile `bsky`, a Bluesky profile, makes: its name,
    /// description and avatar where it has them, made when `grain`, the
    /// grain profile there is, says it was, or now.
    static func fromBluesky(_ bsky: [String: AnyCodable], grain: [String: AnyCodable]?, now: String = DateFormatting.nowISO()) -> [String: AnyCodable] {
        let created = grain?["createdAt"]?.stringValue ?? now
        var record: [String: AnyCodable] = ["$type": AnyCodable(Self.grain), "createdAt": AnyCodable(created)]
        for key in ["displayName", "description"] {
            if let text = bsky[key]?.stringValue, !text.isEmpty {
                record[key] = AnyCodable(text)
            }
        }
        if let avatar = bsky["avatar"], avatar.dictValue != nil {
            record["avatar"] = avatar
        }
        return record
    }

    /// The account's `collection/self`, or nil if its PDS has none.
    private static func read(_ collection: String, client: XRPCClient, auth: AuthContext) async throws -> GetRecordResponse? {
        do {
            return try await client.getRecord(uri: "at://\(auth.did)/\(collection)/self", auth: auth)
        } catch let XRPCError.httpError(_, body) where isNotFound(body) {
            return nil
        }
    }

    /// Whether an answer says there is no such record: atproto's
    /// `RecordNotFound`, which a PDS answers with a 400.
    static func isNotFound(_ body: Data?) -> Bool {
        struct Refusal: Decodable { let error: String? }
        return body.flatMap { try? JSONDecoder().decode(Refusal.self, from: $0) }?.error == "RecordNotFound"
    }
}

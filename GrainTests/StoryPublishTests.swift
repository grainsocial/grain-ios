import CryptoKit
import Foundation
@testable import Grain
import Testing
import UIKit

/// Records every request the publish makes.
private final class PublishLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(path: String, body: Data?)] = []

    func record(path: String, body: Data?) {
        lock.withLock { entries.append((path, body)) }
    }

    func count(_ nsid: String) -> Int {
        lock.withLock { entries.count { $0.path.hasSuffix(nsid) } }
    }

    func paths() -> [String] {
        lock.withLock { entries.map(\.path) }
    }

    func bodies(_ nsid: String) -> [[String: Any]] {
        lock.withLock {
            entries
                .filter { $0.path.hasSuffix(nsid) }
                .compactMap(\.body)
                .compactMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        }
    }
}

private func bodyData(of request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let size = 8192
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: size)
        guard read > 0 else { break }
        data.append(buffer, count: read)
    }
    return data
}

/// A small but real image, so the resize and JPEG encode have bytes to work on.
private func makeImage(width: CGFloat = 40, height: CGFloat = 30) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
        UIColor.orange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

private let uploadedBlob = BlobRef(
    type: "blob",
    ref: BlobRef.BlobLink(link: "bafyuploaded"),
    mimeType: "image/jpeg",
    size: 1234
)

// MARK: - The record

/// The shape of a `social.grain.story` record, which used to be assembled
/// inline in the composer where nothing could look at it.
struct StoryRecordTests {
    private let size = CGSize(width: 1500, height: 2000)

    /// The record is only ever seen by the PDS as JSON, so read it back the
    /// way the server would rather than reaching into `AnyCodable`.
    private func asJSON(_ record: [String: AnyCodable]) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func theRecordCarriesTheMediaAspectRatioAndTimestamp() throws {
        let draft = StoryDraft(image: makeImage())

        let record = try asJSON(draft.record(blob: uploadedBlob, size: size, createdAt: "2026-09-05T12:00:00Z"))

        let media = try #require(record["media"] as? [String: Any])
        #expect(media["mimeType"] as? String == "image/jpeg")
        #expect(media["size"] as? Int == 1234)
        #expect((media["ref"] as? [String: Any])?["$link"] as? String == "bafyuploaded")

        let ratio = try #require(record["aspectRatio"] as? [String: Any])
        #expect(ratio["width"] as? Int == 1500)
        #expect(ratio["height"] as? Int == 2000)
        #expect(record["createdAt"] as? String == "2026-09-05T12:00:00Z")
    }

    @Test func aLocationIsWrittenAsItsCellAndNameWithTheAddressBeside() throws {
        var draft = StoryDraft(image: makeImage())
        draft.location = StoryDraft.Location(
            h3: "8a2a1072b59ffff",
            name: "Lisboa",
            address: ["country": AnyCodable("Portugal")]
        )

        let record = try asJSON(draft.record(blob: uploadedBlob, size: size, createdAt: "now"))

        let location = try #require(record["location"] as? [String: Any])
        #expect(location["value"] as? String == "8a2a1072b59ffff")
        #expect(location["name"] as? String == "Lisboa")
        #expect((record["address"] as? [String: Any])?["country"] as? String == "Portugal")
    }

    /// A location without a reverse-geocoded address must not write an empty
    /// address object — the field is optional in the lexicon, not nullable.
    @Test func aLocationWithoutAnAddressWritesNoAddressKey() throws {
        var draft = StoryDraft(image: makeImage())
        draft.location = StoryDraft.Location(h3: "8a2a1072b59ffff", name: "Lisboa", address: nil)

        let record = try asJSON(draft.record(blob: uploadedBlob, size: size, createdAt: "now"))

        #expect(record["location"] != nil)
        #expect(record["address"] == nil)
    }

    @Test func noLocationMeansNoLocationKeys() throws {
        let record = try asJSON(StoryDraft(image: makeImage()).record(blob: uploadedBlob, size: size, createdAt: "now"))

        #expect(record["location"] == nil)
        #expect(record["address"] == nil)
    }

    @Test func labelsAreWrappedAsSelfLabels() throws {
        var draft = StoryDraft(image: makeImage())
        draft.labels = ["sexual", "nudity"]

        let record = try asJSON(draft.record(blob: uploadedBlob, size: size, createdAt: "now"))

        let labels = try #require(record["labels"] as? [String: Any])
        #expect(labels["$type"] as? String == "com.atproto.label.defs#selfLabels")
        let values = try #require(labels["values"] as? [[String: Any]])
        // Sorted, so the record is stable between two posts with the same set.
        #expect(values.map { $0["val"] as? String } == ["nudity", "sexual"])
    }

    /// An empty self-labels wrapper is a different thing from no labels, and
    /// the appview treats it as one.
    @Test func noLabelsMeansNoLabelsKey() throws {
        let record = try asJSON(StoryDraft(image: makeImage()).record(blob: uploadedBlob, size: size, createdAt: "now"))

        #expect(record["labels"] == nil)
    }
}

// MARK: - Publishing

/// Publishing a story: upload, write, and the best-effort Bluesky cross-post.
@MainActor
struct StoryPublishTests {
    private let log = PublishLog()
    private let client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
    private let context = AuthContext(accessToken: "test-token", dpop: DPoP(privateKey: P256.Signing.PrivateKey()))

    /// A server that accepts everything. `uploadStatus` and `blueskyStatus`
    /// let a test make one step fail.
    ///
    /// `nonisolated`, because the handler runs on the URL loading thread and a
    /// closure written inside a `@MainActor` type would otherwise inherit its
    /// isolation and trap there.
    private nonisolated func serve(uploadStatus: Int = 200, blueskyStatus: Int = 200) {
        let log = log
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let body = bodyData(of: request)
            log.record(path: path, body: body)

            func respond(_ json: String, status: Int = 200) -> (Data, HTTPURLResponse) {
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (Data(json.utf8), response)
            }

            if path.hasSuffix("dev.hatk.uploadBlob") {
                guard uploadStatus == 200 else { return respond(#"{"error":"PayloadTooLarge"}"#, status: uploadStatus) }
                return respond(#"{"blob":{"$type":"blob","ref":{"$link":"bafyuploaded"},"mimeType":"image/jpeg","size":1234}}"#)
            }
            if path.hasSuffix("dev.hatk.createRecord") {
                let collection = body
                    .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }?["collection"] as? String
                if collection == "app.bsky.feed.post", blueskyStatus != 200 {
                    return respond("bluesky is down", status: blueskyStatus)
                }
                return respond(#"{"uri":"at://did:plc:test/social.grain.story/story1","cid":"bafy"}"#)
            }
            return respond("{}")
        }
    }

    private func storyRecords() -> [[String: Any]] {
        log.bodies("dev.hatk.createRecord").filter { $0["collection"] as? String == "social.grain.story" }
    }

    private func blueskyRecords() -> [[String: Any]] {
        log.bodies("dev.hatk.createRecord").filter { $0["collection"] as? String == "app.bsky.feed.post" }
    }

    @Test func publishingUploadsThePhotoThenWritesTheStory() async throws {
        serve()
        defer { MockURLProtocol.handler = nil }

        let result = try await StoryService.publish(StoryDraft(image: makeImage()), client: client, repo: "did:plc:test", auth: context)

        #expect(result.uri == "at://did:plc:test/social.grain.story/story1")
        #expect(log.count("dev.hatk.uploadBlob") == 1)
        let write = try #require(storyRecords().first)
        #expect(write["repo"] as? String == "did:plc:test")
        let record = try #require(write["record"] as? [String: Any])
        let media = try #require(record["media"] as? [String: Any])
        #expect((media["ref"] as? [String: Any])?["$link"] as? String == "bafyuploaded", "the story points at the blob it just uploaded")

        let order = log.paths().filter { $0.hasSuffix("uploadBlob") || $0.hasSuffix("createRecord") }
        #expect(order.first?.hasSuffix("uploadBlob") == true, "the blob has to exist before the record references it")
    }

    /// The upload is capped so a single story never exceeds the PDS blob limit.
    @Test func thePhotoIsResizedBeforeUpload() async throws {
        serve()
        defer { MockURLProtocol.handler = nil }

        _ = try await StoryService.publish(StoryDraft(image: makeImage(width: 4000, height: 3000)), client: client, repo: "did:plc:test", auth: context)

        let record = try #require(storyRecords().first?["record"] as? [String: Any])
        let ratio = try #require(record["aspectRatio"] as? [String: Any])
        #expect(ratio["width"] as? Int == 2000)
        #expect(ratio["height"] as? Int == 1500)
    }

    @Test func crossPostingOffWritesNoBlueskyPost() async throws {
        serve()
        defer { MockURLProtocol.handler = nil }

        _ = try await StoryService.publish(StoryDraft(image: makeImage()), client: client, repo: "did:plc:test", auth: context)

        #expect(blueskyRecords().isEmpty)
        #expect(storyRecords().count == 1)
    }

    @Test func crossPostingOnWritesABlueskyPostLinkingBackToTheStory() async throws {
        serve()
        defer { MockURLProtocol.handler = nil }
        var draft = StoryDraft(image: makeImage())
        draft.postToBluesky = true
        draft.location = StoryDraft.Location(h3: "8a2a1072b59ffff", name: "Lisboa", address: nil)

        _ = try await StoryService.publish(draft, client: client, repo: "did:plc:test", auth: context)

        let post = try #require(blueskyRecords().first)
        #expect(post["repo"] as? String == "did:plc:test")
        let record = try #require(post["record"] as? [String: Any])
        let text = record["text"] as? String ?? ""
        #expect(text.contains("grain.social/profile/did:plc:test/story/story1"), "the post links to the story the PDS just keyed: \(text)")
        #expect(text.contains("Lisboa"), "the location carries into the post")

        let embed = try #require(record["embed"] as? [String: Any])
        let images = try #require(embed["images"] as? [[String: Any]])
        #expect(((images.first?["image"] as? [String: Any])?["ref"] as? [String: Any])?["$link"] as? String == "bafyuploaded", "the cross-post reuses the uploaded blob rather than uploading again")
        #expect(log.count("dev.hatk.uploadBlob") == 1)
    }

    /// The story is already live by the time Bluesky is asked. A failed
    /// cross-post must not report the whole post as failed and invite a retry
    /// that would write the story twice.
    @Test func aFailedCrossPostStillCountsAsPublished() async throws {
        serve(blueskyStatus: 500)
        defer { MockURLProtocol.handler = nil }
        var draft = StoryDraft(image: makeImage())
        draft.postToBluesky = true

        let result = try await StoryService.publish(draft, client: client, repo: "did:plc:test", auth: context)

        #expect(result.uri != nil)
        #expect(storyRecords().count == 1)
        #expect(blueskyRecords().count == 1, "it did try")
    }

    @Test func aRejectedUploadFailsBeforeAnyRecordIsWritten() async {
        serve(uploadStatus: 413)
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: (any Error).self) {
            try await StoryService.publish(StoryDraft(image: makeImage()), client: client, repo: "did:plc:test", auth: context)
        }
        #expect(storyRecords().isEmpty, "no story should point at a blob that never landed")
    }

    // MARK: - Through the credentials-resolving wrapper

    @Test func aSignedInAccountPublishesAndReportsSuccess() async {
        await withGrainEnvironment {
            let account = TestAccount()
            defer { account.restore() }
            let auth = AuthManager(session: MockURLProtocol.mockSession())
            await account.activate(auth)
            serve()
            defer { MockURLProtocol.handler = nil }

            let result = await StoryService.publish(StoryDraft(image: makeImage()), client: client, auth: auth)

            guard case .success = result else {
                Issue.record("an accepted publish must report success: \(result)")
                return
            }
            #expect(storyRecords().first?["repo"] as? String == account.did, "the story is written to the signed-in repo")
        }
    }

    @Test func aServerRejectionIsReportedWithItsStatusAndBody() async {
        await withGrainEnvironment {
            let account = TestAccount()
            defer { account.restore() }
            let auth = AuthManager(session: MockURLProtocol.mockSession())
            await account.activate(auth)
            serve(uploadStatus: 413)
            defer { MockURLProtocol.handler = nil }

            let result = await StoryService.publish(StoryDraft(image: makeImage()), client: client, auth: auth)

            guard case let .failure(error) = result else {
                Issue.record("a 413 must not report success")
                return
            }
            let message = StoryService.message(for: error)
            #expect(message.contains("413"), "the status is what makes it diagnosable: \(message)")
            #expect(message.contains("PayloadTooLarge"), "…along with the body")
        }
    }

    @Test func publishingWhileSignedOutFailsWithoutAskingTheServer() async {
        await withGrainEnvironment {
            serve()
            defer { MockURLProtocol.handler = nil }
            let auth = AuthManager(session: MockURLProtocol.mockSession())

            let result = await StoryService.publish(StoryDraft(image: makeImage()), client: client, auth: auth)

            guard case let .failure(error) = result else {
                Issue.record("signed out cannot be a successful publish")
                return
            }
            #expect(error as? StoryPublishError == .notSignedIn)
            #expect(!StoryService.message(for: error).isEmpty, "the composer has to have something to show")
            #expect(log.count("dev.hatk.uploadBlob") == 0, "no point spending an upload without credentials")
        }
    }
}

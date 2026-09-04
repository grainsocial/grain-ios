import CryptoKit
@testable import Grain
import XCTest

// MARK: - Helpers

/// Thread-safe tally of what the mock server was asked to do. The handler runs
/// off the main actor, so the counters need their own lock.
private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    private var bodies: [String: [Data]] = [:]

    func record(path: String, body: Data?) {
        lock.lock()
        defer { lock.unlock() }
        paths.append(path)
        if let body {
            bodies[path, default: []].append(body)
        }
    }

    func count(_ nsid: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return paths.count { $0.hasSuffix(nsid) }
    }

    func bodies(_ nsid: String) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return bodies.first { $0.key.hasSuffix(nsid) }?.value ?? []
    }
}

@MainActor
private final class StubAuth: AuthContextProviding {
    private let context: AuthContext?

    init(signedIn: Bool = true) {
        context = signedIn
            ? AuthContext(accessToken: "test-token", dpop: DPoP(privateKey: P256.Signing.PrivateKey()))
            : nil
    }

    func authContext() async -> AuthContext? {
        context
    }
}

/// `URLProtocol` hands the request over with the body moved into a stream.
private func bodyData(of request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read <= 0 {
            break
        }
        data.append(buffer, count: read)
    }
    return data
}

final class GalleryPublishTests: GrainTestCase {
    private var store: GalleryDraftStore!
    private var storeRoot: URL!
    private var log: RequestLog!

    override func setUp() {
        super.setUp()
        storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gallery-publish-tests-\(UUID().uuidString)", isDirectory: true)
        store = GalleryDraftStore(root: storeRoot)
        log = RequestLog()
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        try? FileManager.default.removeItem(at: storeRoot)
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeDraft(photoCount: Int, uploaded: Int = 0, includeExif: Bool = false) throws -> GalleryDraft {
        let draftID = UUID()
        var photos: [GalleryDraft.Photo] = []
        for index in 0 ..< photoCount {
            let fileName = "photo-\(index).jpg"
            try store.writeImage(Data("jpeg-bytes-\(index)".utf8), draftID: draftID, fileName: fileName)
            photos.append(GalleryDraft.Photo(
                id: UUID(),
                fileName: fileName,
                width: 1600,
                height: 1200,
                alt: index == 0 ? "A quiet street" : "",
                exif: includeExif ? ["make": AnyCodable("Leica")] : nil,
                photoRkey: TID.next(),
                exifRkey: TID.next(),
                itemRkey: TID.next(),
                blob: index < uploaded ? blob(index) : nil
            ))
        }
        return GalleryDraft(
            id: draftID,
            repo: "did:plc:test",
            title: "Golden hour",
            description: "",
            labels: [],
            location: nil,
            includeExif: includeExif,
            postToBluesky: false,
            createdAt: DateFormatting.nowISO(),
            galleryRkey: TID.next(),
            blueskyRkey: TID.next(),
            photos: photos
        )
    }

    private func blob(_ index: Int) -> BlobRef {
        BlobRef(type: "blob", ref: BlobRef.BlobLink(link: "bafyblob\(index)"), mimeType: "image/jpeg", size: 1234)
    }

    /// Stand up a mock server. `applyWritesStatus` lets a test make the atomic
    /// commit fail; `galleryExists` decides what the follow-up existence check
    /// finds.
    private func makeClient(
        applyWritesStatus: Int = 200,
        galleryExists: Bool = false,
        failUploadsAfter: Int? = nil
    ) -> XRPCClient {
        let log = log!
        MockURLProtocol.handler = { request in
            let path = request.url!.path
            log.record(path: path, body: bodyData(of: request))

            func respond(_ json: String, status: Int = 200) -> (Data, HTTPURLResponse) {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (Data(json.utf8), response)
            }

            if path.hasSuffix("dev.hatk.uploadBlob") {
                if let failUploadsAfter, log.count("dev.hatk.uploadBlob") > failUploadsAfter {
                    return respond(#"{"error":"PayloadTooLarge"}"#, status: 413)
                }
                return respond(#"{"blob":{"$type":"blob","ref":{"$link":"bafyuploaded"},"mimeType":"image/jpeg","size":1234}}"#)
            }
            if path.hasSuffix("dev.hatk.applyWrites") {
                if applyWritesStatus != 200 {
                    return respond(#"{"error":"InvalidRequest","message":"Record already exists"}"#, status: applyWritesStatus)
                }
                return respond(#"{"results":[]}"#)
            }
            if path.hasSuffix("dev.hatk.getRecord") {
                return galleryExists
                    ? respond(#"{"uri":"at://did:plc:test/social.grain.gallery/abc","cid":"bafycid"}"#)
                    : respond(#"{"error":"NotFound"}"#, status: 404)
            }
            return respond("{}")
        }
        return XRPCClient(baseURL: URL(string: "https://example.test")!, session: MockURLProtocol.mockSession())
    }

    // MARK: - Record construction

    func testWritesAreStableAcrossCalls() throws {
        let draft = try makeDraft(photoCount: 3, uploaded: 3)
        let first = draft.writes()
        let second = draft.writes()
        XCTAssertEqual(first.map(\.rkey), second.map(\.rkey), "record keys must not change between attempts")
        XCTAssertEqual(first.map(\.collection), second.map(\.collection))
    }

    func testWritesCoverEveryRecordExactlyOnce() throws {
        let draft = try makeDraft(photoCount: 3, uploaded: 3, includeExif: true)
        let writes = draft.writes()
        XCTAssertEqual(writes.count { $0.collection == "social.grain.photo" }, 3)
        XCTAssertEqual(writes.count { $0.collection == "social.grain.photo.exif" }, 3)
        XCTAssertEqual(writes.count { $0.collection == "social.grain.gallery" }, 1)
        XCTAssertEqual(writes.count { $0.collection == "social.grain.gallery.item" }, 3)
        XCTAssertTrue(writes.allSatisfy { $0.type == "dev.hatk.applyWrites#create" })
        XCTAssertTrue(writes.allSatisfy { TID.isValid($0.rkey) })
    }

    /// A photo whose blob never made it up must not produce a dangling item
    /// record pointing at a photo that doesn't exist.
    func testWritesSkipPhotosWithoutBlobs() throws {
        let draft = try makeDraft(photoCount: 4, uploaded: 2)
        let writes = draft.writes()
        XCTAssertEqual(writes.count { $0.collection == "social.grain.photo" }, 2)
        XCTAssertEqual(writes.count { $0.collection == "social.grain.gallery.item" }, 2)
    }

    func testGalleryUriUsesTheAssignedRecordKey() throws {
        let draft = try makeDraft(photoCount: 1, uploaded: 1)
        XCTAssertEqual(draft.galleryUri, "at://did:plc:test/social.grain.gallery/\(draft.galleryRkey)")
    }

    // MARK: - Store

    func testStoreRoundTripsADraft() throws {
        var draft = try makeDraft(photoCount: 2, uploaded: 1)
        store.save(draft)

        let loaded = try XCTUnwrap(store.loadAll().first)
        XCTAssertEqual(loaded.id, draft.id)
        XCTAssertEqual(loaded.galleryRkey, draft.galleryRkey)
        XCTAssertEqual(loaded.photos.map(\.photoRkey), draft.photos.map(\.photoRkey))
        XCTAssertEqual(loaded.photos[0].blob?.ref?.link, "bafyblob0")
        XCTAssertNil(loaded.photos[1].blob)

        draft.committed = true
        store.save(draft)
        XCTAssertEqual(store.loadAll().first?.committed, true)

        store.delete(draft.id)
        XCTAssertTrue(store.loadAll().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(for: draft.id).path))
    }

    // MARK: - Publishing

    @MainActor
    func testPublishUploadsEveryBlobThenCommitsOnce() async throws {
        let draft = try makeDraft(photoCount: 3)
        let center = GalleryUploadCenter(store: store)

        let published = await center.publish(draft, client: makeClient(), auth: StubAuth())

        XCTAssertTrue(published)
        XCTAssertEqual(log.count("dev.hatk.uploadBlob"), 3)
        XCTAssertEqual(log.count("dev.hatk.applyWrites"), 1)
        XCTAssertEqual(center.stage, .finished)
        XCTAssertNil(center.activeDraft)
        XCTAssertTrue(store.loadAll().isEmpty, "a published draft is cleaned off disk")
    }

    /// The whole point of checkpointing: resuming a draft that died partway
    /// through re-uploads only what's missing.
    @MainActor
    func testResumeOnlyUploadsTheBlobsThatAreStillMissing() async throws {
        let draft = try makeDraft(photoCount: 5, uploaded: 3)
        let center = GalleryUploadCenter(store: store)

        let published = await center.publish(draft, client: makeClient(), auth: StubAuth())

        XCTAssertTrue(published)
        XCTAssertEqual(log.count("dev.hatk.uploadBlob"), 2, "the three finished uploads must not repeat")
    }

    /// The duplicate-gallery case. A commit that actually landed but came back
    /// as an error — a lost response, or a retry the PDS rejected because the
    /// records already exist — is a published gallery, not a failure to redo.
    @MainActor
    func testCommitRejectedButAlreadyOnThePdsCountsAsPublished() async throws {
        let draft = try makeDraft(photoCount: 2, uploaded: 2)
        let center = GalleryUploadCenter(store: store)

        let published = await center.publish(
            draft,
            client: makeClient(applyWritesStatus: 400, galleryExists: true),
            auth: StubAuth()
        )

        XCTAssertTrue(published, "the gallery is on the PDS, so this is a success")
        XCTAssertEqual(log.count("dev.hatk.applyWrites"), 1, "no second commit attempt")
        XCTAssertEqual(log.count("dev.hatk.getRecord"), 1, "we asked whether it landed")
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    @MainActor
    func testCommitThatNeverLandedIsReportedAsAFailureAndKeepsTheDraft() async throws {
        let draft = try makeDraft(photoCount: 2, uploaded: 2)
        let center = GalleryUploadCenter(store: store)

        let published = await center.publish(
            draft,
            client: makeClient(applyWritesStatus: 400, galleryExists: false),
            auth: StubAuth()
        )

        XCTAssertFalse(published)
        if case .failed = center.stage {} else {
            XCTFail("expected a failed stage, got \(center.stage)")
        }
        XCTAssertEqual(center.activeDraft?.id, draft.id, "the draft is kept so retry can resume it")
        XCTAssertEqual(store.loadAll().count, 1, "and it stays on disk across a relaunch")
    }

    /// End to end on a bad connection: the commit fails, the user taps Try
    /// again, and the second attempt neither re-uploads the photos nor writes a
    /// second set of records.
    @MainActor
    func testRetryAfterAFailedCommitReusesTheSameRecordKeys() async throws {
        let draft = try makeDraft(photoCount: 3)
        let center = GalleryUploadCenter(store: store)
        let auth = StubAuth()

        let first = await center.publish(draft, client: makeClient(applyWritesStatus: 400), auth: auth)
        XCTAssertFalse(first)
        XCTAssertEqual(log.count("dev.hatk.uploadBlob"), 3)

        let second = await center.retry(client: makeClient(), auth: auth)

        XCTAssertTrue(second)
        XCTAssertEqual(log.count("dev.hatk.uploadBlob"), 3, "the retry must not re-upload a single photo")

        let commits = log.bodies("dev.hatk.applyWrites")
        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(try recordKeys(commits[0]), try recordKeys(commits[1]), "both attempts address the same records")

        let keys = try recordKeys(commits[1])
        XCTAssertEqual(Set(keys).count, keys.count, "no record is written twice within a commit")
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    @MainActor
    func testPublishWithoutASessionFailsWithoutTouchingTheNetwork() async throws {
        let draft = try makeDraft(photoCount: 2)
        let center = GalleryUploadCenter(store: store)

        let published = await center.publish(draft, client: makeClient(), auth: StubAuth(signedIn: false))

        XCTAssertFalse(published)
        XCTAssertEqual(log.count("dev.hatk.uploadBlob"), 0)
    }

    @MainActor
    func testResumePendingPicksUpDraftsLeftOnDisk() async throws {
        let draft = try makeDraft(photoCount: 2, uploaded: 2)
        store.save(draft)

        let center = GalleryUploadCenter(store: store)
        center.refreshPending()
        XCTAssertEqual(center.pending.count, 1)

        await center.resumePending(client: makeClient(), auth: StubAuth())

        XCTAssertEqual(log.count("dev.hatk.applyWrites"), 1)
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    @MainActor
    func testSetAsideKeepsTheDraftForLater() async throws {
        let draft = try makeDraft(photoCount: 2, uploaded: 2)
        let center = GalleryUploadCenter(store: store)

        _ = await center.publish(draft, client: makeClient(applyWritesStatus: 400), auth: StubAuth())
        center.setAside()

        XCTAssertEqual(center.stage, .idle)
        XCTAssertNil(center.activeDraft)
        XCTAssertEqual(center.pending.count, 1)
        XCTAssertEqual(store.loadAll().count, 1)
    }

    /// The create sheet refreshes the feed through its own completion handler.
    /// Firing `onPublished` as well rebuilt the feed while the sheet was still
    /// up, which re-presented it for a frame before it closed.
    @MainActor
    func testDirectPublishDoesNotAlsoFireTheBackgroundRefreshHook() async throws {
        let draft = try makeDraft(photoCount: 1, uploaded: 1)
        let center = GalleryUploadCenter(store: store)
        var refreshes = 0
        center.onPublished = { refreshes += 1 }

        let published = await center.publish(draft, client: makeClient(), auth: StubAuth())

        XCTAssertTrue(published)
        XCTAssertEqual(refreshes, 0, "the create sheet owns the refresh for its own publish")
    }

    @MainActor
    func testResumePendingFiresTheRefreshHookOncePerSweep() async throws {
        for _ in 0 ..< 2 {
            try store.save(makeDraft(photoCount: 1, uploaded: 1))
        }
        let center = GalleryUploadCenter(store: store)
        var refreshes = 0
        center.onPublished = { refreshes += 1 }

        await center.resumePending(client: makeClient(), auth: StubAuth())

        XCTAssertEqual(log.count("dev.hatk.applyWrites"), 2, "both drafts published")
        XCTAssertEqual(refreshes, 1, "one feed rebuild, not one per draft")
    }

    @MainActor
    func testResumePendingSkipsTheRefreshHookWhenNothingPublished() async throws {
        try store.save(makeDraft(photoCount: 1, uploaded: 1))
        let center = GalleryUploadCenter(store: store)
        var refreshes = 0
        center.onPublished = { refreshes += 1 }

        await center.resumePending(client: makeClient(applyWritesStatus: 400), auth: StubAuth())

        XCTAssertEqual(refreshes, 0)
    }

    /// The connection dying mid-upload is the common case. The photos that made
    /// it up must stay up.
    @MainActor
    func testAnUploadThatDiesPartwayResumesFromTheLastPhotoThatLanded() async throws {
        let draft = try makeDraft(photoCount: 5)
        let center = GalleryUploadCenter(store: store)
        let auth = StubAuth()

        let first = await center.publish(draft, client: makeClient(failUploadsAfter: 2), auth: auth)
        XCTAssertFalse(first)
        XCTAssertEqual(log.count("dev.hatk.uploadBlob"), 3, "two succeeded, the third failed")
        XCTAssertEqual(center.activeDraft?.uploadedPhotoCount, 2, "progress is remembered")
        XCTAssertEqual(store.load(draft.id)?.uploadedPhotoCount, 2, "and checkpointed to disk")

        let second = await center.retry(client: makeClient(), auth: auth)

        XCTAssertTrue(second)
        XCTAssertEqual(
            log.count("dev.hatk.uploadBlob"), 6,
            "the retry uploads the remaining three photos, not all five again"
        )
        XCTAssertEqual(log.count("dev.hatk.applyWrites"), 1)
    }

    /// A background resume and a tap on Post can land together; the two must
    /// not interleave and corrupt each other's progress.
    @MainActor
    func testConcurrentPublishesAreSerialised() async throws {
        let first = try makeDraft(photoCount: 2, uploaded: 2)
        let second = try makeDraft(photoCount: 2, uploaded: 2)
        let center = GalleryUploadCenter(store: store)
        let client = makeClient()
        let auth = StubAuth()

        async let firstPublish = center.publish(first, client: client, auth: auth)
        async let secondPublish = center.publish(second, client: client, auth: auth)
        let results = await [firstPublish, secondPublish]

        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(log.count("dev.hatk.applyWrites"), 2)
        XCTAssertNil(center.activeDraft)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testLoadAllDiscardsDraftsThatHaveSatUnfinishedTooLong() throws {
        var stale = try makeDraft(photoCount: 1, uploaded: 1)
        stale.createdAt = DateFormatting.nowISO(date: Date().addingTimeInterval(-8 * 24 * 60 * 60))
        store.save(stale)
        let fresh = try makeDraft(photoCount: 1, uploaded: 1)
        store.save(fresh)

        let loaded = store.loadAll()

        XCTAssertEqual(loaded.map(\.id), [fresh.id])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.directory(for: stale.id).path),
            "the expired draft's photos are cleaned up too"
        )
    }

    func testLoadAllSweepsDirectoriesWithNoReadableDraft() throws {
        let orphan = UUID()
        try store.writeImage(Data("stranded".utf8), draftID: orphan, fileName: "photo-0.jpg")

        XCTAssertTrue(store.loadAll().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(for: orphan).path))
    }

    // MARK: - Stage reporting

    func testStageLabelsCountPhotosFromOne() {
        XCTAssertEqual(GalleryUploadCenter.Stage.uploading(completed: 0, total: 8).label, "Uploading photo 1 of 8")
        XCTAssertEqual(GalleryUploadCenter.Stage.uploading(completed: 7, total: 8).label, "Uploading photo 8 of 8")
        XCTAssertEqual(GalleryUploadCenter.Stage.preparing(completed: 8, total: 8).label, "Preparing photo 8 of 8")
    }

    func testStageProgressRunsForwardAcrossBothPhases() {
        let prepared = GalleryUploadCenter.Stage.preparing(completed: 4, total: 8).fraction
        let uploading = GalleryUploadCenter.Stage.uploading(completed: 0, total: 8).fraction
        XCTAssertEqual(prepared, 0.25)
        XCTAssertEqual(uploading, 0.5)
        XCTAssertEqual(GalleryUploadCenter.Stage.uploading(completed: 8, total: 8).fraction, 1.0)
        XCTAssertNil(GalleryUploadCenter.Stage.idle.fraction)
    }

    // MARK: - Body inspection

    private func recordKeys(_ body: Data) throws -> [String] {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let writes = try XCTUnwrap(json["writes"] as? [[String: Any]])
        return writes.map { "\($0["collection"] ?? "")/\($0["rkey"] ?? "")" }
    }
}

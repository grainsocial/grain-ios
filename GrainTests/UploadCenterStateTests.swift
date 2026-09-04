@testable import Grain
import XCTest

/// The bookkeeping around a publish rather than the publish itself: which
/// drafts are on screen, what happens to them when the account changes, and
/// how a failure is stepped away from without losing the work.
///
/// `GalleryPublishTests` covers the upload and commit state machine; this
/// covers the parts that decide what the resume banner shows.
@MainActor
final class UploadCenterStateTests: GrainTestCase {
    private var root: URL!
    private var store: GalleryDraftStore!
    private var center: GalleryUploadCenter!

    override func setUp() async throws {
        try await super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("uploadcenter-\(UUID().uuidString)", isDirectory: true)
        store = GalleryDraftStore(root: root)
        center = GalleryUploadCenter(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    @discardableResult
    private func saveDraft(repo: String, title: String, age: TimeInterval = 0) -> GalleryDraft {
        let draft = GalleryDraft(
            repo: repo,
            title: title,
            description: "",
            labels: [],
            location: nil,
            includeExif: false,
            postToBluesky: false,
            // Relative, not a literal: the store sweeps drafts older than a
            // week, so a hardcoded date turns this into a time bomb.
            createdAt: DateFormatting.nowISO(date: Date().addingTimeInterval(-age)),
            galleryRkey: TID.next(),
            blueskyRkey: TID.next(),
            photos: []
        )
        store.save(draft)
        return draft
    }

    // MARK: - Starting state

    func testItStartsIdleWithNothingPending() {
        XCTAssertEqual(center.stage, .idle)
        XCTAssertNil(center.activeDraft)
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertNil(center.ownerDID)
    }

    // MARK: - refreshPending

    /// With no account set nothing is filtered — that's what previews and tests
    /// want, and what the app looks like before sign-in resolves.
    func testWithNoOwnerEveryDraftOnDiskIsPending() {
        saveDraft(repo: "did:plc:a", title: "Alpha")
        saveDraft(repo: "did:plc:b", title: "Beta")

        center.refreshPending()

        XCTAssertEqual(Set(center.pending.map(\.title)), ["Alpha", "Beta"])
    }

    /// Drafts composed under another account name a repo we no longer hold a
    /// token for; resuming one would write to the wrong place.
    func testOnlyTheOwningAccountsDraftsArePending() {
        saveDraft(repo: "did:plc:a", title: "Alpha")
        saveDraft(repo: "did:plc:b", title: "Beta")

        center.accountChanged(to: "did:plc:a")

        XCTAssertEqual(center.pending.map(\.title), ["Alpha"])
    }

    /// Drafts are listed oldest first so the resume banner works through them
    /// in the order they were composed.
    func testPendingDraftsComeBackOldestFirst() {
        saveDraft(repo: "did:plc:a", title: "Older", age: 600)
        saveDraft(repo: "did:plc:a", title: "Newer", age: 60)

        center.accountChanged(to: "did:plc:a")

        XCTAssertEqual(center.pending.map(\.title), ["Older", "Newer"])
    }

    /// A week-old draft is written off rather than offered for resume.
    func testDraftsThatHaveSatTooLongAreNotOffered() {
        saveDraft(repo: "did:plc:a", title: "Fresh", age: 60)
        saveDraft(repo: "did:plc:a", title: "Ancient", age: GalleryDraftStore.maxAge + 3600)

        center.accountChanged(to: "did:plc:a")

        XCTAssertEqual(center.pending.map(\.title), ["Fresh"])
    }

    // MARK: - accountChanged

    /// Switching accounts must take the outgoing account's draft off screen so
    /// the retry button can't act on it with the wrong credentials — but the
    /// work stays on disk for when that account comes back.
    func testSwitchingAccountsTakesTheOtherAccountsDraftOffScreen() {
        let alphas = saveDraft(repo: "did:plc:a", title: "Alpha")
        center.accountChanged(to: "did:plc:a")
        center.refreshPending()
        XCTAssertEqual(center.pending.map(\.title), ["Alpha"])

        center.accountChanged(to: "did:plc:b")

        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertNotNil(store.load(alphas.id), "The draft itself must survive the switch")
    }

    func testSwitchingBackBringsTheDraftBack() {
        saveDraft(repo: "did:plc:a", title: "Alpha")
        center.accountChanged(to: "did:plc:a")
        center.accountChanged(to: "did:plc:b")
        XCTAssertTrue(center.pending.isEmpty)

        center.accountChanged(to: "did:plc:a")

        XCTAssertEqual(center.pending.map(\.title), ["Alpha"])
    }

    /// The hook fires on every sign-in check, so re-announcing the same account
    /// must not disturb anything.
    func testReAnnouncingTheSameAccountIsANoOp() {
        saveDraft(repo: "did:plc:a", title: "Alpha")
        center.accountChanged(to: "did:plc:a")
        let before = center.pending.map(\.id)

        center.accountChanged(to: "did:plc:a")

        XCTAssertEqual(center.pending.map(\.id), before)
        XCTAssertEqual(center.ownerDID, "did:plc:a")
    }

    func testSigningOutClearsTheOwnerAndShowsEverythingAgain() {
        saveDraft(repo: "did:plc:a", title: "Alpha")
        saveDraft(repo: "did:plc:b", title: "Beta")
        center.accountChanged(to: "did:plc:a")

        center.accountChanged(to: nil)

        XCTAssertNil(center.ownerDID)
        XCTAssertEqual(Set(center.pending.map(\.title)), ["Alpha", "Beta"])
    }

    // MARK: - discard

    func testDiscardingTakesTheDraftOffDiskAndOffScreen() {
        let draft = saveDraft(repo: "did:plc:a", title: "Alpha")
        center.accountChanged(to: "did:plc:a")
        XCTAssertEqual(center.pending.count, 1)

        center.discard(draft.id)

        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertNil(store.load(draft.id))
    }

    /// Tapping discard twice, or discarding something already swept, must not
    /// disturb the drafts that are left.
    func testDiscardingSomethingThatIsAlreadyGoneIsHarmless() {
        saveDraft(repo: "did:plc:a", title: "Alpha")
        center.accountChanged(to: "did:plc:a")

        center.discard(UUID())

        XCTAssertEqual(center.pending.map(\.title), ["Alpha"])
    }

    // MARK: - clearFailure

    /// Dismissing the error puts the sheet back to a usable state; it must not
    /// reach in and change a publish that's still running.
    func testClearingAFailureOnlyAffectsTheFailedState() {
        XCTAssertEqual(center.stage, .idle)

        center.clearFailure()

        XCTAssertEqual(center.stage, .idle)
    }

    // MARK: - Stage

    func testOnlyTheWorkingStagesCountAsBusy() {
        XCTAssertTrue(GalleryUploadCenter.Stage.preparing(completed: 0, total: 3).isBusy)
        XCTAssertTrue(GalleryUploadCenter.Stage.uploading(completed: 0, total: 3).isBusy)
        XCTAssertTrue(GalleryUploadCenter.Stage.publishing.isBusy)

        XCTAssertFalse(GalleryUploadCenter.Stage.idle.isBusy)
        XCTAssertFalse(GalleryUploadCenter.Stage.finished.isBusy)
        XCTAssertFalse(GalleryUploadCenter.Stage.failed(message: "no").isBusy)
    }

    /// A gallery with no photos to count gets an indeterminate spinner rather
    /// than a bar stuck at zero — and must not divide by zero getting there.
    func testStagesWithNothingToCountHaveNoFraction() {
        XCTAssertNil(GalleryUploadCenter.Stage.preparing(completed: 0, total: 0).fraction)
        XCTAssertNil(GalleryUploadCenter.Stage.uploading(completed: 0, total: 0).fraction)
        XCTAssertNil(GalleryUploadCenter.Stage.failed(message: "no").fraction)
    }

    /// The failure message is the label, because that's what the overlay shows.
    func testAFailureLabelsItselfWithItsMessage() {
        XCTAssertEqual(
            GalleryUploadCenter.Stage.failed(message: "The connection dropped.").label,
            "The connection dropped."
        )
    }

    // MARK: - Draft store sweeping

    /// A directory with no readable draft is left behind by a build that died
    /// mid-write; it's swept rather than counted.
    func testADirectoryWithNoReadableDraftIsSweptUp() throws {
        saveDraft(repo: "did:plc:a", title: "Alpha")
        let orphan = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: orphan.appendingPathComponent("draft.json"))

        center.refreshPending()

        XCTAssertEqual(center.pending.map(\.title), ["Alpha"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testLoadingADraftThatWasNeverSavedReturnsNothing() {
        XCTAssertNil(store.load(UUID()))
    }

    /// Photos are written beside the draft, keyed by file name.
    func testPhotoDataRoundTripsThroughTheStore() throws {
        let id = UUID()
        let bytes = Data([0x01, 0x02, 0x03])

        try store.writeImage(bytes, draftID: id, fileName: "photo.jpg")

        XCTAssertEqual(try store.readImage(draftID: id, fileName: "photo.jpg"), bytes)
        XCTAssertEqual(
            store.imageURL(draftID: id, fileName: "photo.jpg"),
            store.directory(for: id).appendingPathComponent("photo.jpg")
        )
    }

    func testReadingAPhotoThatWasNeverWrittenThrows() {
        XCTAssertThrowsError(try store.readImage(draftID: UUID(), fileName: "missing.jpg"))
    }
}

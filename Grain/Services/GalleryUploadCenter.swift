import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "GalleryUpload")

/// Just enough of `AuthManager` for the uploader to get a token that may have
/// been refreshed since the last attempt — and enough of a seam to exercise the
/// publish state machine without a keychain.
@MainActor
protocol AuthContextProviding {
    func authContext() async -> AuthContext?
}

extension AuthManager: AuthContextProviding {}

/// Publishes gallery drafts, and picks up the ones an earlier attempt left behind.
///
/// The old flow issued roughly `2n + 2` record writes with server-assigned
/// record keys and no retries, so a single dropped request on a bad connection
/// both failed the post and stranded whatever had already been written. Tapping
/// Post again started over from nothing, which is how a gallery ended up in the
/// feed twice.
///
/// This runs in two steps instead. First the blobs go up, one request each,
/// checkpointed to disk as they land — those are content-addressed, so
/// re-uploading is harmless and skipping is free. Then every record goes out in
/// a single atomic `applyWrites` commit with record keys the draft has been
/// carrying since it was built. Retrying either step is safe, and a retry only
/// pays for the part that hadn't finished.
@MainActor
@Observable
final class GalleryUploadCenter {
    enum Stage: Equatable {
        case idle
        case preparing(completed: Int, total: Int)
        case uploading(completed: Int, total: Int)
        case publishing
        case finished
        case failed(message: String)

        var isBusy: Bool {
            switch self {
            case .preparing, .uploading, .publishing: true
            case .idle, .finished, .failed: false
            }
        }

        /// 0...1 for the determinate bar, or nil while the work isn't countable.
        var fraction: Double? {
            switch self {
            // Preparing and uploading are each roughly half the wait, and both
            // are per-photo, so they share one bar rather than resetting it.
            case let .preparing(completed, total):
                total > 0 ? Double(completed) / Double(total) * 0.5 : nil
            case let .uploading(completed, total):
                total > 0 ? 0.5 + Double(completed) / Double(total) * 0.5 : nil
            case .publishing: 1
            case .finished: 1
            case .idle, .failed: nil
            }
        }

        var label: String {
            switch self {
            case .idle: ""
            case let .preparing(completed, total): "Preparing photo \(min(completed + 1, total)) of \(total)"
            case let .uploading(completed, total): "Uploading photo \(min(completed + 1, total)) of \(total)"
            case .publishing: "Publishing gallery"
            case .finished: "Posted"
            case let .failed(message): message
            }
        }
    }

    private(set) var stage: Stage = .idle
    /// The draft being worked on, kept after a failure so `retry` has something
    /// to resume.
    private(set) var activeDraft: GalleryDraft?
    /// Drafts from an interrupted publish that nothing is currently working on.
    private(set) var pending: [GalleryDraft] = []

    /// Called after a *background* resume puts a gallery live, so the feed can
    /// refresh to show it.
    ///
    /// Deliberately not fired for a publish the create sheet is driving: that
    /// path has its own completion handler, and refreshing from both meant the
    /// feed was rebuilt while the sheet was still presented — which re-presented
    /// the sheet for a frame before it closed for good.
    var onPublished: (@MainActor () -> Void)?

    /// DID of the signed-in account. Drafts on disk name the repo they publish
    /// to, so this filters out galleries composed under a different account —
    /// resuming one of those would write to a repo we no longer hold a token
    /// for. Nil means "don't filter", which is what tests and previews want.
    var ownerDID: String?

    private let store: GalleryDraftStore
    private var inFlight: Task<Bool, Never>?

    init(store: GalleryDraftStore = .shared) {
        self.store = store
    }

    /// Re-point the uploader at another account. A draft belonging to the
    /// account being left stays on disk — it reappears when that account comes
    /// back — but it's taken off screen so the resume banner and its retry
    /// button can't act on it with the wrong credentials.
    func accountChanged(to did: String?) {
        guard did != ownerDID else { return }
        ownerDID = did
        if let draft = activeDraft, draft.repo != did {
            activeDraft = nil
            stage = .idle
        }
        refreshPending()
    }

    /// Re-read what's on disk. Cheap — the JSON is a few kilobytes.
    func refreshPending() {
        let activeID = activeDraft?.id
        pending = store.loadAll().filter { draft in
            draft.id != activeID && (ownerDID == nil || draft.repo == ownerDID)
        }
    }

    func discard(_ draftID: UUID) {
        store.delete(draftID)
        pending.removeAll { $0.id == draftID }
        if activeDraft?.id == draftID {
            activeDraft = nil
            stage = .idle
        }
    }

    /// Step away from a failed publish without throwing the work out — the
    /// draft stays on disk and gets picked up by `resumePending`.
    func setAside() {
        if let draft = activeDraft {
            activeDraft = nil
            pending.append(draft)
        }
        stage = .idle
    }

    func clearFailure() {
        if case .failed = stage {
            stage = .idle
        }
    }

    // MARK: - Entry points

    /// Prepare the photos on screen into a draft, then publish it.
    @discardableResult
    func publish(
        items: [PhotoItem],
        repo: String,
        title: String,
        description: String,
        labels: [String],
        location: GalleryDraft.Location?,
        includeExif: Bool,
        postToBluesky: Bool,
        client: XRPCClient,
        auth: any AuthContextProviding
    ) async -> Bool {
        stage = .preparing(completed: 0, total: items.count)
        do {
            let draft = try await GalleryDraft.build(
                items: items,
                repo: repo,
                title: title,
                description: description,
                labels: labels,
                location: location,
                includeExif: includeExif,
                postToBluesky: postToBluesky,
                store: store,
                onProgress: { [weak self] completed, total in
                    self?.stage = .preparing(completed: completed, total: total)
                }
            )
            return await publish(draft, client: client, auth: auth)
        } catch {
            logger.error("Preparing draft failed: \(error.localizedDescription)")
            stage = .failed(message: Self.message(for: error))
            return false
        }
    }

    /// Re-run the publish that just failed, resuming from its last checkpoint.
    @discardableResult
    func retry(client: XRPCClient, auth: any AuthContextProviding) async -> Bool {
        guard let draft = activeDraft else { return false }
        return await publish(draft, client: client, auth: auth)
    }

    /// Resume every leftover draft, one at a time. Safe to call on launch and
    /// on foreground — a draft already being worked on is skipped, and one
    /// that turns out to be published already is cleaned up by `publish`.
    func resumePending(client: XRPCClient, auth: any AuthContextProviding) async {
        guard !stage.isBusy else { return }
        refreshPending()
        var anyPublished = false
        for draft in pending {
            guard !stage.isBusy else { break }
            logger.info("Resuming interrupted gallery \(draft.id)")
            let published = await publish(draft, client: client, auth: auth)
            if !published {
                break
            }
            anyPublished = true
        }
        // Fired once at the end — every call rebuilds the feed.
        if anyPublished {
            onPublished?()
        }
    }

    /// Publish `draft`, or pick up where a previous attempt stopped.
    /// Returns true once the gallery is live.
    ///
    /// Publishes are serialised. A background resume and a tap on Post can
    /// arrive at the same moment, and two of these interleaving would have them
    /// trampling each other's `stage` and `activeDraft`.
    @discardableResult
    func publish(_ draft: GalleryDraft, client: XRPCClient, auth: any AuthContextProviding) async -> Bool {
        if let inFlight {
            _ = await inFlight.value
        }
        let task = Task { await performPublish(draft, client: client, auth: auth) }
        inFlight = task
        let published = await task.value
        if inFlight == task {
            inFlight = nil
        }
        return published
    }

    private func performPublish(_ draft: GalleryDraft, client: XRPCClient, auth: any AuthContextProviding) async -> Bool {
        guard let authContext = await auth.authContext() else {
            stage = .failed(message: "You're signed out. Sign in again to finish posting.")
            return false
        }

        var draft = draft
        activeDraft = draft
        pending.removeAll { $0.id == draft.id }
        store.save(draft)

        do {
            try await uploadBlobs(&draft, client: client, authContext: authContext)

            if !draft.committed {
                stage = .publishing
                try await commit(draft, client: client, authContext: authContext)
                draft.committed = true
                store.save(draft)
            }

            // The gallery is live from here on. The cross-post is a bonus, and
            // a failure in it must not send the user back to a retry screen for
            // a gallery that already posted.
            if draft.postToBluesky, !draft.crossPosted {
                await crossPostToBluesky(draft, client: client, authContext: authContext)
                draft.crossPosted = true
                store.save(draft)
            }

            store.delete(draft.id)
            activeDraft = nil
            stage = .finished
            refreshPending()
            return true
        } catch {
            logger.error("Publish failed for \(draft.id): \(error.localizedDescription)")
            // Keep the draft so retrying resumes instead of re-uploading
            // everything. Read it back from disk rather than trusting the local
            // copy: the checkpoint written after the last successful upload is
            // what a fresh launch would resume from, so a retry should start
            // from exactly the same place.
            activeDraft = store.load(draft.id) ?? draft
            stage = .failed(message: Self.message(for: error))
            refreshPending()
            return false
        }
    }

    // MARK: - Steps

    private func uploadBlobs(_ draft: inout GalleryDraft, client: XRPCClient, authContext: AuthContext) async throws {
        let total = draft.photos.count
        stage = .uploading(completed: draft.uploadedPhotoCount, total: total)

        for index in draft.photos.indices where draft.photos[index].blob == nil {
            let photo = draft.photos[index]
            let data = try store.readImage(draftID: draft.id, fileName: photo.fileName)
            let response = try await NetworkRetry.run {
                try await client.uploadBlob(data: data, mimeType: "image/jpeg", auth: authContext)
            }
            draft.photos[index].blob = response.blob
            // Checkpoint per photo: an upload that dies on 14 of 20 resumes at 14.
            store.save(draft)
            stage = .uploading(completed: draft.uploadedPhotoCount, total: total)
        }
    }

    private func commit(_ draft: GalleryDraft, client: XRPCClient, authContext: AuthContext) async throws {
        do {
            _ = try await NetworkRetry.run {
                try await client.applyWrites(draft.writes(), auth: authContext)
            }
        } catch {
            // The commit is atomic, but "we never saw the response" and "the
            // commit landed" look identical from here — as does a retry that
            // was rejected because the records already exist. All three mean
            // the gallery is on the PDS. Ask before calling it a failure.
            if await galleryExists(draft, client: client, authContext: authContext) {
                logger.info("Commit reported \(error.localizedDescription), but the gallery is on the PDS — treating as published")
                return
            }
            throw error
        }
    }

    private func galleryExists(_ draft: GalleryDraft, client: XRPCClient, authContext: AuthContext) async -> Bool {
        do {
            let response = try await NetworkRetry.run(attempts: 2) {
                try await client.getRecord(uri: draft.galleryUri, auth: authContext)
            }
            return response.uri != nil
        } catch {
            // Couldn't tell. Report the original failure and let the retry ask again.
            return false
        }
    }

    private func crossPostToBluesky(_ draft: GalleryDraft, client: XRPCClient, authContext: AuthContext) async {
        let images = draft.photos.compactMap { photo -> (blob: BlobRef, alt: String, width: Int, height: Int)? in
            guard let blob = photo.blob else { return nil }
            return (blob: blob, alt: photo.alt, width: photo.width, height: photo.height)
        }
        do {
            try await BlueskyPost.create(
                options: BlueskyPostOptions(
                    url: "https://grain.social/profile/\(draft.repo)/gallery/\(draft.galleryRkey)",
                    title: draft.title.isEmpty ? nil : draft.title,
                    location: draft.location.map { ($0.name, $0.address) },
                    description: draft.description.isEmpty ? nil : draft.description,
                    images: images
                ),
                client: client,
                repo: draft.repo,
                auth: authContext,
                rkey: draft.blueskyRkey,
                createdAt: draft.createdAt
            )
        } catch {
            logger.error("Bluesky cross-post failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Copy

    static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "You're offline. Your gallery is saved — try again once you have a connection."
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
                return "The connection dropped. Nothing was lost — trying again picks up where it stopped."
            default:
                break
            }
        }
        if let xrpcError = error as? XRPCError {
            switch xrpcError {
            case .unauthorized:
                return "Your session expired. Sign in again to finish posting."
            case let .httpError(statusCode, body):
                if statusCode == 429 {
                    return "Your server is rate limiting uploads. Wait a moment and try again."
                }
                if (500 ... 599).contains(statusCode) {
                    return "The server had a problem. Nothing was lost — try again in a moment."
                }
                let detail = body.flatMap { String(data: $0, encoding: .utf8) }
                return detail.map { "Couldn't post (HTTP \(statusCode)): \($0)" } ?? "Couldn't post (HTTP \(statusCode))."
            default:
                break
            }
        }
        if let draftError = error as? GalleryDraftError {
            return draftError.localizedDescription
        }
        return "Couldn't post: \(error.localizedDescription)"
    }
}

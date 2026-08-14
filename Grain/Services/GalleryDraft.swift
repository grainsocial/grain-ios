import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "GalleryDraft")

/// A gallery that has been handed to the uploader but hasn't finished publishing.
///
/// Two things make a draft resumable. Every record key it will ever write is
/// assigned up front, so a retry overwrites its own records rather than
/// creating a second gallery. And its photos are stored next to it on disk as
/// already-resized JPEGs, so the work survives the app being killed mid-upload
/// and doesn't depend on the `PhotosPickerItem` still being alive.
struct GalleryDraft: Codable, Sendable, Identifiable, Equatable {
    var id: UUID = .init()
    /// DID of the author, i.e. the repo every record is written to.
    var repo: String
    var title: String
    var description: String
    var labels: [String]
    var location: Location?
    var includeExif: Bool
    var postToBluesky: Bool
    /// `createdAt` for every record in the gallery. Frozen when the draft is
    /// created so a retry two minutes later writes byte-identical records.
    var createdAt: String
    var galleryRkey: String
    /// Record key for the optional Bluesky cross-post, assigned up front for
    /// the same reason as the rest: a resumed publish must not post twice.
    var blueskyRkey: String
    var photos: [Photo]
    /// Set once the atomic commit is known to have landed. Short-circuits the
    /// commit step on any later resume.
    var committed: Bool = false
    /// Set once the Bluesky cross-post has been written (or deliberately skipped).
    var crossPosted: Bool = false

    struct Location: Codable, Sendable, Equatable {
        var h3: String
        var name: String
        var address: [String: AnyCodable]?

        static func == (lhs: Location, rhs: Location) -> Bool {
            lhs.h3 == rhs.h3 && lhs.name == rhs.name
        }
    }

    struct Photo: Codable, Sendable, Identifiable, Equatable {
        var id: UUID
        /// File name of the resized JPEG inside the draft's directory.
        var fileName: String
        var width: Int
        var height: Int
        var alt: String
        var exif: [String: AnyCodable]?
        var photoRkey: String
        var exifRkey: String
        var itemRkey: String
        /// Set once the blob is on the PDS. Blobs are content-addressed so a
        /// re-upload would return the same ref anyway — but skipping it is the
        /// entire point when the connection is the thing that's failing.
        var blob: BlobRef?

        static func == (lhs: Photo, rhs: Photo) -> Bool {
            lhs.id == rhs.id && lhs.blob?.ref?.link == rhs.blob?.ref?.link
        }
    }

    static func == (lhs: GalleryDraft, rhs: GalleryDraft) -> Bool {
        lhs.id == rhs.id && lhs.committed == rhs.committed && lhs.photos == rhs.photos
    }

    var galleryUri: String {
        "at://\(repo)/social.grain.gallery/\(galleryRkey)"
    }

    func photoUri(_ photo: Photo) -> String {
        "at://\(repo)/social.grain.photo/\(photo.photoRkey)"
    }

    var uploadedPhotoCount: Int {
        photos.count(where: { $0.blob != nil })
    }

    /// A short label for the resume banner — the title, or a fallback.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled gallery" : trimmed
    }

    // MARK: - Record construction

    /// Every write the gallery needs, in the order the appview should index
    /// them: photos first, then the gallery they belong to, then the links.
    /// They all go out in one atomic commit, so this ordering is about how the
    /// server reads the batch, not about durability.
    func writes() -> [ApplyWrite] {
        var writes: [ApplyWrite] = []

        for photo in photos {
            guard let blob = photo.blob else { continue }
            var record: [String: AnyCodable] = [
                "photo": AnyCodable(blobDict(blob)),
                "aspectRatio": AnyCodable([
                    "width": AnyCodable(photo.width),
                    "height": AnyCodable(photo.height),
                ] as [String: AnyCodable]),
                "createdAt": AnyCodable(createdAt),
            ]
            let alt = photo.alt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !alt.isEmpty {
                record["alt"] = AnyCodable(alt)
            }
            writes.append(.create(collection: "social.grain.photo", rkey: photo.photoRkey, value: AnyCodable(record)))

            if includeExif, var exif = photo.exif, !exif.isEmpty {
                exif["photo"] = AnyCodable(photoUri(photo))
                exif["createdAt"] = AnyCodable(createdAt)
                writes.append(.create(collection: "social.grain.photo.exif", rkey: photo.exifRkey, value: AnyCodable(exif)))
            }
        }

        var gallery: [String: AnyCodable] = [
            "title": AnyCodable(title),
            "createdAt": AnyCodable(createdAt),
        ]
        if !description.isEmpty {
            gallery["description"] = AnyCodable(description)
        }
        if !labels.isEmpty {
            let values = labels.map { ["val": AnyCodable($0)] as [String: AnyCodable] }
            gallery["labels"] = AnyCodable([
                "$type": AnyCodable("com.atproto.label.defs#selfLabels"),
                "values": AnyCodable(values as [[String: AnyCodable]]),
            ] as [String: AnyCodable])
        }
        if let location {
            gallery["location"] = AnyCodable([
                "value": AnyCodable(location.h3),
                "name": AnyCodable(location.name),
            ] as [String: AnyCodable])
            if let address = location.address {
                gallery["address"] = AnyCodable(address)
            }
        }
        writes.append(.create(collection: "social.grain.gallery", rkey: galleryRkey, value: AnyCodable(gallery)))

        var position = 0
        for photo in photos where photo.blob != nil {
            let item: [String: AnyCodable] = [
                "gallery": AnyCodable(galleryUri),
                "item": AnyCodable(photoUri(photo)),
                "position": AnyCodable(position),
                "createdAt": AnyCodable(createdAt),
            ]
            writes.append(.create(collection: "social.grain.gallery.item", rkey: photo.itemRkey, value: AnyCodable(item)))
            position += 1
        }

        return writes
    }

    private func blobDict(_ blob: BlobRef) -> [String: AnyCodable] {
        [
            "$type": AnyCodable(blob.type ?? "blob"),
            "ref": AnyCodable(["$link": AnyCodable(blob.ref?.link ?? "")] as [String: AnyCodable]),
            "mimeType": AnyCodable(blob.mimeType ?? "image/jpeg"),
            "size": AnyCodable(blob.size ?? 0),
        ]
    }
}

// MARK: - Disk store

/// On-disk home for drafts that are mid-publish.
///
/// Lives in Application Support rather than Caches: a half-uploaded gallery is
/// the user's unsaved work, and the system is free to evict Caches at any time.
/// Excluded from backup — these are short-lived and can be several megabytes of
/// JPEG each.
final class GalleryDraftStore: Sendable {
    static let shared = GalleryDraftStore()

    private let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = support.appendingPathComponent("grain_pending_galleries", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableRoot = self.root
        try? mutableRoot.setResourceValues(resourceValues)
    }

    func directory(for draftID: UUID) -> URL {
        root.appendingPathComponent(draftID.uuidString, isDirectory: true)
    }

    func imageURL(draftID: UUID, fileName: String) -> URL {
        directory(for: draftID).appendingPathComponent(fileName)
    }

    func writeImage(_ data: Data, draftID: UUID, fileName: String) throws {
        let directory = directory(for: draftID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    func readImage(draftID: UUID, fileName: String) throws -> Data {
        try Data(contentsOf: imageURL(draftID: draftID, fileName: fileName))
    }

    /// Persist the draft's progress. Called after every uploaded blob, so an
    /// upload that dies on photo 14 of 20 resumes at 14 rather than at 1.
    func save(_ draft: GalleryDraft) {
        do {
            let directory = directory(for: draft.id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(draft)
            try data.write(to: directory.appendingPathComponent("draft.json"), options: .atomic)
        } catch {
            logger.error("Failed to save draft \(draft.id): \(error.localizedDescription)")
        }
    }

    /// How long an unfinished draft is kept before it's written off. A gallery
    /// that hasn't managed to post in a week isn't going to, and each one can
    /// be twenty megabytes of JPEG sitting in Application Support.
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    /// The draft as last checkpointed, which is the authoritative record of how
    /// far a publish actually got.
    func load(_ draftID: UUID) -> GalleryDraft? {
        guard let data = try? Data(contentsOf: directory(for: draftID).appendingPathComponent("draft.json")) else {
            return nil
        }
        return try? JSONDecoder().decode(GalleryDraft.self, from: data)
    }

    /// Every draft still on disk, oldest first. Expired drafts and directories
    /// with no readable `draft.json` are swept up on the way past.
    func loadAll(now: Date = Date()) -> [GalleryDraft] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries.compactMap { entry -> GalleryDraft? in
            guard let data = try? Data(contentsOf: entry.appendingPathComponent("draft.json")),
                  let draft = try? JSONDecoder().decode(GalleryDraft.self, from: data)
            else {
                try? FileManager.default.removeItem(at: entry)
                return nil
            }
            if let created = DateFormatting.parse(draft.createdAt),
               now.timeIntervalSince(created) > Self.maxAge
            {
                logger.info("Discarding gallery draft \(draft.id) — unfinished for over a week")
                delete(draft.id)
                return nil
            }
            return draft
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    func delete(_ draftID: UUID) {
        try? FileManager.default.removeItem(at: directory(for: draftID))
    }
}

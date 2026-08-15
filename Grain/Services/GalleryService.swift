import Foundation

/// Shared helpers for `social.grain.gallery` records.
///
/// Deleting a gallery goes through `social.grain.unspecced.deleteGallery`, not
/// a plain `deleteRecord` on the collection. A gallery is the head of a small
/// graph — photos, the gallery items linking them, exif records, and comments —
/// and only the unspecced endpoint walks it. Deleting the gallery record on its
/// own leaves all of that orphaned in the repo while the UI, which promises
/// "this will permanently delete this gallery and all its photos", looks like
/// it worked.
///
/// That's not hypothetical: six of the seven places you can delete a gallery
/// used `deleteRecord` directly until 2026-08-14. Everything routes through
/// here now so there's one decision to get wrong instead of seven.
enum GalleryService {
    static let collection = "social.grain.gallery"

    /// Deletes a gallery and everything hanging off it, by full URI.
    static func delete(
        galleryUri: String,
        client: XRPCClient,
        auth: AuthContext
    ) async throws {
        let rkey = galleryUri.split(separator: "/").last.map(String.init) ?? ""
        try await client.deleteGallery(rkey: rkey, auth: auth)
    }
}

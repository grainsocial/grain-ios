import Foundation

enum DeepLink: Equatable {
    case profile(did: String)
    case gallery(did: String, rkey: String, commentUri: String? = nil)
    case story(did: String, rkey: String)

    static func from(url: URL) -> DeepLink? {
        // Normalize: for grain:// scheme, host is the first segment (e.g. grain://profile/did/...)
        // For https, path starts with /profile/did/...
        let segments: [String] = if url.scheme == "grain", let host = url.host {
            [host] + url.pathComponents.filter { $0 != "/" }
        } else {
            url.pathComponents.filter { $0 != "/" }
        }

        guard segments.first == "profile", segments.count >= 2 else { return nil }
        let did = segments[1]

        if segments.count >= 4, segments[2] == "gallery" {
            return .gallery(did: did, rkey: segments[3])
        }

        if segments.count >= 4, segments[2] == "story" {
            return .story(did: did, rkey: segments[3])
        }

        return .profile(did: did)
    }

    var galleryUri: String? {
        if case let .gallery(did, rkey, _) = self {
            return "at://\(did)/social.grain.gallery/\(rkey)"
        }
        return nil
    }
}

/// Carries gallery navigation context through `.navigationDestination(item:)`,
/// which only accepts a single `Identifiable & Hashable` value.
struct GalleryDeepLinkTarget: Identifiable, Hashable {
    let uri: String
    let commentUri: String?

    var id: String {
        uri + "|" + (commentUri ?? "")
    }
}

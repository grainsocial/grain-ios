import Foundation

enum DeepLink: Equatable {
    case profile(did: String)
    case gallery(did: String, rkey: String)
    case story(did: String, rkey: String)

    static func from(url: URL) -> DeepLink? {
        // Normalize: for grain:// scheme, host is the first segment (e.g. grain://profile/did/...)
        // For https, path starts with /profile/did/...
        var segments: [String]
        if url.scheme == "grain", let host = url.host {
            segments = [host] + url.pathComponents.filter { $0 != "/" }
        } else {
            segments = url.pathComponents.filter { $0 != "/" }
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
        if case .gallery(let did, let rkey) = self {
            return "at://\(did)/social.grain.gallery/\(rkey)"
        }
        return nil
    }
}

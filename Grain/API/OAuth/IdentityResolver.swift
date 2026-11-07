import Foundation

/// An account as its DID document describes it.
struct ResolvedIdentity: Sendable, Equatable {
    let did: String
    /// The handle the DID document claims, when it resolves back to the DID.
    let handle: String?
    /// The `#atproto_pds` service endpoint.
    let pds: URL
}

/// Handle and DID resolution, as atproto's OAuth asks a client to do before
/// it knows where an account signs in.
///
/// A handle resolves through its own `/.well-known/atproto-did` first, then
/// through `com.atproto.identity.resolveHandle` at the AppView: the resolvers,
/// in the order, that grain's CLI uses. A DID document comes from the PLC
/// directory for `did:plc`, or from its host for `did:web`.
struct IdentityResolver: Sendable {
    let session: URLSession
    var handleService = URL(string: "https://public.api.bsky.app")!
    var plcDirectory = URL(string: "https://plc.directory")!

    /// How long a lookup at a host the name alone points to may take: any
    /// name can point at a host that takes the connection and never answers.
    static let lookupTimeout: TimeInterval = 3

    /// Resolve what the user typed, a handle (with or without `@`) or a DID.
    func resolve(_ identifier: String) async throws -> ResolvedIdentity {
        let typed = Self.normalize(identifier)
        guard !typed.isEmpty else { throw OAuthError.handleRequired }

        if typed.hasPrefix("did:") {
            let document = try await document(for: typed)
            let pds = try Self.pds(in: document, did: typed)
            // Use the handle the document claims only if it resolves back.
            var handle: String?
            if let claimed = document.handle, let back = try? await resolveHandle(claimed), back == typed {
                handle = claimed
            }
            return ResolvedIdentity(did: typed, handle: handle, pds: pds)
        }

        guard Self.looksLikeHandle(typed) else { throw OAuthError.handleNotFound(typed) }
        let did = try await resolveHandle(typed)
        let document = try await document(for: did)
        let pds = try Self.pds(in: document, did: did)
        let claims = document.alsoKnownAs?.contains { $0.lowercased() == "at://\(typed)" } ?? false
        return ResolvedIdentity(did: did, handle: claims ? typed : nil, pds: pds)
    }

    /// A handle's DID, from the first resolver that answers with one.
    func resolveHandle(_ handle: String) async throws -> String {
        if let did = try? await wellKnown(handle) {
            return did
        }
        var components = URLComponents(
            url: handleService.appendingPathComponent("xrpc/com.atproto.identity.resolveHandle"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "handle", value: handle)]
        struct Resolved: Decodable { let did: String }
        if let url = components.url,
           case let (data, response)? = try? await session.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let resolved = try? JSONDecoder().decode(Resolved.self, from: data),
           resolved.did.hasPrefix("did:")
        {
            return resolved.did
        }
        throw OAuthError.handleNotFound(handle)
    }

    private func wellKnown(_ handle: String) async throws -> String {
        guard let url = URL(string: "https://\(handle)/.well-known/atproto-did") else { throw OAuthError.handleNotFound(handle) }
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.lookupTimeout
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let did = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              did.hasPrefix("did:")
        else { throw OAuthError.handleNotFound(handle) }
        return did
    }

    /// `did`'s DID document.
    func document(for did: String) async throws -> DIDDocument {
        var request: URLRequest
        if did.hasPrefix("did:plc:") {
            request = URLRequest(url: plcDirectory.appendingPathComponent(did))
        } else if did.hasPrefix("did:web:") {
            let host = String(did.dropFirst("did:web:".count)).replacingOccurrences(of: "%3A", with: ":")
            guard let url = URL(string: "https://\(host)/.well-known/did.json") else { throw OAuthError.unsupportedDID(did) }
            request = URLRequest(url: url)
            request.timeoutInterval = Self.lookupTimeout
        } else {
            throw OAuthError.unsupportedDID(did)
        }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let document = try? JSONDecoder().decode(DIDDocument.self, from: data)
        else { throw OAuthError.noPDS(did) }
        return document
    }

    static func pds(in document: DIDDocument, did: String) throws -> URL {
        guard let endpoint = document.service?.first(where: { $0.id.hasSuffix("#atproto_pds") })?.serviceEndpoint,
              let url = URL(string: endpoint), url.scheme == "https" || url.scheme == "http"
        else { throw OAuthError.noPDS(did) }
        return url
    }

    static func normalize(_ identifier: String) -> String {
        var typed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.hasPrefix("@") {
            typed.removeFirst()
        }
        return typed.hasPrefix("did:") ? typed : typed.lowercased()
    }

    /// Enough of atproto's handle syntax to keep a typo off the network:
    /// dot-separated labels of letters, digits and hyphens.
    static func looksLikeHandle(_ handle: String) -> Bool {
        let labels = handle.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, handle.count <= 253 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }
}

/// The parts of a DID document sign-in reads.
struct DIDDocument: Decodable, Sendable {
    struct Service: Decodable, Sendable {
        let id: String
        let serviceEndpoint: String?

        enum CodingKeys: String, CodingKey {
            case id
            case serviceEndpoint
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            // An endpoint may be an object or a list; only a URL string is a PDS.
            serviceEndpoint = try? container.decode(String.self, forKey: .serviceEndpoint)
        }
    }

    let id: String?
    let alsoKnownAs: [String]?
    let service: [Service]?

    /// The handle in the first `at://` alias.
    var handle: String? {
        alsoKnownAs?.first { $0.hasPrefix("at://") }.map { String($0.dropFirst("at://".count)).lowercased() }
    }
}

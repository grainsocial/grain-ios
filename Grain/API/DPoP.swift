import CryptoKit
import Foundation
import Security

/// DPoP (Demonstration of Proof-of-Possession) proof generator using ES256.
final class DPoP: Sendable {
    private let privateKey: P256.Signing.PrivateKey
    let publicJWK: [String: String]
    let thumbprint: String

    init(privateKey: P256.Signing.PrivateKey) {
        self.privateKey = privateKey
        let publicKey = privateKey.publicKey
        let rawRepresentation = publicKey.rawRepresentation
        let xCoord = rawRepresentation.prefix(32)
        let yCoord = rawRepresentation.suffix(32)

        publicJWK = [
            "kty": "EC",
            "crv": "P-256",
            "x": xCoord.base64URLEncoded(),
            "y": yCoord.base64URLEncoded(),
        ]

        // JWK thumbprint (RFC 7638) — lexicographic JSON of required members
        let thumbprintInput = #"{"crv":"P-256","kty":"EC","x":"\#(xCoord.base64URLEncoded())","y":"\#(yCoord.base64URLEncoded())"}"#
        let hash = SHA256.hash(data: Data(thumbprintInput.utf8))
        thumbprint = Data(hash).base64URLEncoded()
    }

    /// Create a DPoP proof JWT.
    func createProof(
        httpMethod: String,
        url: URL,
        accessToken: String? = nil,
        nonce: String? = nil
    ) async throws -> String {
        // Normalize URL: scheme + host + path (no query)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.query = nil
        components.fragment = nil
        let htu = components.url!.absoluteString

        // Header
        let header: [String: Any] = [
            "typ": "dpop+jwt",
            "alg": "ES256",
            "jwk": publicJWK,
        ]

        // Payload
        var payload: [String: Any] = [
            "jti": UUID().uuidString,
            "htm": httpMethod.uppercased(),
            "htu": htu,
            "iat": Int(Date().timeIntervalSince1970),
        ]

        if let accessToken {
            let tokenHash = SHA256.hash(data: Data(accessToken.utf8))
            payload["ath"] = Data(tokenHash).base64URLEncoded()
        }

        if let nonce {
            payload["nonce"] = nonce
        }

        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        let signingInput = headerData.base64URLEncoded() + "." + payloadData.base64URLEncoded()
        let signature = try privateKey.signature(for: Data(signingInput.utf8))

        return signingInput + "." + signature.rawRepresentation.base64URLEncoded()
    }
}

// MARK: - Key Management

extension DPoP {
    private static let keychainService = "social.grain.dpop"
    private static let keychainAccount = "dpop-private-key"

    /// Load existing key from Keychain or generate a new one.
    static func loadOrCreate() throws -> DPoP {
        if let existingKey = try loadFromKeychain() {
            return DPoP(privateKey: existingKey)
        }
        let newKey = P256.Signing.PrivateKey()
        try saveToKeychain(newKey)
        return DPoP(privateKey: newKey)
    }

    /// Remove the stored key (for logout).
    static func clearKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func loadFromKeychain() throws -> P256.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try P256.Signing.PrivateKey(rawRepresentation: data)
    }

    private static func saveToKeychain(_ key: P256.Signing.PrivateKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: key.rawRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

// MARK: - Base64URL

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

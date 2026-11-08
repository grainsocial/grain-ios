import Foundation

/// The label definitions every card resolves a gallery's labels against,
/// read from grain-serve's `social.grain.moderation.describeLabels` once,
/// and kept for the next launch. Until that answers, and when it cannot,
/// the last ones read stand, or else the copy the app carries.
@Observable
@MainActor
final class LabelDefinitionsCache {
    private(set) var definitions: [LabelDefinition]
    private var hasLoaded = false

    static let storageKey = "labelDefinitions.v1"

    init(definitions: [LabelDefinition]? = nil) {
        self.definitions = definitions ?? Self.stored() ?? LabelDefinition.all
    }

    func loadIfNeeded(client: XRPCClient, auth: AuthContext?) async {
        guard !hasLoaded else { return }
        do {
            let fetched = try await client.describeLabels(auth: auth)
            hasLoaded = true
            guard !fetched.isEmpty else { return }
            definitions = fetched
            if let data = try? JSONEncoder().encode(fetched) {
                StorageEnvironment.defaults.set(data, forKey: Self.storageKey)
            }
        } catch {
            // Keep what there is; the next call asks again.
        }
    }

    private static func stored() -> [LabelDefinition]? {
        guard let data = StorageEnvironment.defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode([LabelDefinition].self, from: data)
    }
}

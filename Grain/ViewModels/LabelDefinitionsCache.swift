import Foundation

@Observable
@MainActor
final class LabelDefinitionsCache {
    private(set) var definitions: [LabelDefinition] = []
    private var hasLoaded = false

    func loadIfNeeded(client: XRPCClient, auth: AuthContext?) async {
        guard !hasLoaded else { return }
        do {
            definitions = try await client.describeLabels(auth: auth)
            hasLoaded = true
        } catch {
            // Use empty definitions — fallbacks will handle well-known labels
        }
    }
}

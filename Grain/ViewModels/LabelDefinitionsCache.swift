import Foundation
import os

private let labelsSignposter = OSSignposter(subsystem: "social.grain.grain", category: "AppLaunch")

@Observable
@MainActor
final class LabelDefinitionsCache {
    private(set) var definitions: [LabelDefinition] = []
    private var hasLoaded = false

    nonisolated func loadIfNeeded(client: XRPCClient, auth: AuthContext?) async {
        let spid = labelsSignposter.makeSignpostID()
        let state = labelsSignposter.beginInterval("Labels.loadIfNeeded", id: spid)
        defer { labelsSignposter.endInterval("Labels.loadIfNeeded", state) }

        let alreadyLoaded = await MainActor.run { self.hasLoaded }
        guard !alreadyLoaded else { return }

        do {
            let netSpid = labelsSignposter.makeSignpostID()
            let netState = labelsSignposter.beginInterval("Labels.network", id: netSpid)
            let defs = try await client.describeLabels(auth: auth)
            labelsSignposter.endInterval("Labels.network", netState)

            await MainActor.run {
                self.definitions = defs
                self.hasLoaded = true
            }
        } catch {
            // Use empty definitions — fallbacks will handle well-known labels
        }
    }
}

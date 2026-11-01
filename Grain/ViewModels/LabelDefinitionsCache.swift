import Foundation

/// The label definitions every card resolves a gallery's labels against:
/// grain's own, which the app carries.
@Observable
@MainActor
final class LabelDefinitionsCache {
    let definitions: [LabelDefinition]

    init(definitions: [LabelDefinition] = LabelDefinition.all) {
        self.definitions = definitions
    }
}

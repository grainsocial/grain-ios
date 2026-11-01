@testable import Grain
import XCTest

/// The cache is read during every card's body evaluation to decide whether a
/// gallery is blurred. It holds grain's own definitions, which the app
/// carries, so it resolves labels before any request is made.
@MainActor
final class LabelDefinitionsCacheTests: GrainTestCase {
    func testItHoldsGrainsDefinitionsFromTheStart() {
        let cache = LabelDefinitionsCache()

        XCTAssertEqual(
            cache.definitions.map(\.identifier),
            ["copyright", "csae", "gore", "harassment", "misleading", "nudity", "other", "sexual", "spam"]
        )
        XCTAssertEqual(cache.definitions.first?.id, "copyright", "Definitions are identified by their label value")
    }

    /// The display name comes from the locale list, falling back to the raw
    /// label value so an unlocalised definition still reads as something.
    func testTheDisplayNameFallsBackToTheIdentifier() {
        XCTAssertEqual(LabelDefinition.all.first { $0.identifier == "gore" }?.displayName, "Graphic Media")
        XCTAssertEqual(LabelDefinition(identifier: "spoiler").displayName, "spoiler")
    }

    /// grain's definition beats the built-in fallback for a value both know.
    func testGrainsDefinitionOverridesTheFallbackTable() {
        let cache = LabelDefinitionsCache(definitions: [
            LabelDefinition(identifier: "nudity", blurs: "content", defaultSetting: "warn"),
        ])

        let resolved = resolveLabels(
            [ATLabel(src: nil, uri: nil, val: "nudity", cts: nil)],
            definitions: cache.definitions
        )
        XCTAssertEqual(resolved.action, .warnContent, "Fallback would have given warnMedia")
    }

    /// With no definitions, `resolveLabels` still has its built-in fallbacks
    /// for the well-known values.
    func testNoDefinitionsStillResolveWellKnownLabels() {
        let cache = LabelDefinitionsCache(definitions: [])

        XCTAssertEqual(
            resolveLabels([ATLabel(src: nil, uri: nil, val: "nudity", cts: nil)], definitions: cache.definitions).action,
            .warnMedia
        )
    }

    /// Every label has the reason a report for it names, the one grain-serve
    /// files under that label.
    func testEveryLabelHasAReportReason() {
        for definition in LabelDefinition.all {
            XCTAssertNotNil(LabelDefinition.reportReasons[definition.identifier], definition.identifier)
        }
        XCTAssertEqual(LabelDefinition.reasonType(for: "harassment"), "com.atproto.moderation.defs#reasonRude")
        XCTAssertEqual(LabelDefinition.reasonType(for: "unheard-of"), "com.atproto.moderation.defs#reasonOther")
    }
}

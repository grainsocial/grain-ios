import XCTest
@testable import Grain

final class LabelResolutionTests: XCTestCase {

    // MARK: - LabelAction ordering

    func testLabelActionSeverityOrder() {
        XCTAssertTrue(LabelAction.none < .badge)
        XCTAssertTrue(LabelAction.badge < .warnMedia)
        XCTAssertTrue(LabelAction.warnMedia < .warnContent)
        XCTAssertTrue(LabelAction.warnContent < .hide)
    }

    // MARK: - resolveLabels with nil/empty

    func testNilLabelsReturnsNone() {
        let result = resolveLabels(nil, definitions: [])
        XCTAssertEqual(result.action, .none)
    }

    func testEmptyLabelsReturnsNone() {
        let result = resolveLabels([], definitions: [])
        XCTAssertEqual(result.action, .none)
    }

    func testLabelWithNilValIsSkipped() {
        let label = ATLabel(src: nil, uri: nil, val: nil, cts: nil)
        let result = resolveLabels([label], definitions: [])
        XCTAssertEqual(result.action, .none)
    }

    func testLabelWithEmptyValIsSkipped() {
        let label = ATLabel(src: nil, uri: nil, val: "", cts: nil)
        let result = resolveLabels([label], definitions: [])
        XCTAssertEqual(result.action, .none)
    }

    // MARK: - Fallback definitions

    func testPornFallbackToWarnMedia() {
        let label = ATLabel(src: nil, uri: nil, val: "porn", cts: nil)
        let result = resolveLabels([label], definitions: [])
        XCTAssertEqual(result.action, .warnMedia)
        XCTAssertEqual(result.label, "porn")
    }

    func testGoreFallbackToWarnMedia() {
        // gore has blurs=media, setting=hide -> warnMedia (media + hide = warnMedia)
        let label = ATLabel(src: nil, uri: nil, val: "gore", cts: nil)
        let result = resolveLabels([label], definitions: [])
        XCTAssertEqual(result.action, .warnMedia)
    }

    func testDMCAFallbackToHide() {
        // dmca-violation has blurs=content, setting=hide -> hide
        let label = ATLabel(src: nil, uri: nil, val: "dmca-violation", cts: nil)
        let result = resolveLabels([label], definitions: [])
        XCTAssertEqual(result.action, .hide)
    }

    func testDoxxingFallbackToHide() {
        let label = ATLabel(src: nil, uri: nil, val: "doxxing", cts: nil)
        let result = resolveLabels([label], definitions: [])
        XCTAssertEqual(result.action, .hide)
    }

    func testBangHideFallback() {
        let label = ATLabel(src: nil, uri: nil, val: "!hide", cts: nil)
        let result = resolveLabels([label], definitions: [])
        XCTAssertEqual(result.action, .hide)
    }

    func testBangWarnFallback() {
        let label = ATLabel(src: nil, uri: nil, val: "!warn", cts: nil)
        let result = resolveLabels([label], definitions: [])
        XCTAssertEqual(result.action, .warnContent)
    }

    // MARK: - Unknown labels

    func testUnknownLabelFallsToBadge() {
        let label = ATLabel(src: nil, uri: nil, val: "totally-unknown", cts: nil)
        let result = resolveLabels([label], definitions: [])
        XCTAssertEqual(result.action, .badge)
        XCTAssertEqual(result.label, "totally-unknown")
    }

    // MARK: - Server-provided definitions

    func testServerDefinitionOverridesFallback() {
        let def = LabelDefinition(
            identifier: "porn",
            locales: [LabelLocale(name: "Adult")],
            blurs: "content",
            defaultSetting: "hide"
        )
        let label = ATLabel(src: nil, uri: nil, val: "porn", cts: nil)
        let result = resolveLabels([label], definitions: [def])
        // content + hide = .hide (server says hide, overriding fallback's warnMedia)
        XCTAssertEqual(result.action, .hide)
        XCTAssertEqual(result.name, "Adult")
    }

    func testServerDefinitionWithWarnSetting() {
        let def = LabelDefinition(
            identifier: "custom-label",
            locales: [LabelLocale(name: "Custom Warning")],
            blurs: "media",
            defaultSetting: "warn"
        )
        let label = ATLabel(src: nil, uri: nil, val: "custom-label", cts: nil)
        let result = resolveLabels([label], definitions: [def])
        XCTAssertEqual(result.action, .warnMedia)
        XCTAssertEqual(result.name, "Custom Warning")
    }

    // MARK: - Worst wins

    func testWorstActionWins() {
        let labels = [
            ATLabel(src: nil, uri: nil, val: "nudity", cts: nil),       // warnMedia
            ATLabel(src: nil, uri: nil, val: "dmca-violation", cts: nil) // hide
        ]
        let result = resolveLabels(labels, definitions: [])
        XCTAssertEqual(result.action, .hide)
        XCTAssertEqual(result.label, "dmca-violation")
    }

    func testMultipleSameSeverityKeepsFirst() {
        // Both are warnMedia — the first one encountered at that severity stays
        let labels = [
            ATLabel(src: nil, uri: nil, val: "porn", cts: nil),
            ATLabel(src: nil, uri: nil, val: "nudity", cts: nil)
        ]
        let result = resolveLabels(labels, definitions: [])
        XCTAssertEqual(result.action, .warnMedia)
        XCTAssertEqual(result.label, "porn")
    }
}

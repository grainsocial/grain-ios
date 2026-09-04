@testable import Grain
import XCTest

/// Decides whether a caption gets a "translate" affordance. Detection is
/// `NLLanguageRecognizer`, which is slow enough that the answer is memoized —
/// so the cache has to give the same answer as a cold call, not a stale one.
final class LanguageDetectorTests: GrainTestCase {
    private var readerReadsEnglish: Bool {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("en")
    }

    /// The verdict is relative to the reader's own language, so anything
    /// asserting "foreign" only means something on an English simulator.
    private func requireEnglishReader() throws {
        try XCTSkipUnless(readerReadsEnglish, "Reader isn't English; there's no foreign/native split to assert")
    }

    func testTextInTheReadersOwnLanguageIsNotForeign() async throws {
        try requireEnglishReader()

        let foreign = await LanguageDetector.shared.isForeign(
            "Shot on a grey afternoon just before the rain came in over the harbour."
        )

        XCTAssertFalse(foreign)
    }

    func testTextInAnotherLanguageIsForeign() async throws {
        try requireEnglishReader()

        let foreign = await LanguageDetector.shared.isForeign(
            "Fotografia tirada numa tarde cinzenta, mesmo antes de a chuva chegar sobre o porto."
        )

        XCTAssertTrue(foreign)
    }

    /// Cards re-parse the same caption every time they re-enter the lazy stack,
    /// which is the whole reason for the cache — the second answer has to match
    /// the first.
    func testTheCachedAnswerMatchesTheFirstOne() async {
        let text = "Uma fotografia tirada ao pôr do sol sobre a cidade velha."

        let first = await LanguageDetector.shared.isForeign(text)
        let second = await LanguageDetector.shared.isForeign(text)

        XCTAssertEqual(first, second)
    }

    /// An empty caption has no language to detect, so there is nothing to
    /// offer a translation of.
    func testEmptyTextIsNotForeign() async {
        for text in ["", "   "] {
            let foreign = await LanguageDetector.shared.isForeign(text)
            XCTAssertFalse(foreign, "\"\(text)\" shouldn't offer a translation")
        }
    }

    /// A caption that is just a hashtag, an emoji or a number gives the
    /// recogniser almost nothing to go on, and left to itself it will name a
    /// language anyway — which is how an offer to translate ends up under a
    /// caption with no prose in it.
    func testACaptionWithNoProseIsNeverForeign() async {
        for text in ["📷", "📷🎞️", "#35mm", "123 456", "f/2.8", "1/500s"] {
            let foreign = await LanguageDetector.shared.isForeign(text)
            XCTAssertFalse(foreign, "\"\(text)\" shouldn't offer a translation")
        }
    }

    /// The guard is on how much prose there is, not on how the caption starts —
    /// a real sentence with a hashtag in it still gets detected.
    func testAHashtagDoesNotSuppressARealCaption() async throws {
        try requireEnglishReader()

        let foreign = await LanguageDetector.shared.isForeign(
            "#Portra400 revelado esta manhã, com uma luz muito suave sobre o rio."
        )

        XCTAssertTrue(foreign)
    }

    /// Two different captions must not share an answer — a cache keyed wrongly
    /// would put a translate button under every caption after the first
    /// foreign one.
    func testDifferentCaptionsGetTheirOwnAnswers() async throws {
        try requireEnglishReader()

        let english = await LanguageDetector.shared.isForeign(
            "A quiet street in the old town, photographed just after sunrise."
        )
        let portuguese = await LanguageDetector.shared.isForeign(
            "Uma rua tranquila na cidade velha, fotografada logo depois do nascer do sol."
        )

        XCTAssertFalse(english)
        XCTAssertTrue(portuguese)
    }
}

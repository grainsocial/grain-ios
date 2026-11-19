@testable import Grain
import XCTest

final class BlueskyPostTests: GrainTestCase {
    private let url = "https://grain.social/profile/did:plc:abc/gallery/xyz"

    func testBuildPostText_Title_IsFollowedByABlankLineAndTheLink() {
        let text = BlueskyPost.buildPostText(url: url, title: "Golden hour")

        XCTAssertEqual(text, "Golden hour\n\n#GrainSocial \(url)")
    }

    /// Stories and untitled galleries post the hashtag and link alone.
    func testBuildPostText_NoTitle_IsJustTheLink() {
        XCTAssertEqual(BlueskyPost.buildPostText(url: url, title: nil), "#GrainSocial \(url)")
        XCTAssertEqual(BlueskyPost.buildPostText(url: url, title: ""), "#GrainSocial \(url)")
    }

    func testBuildPostText_TitleIsTrimmed() {
        let text = BlueskyPost.buildPostText(url: url, title: "  Golden hour \n")

        XCTAssertEqual(text, "Golden hour\n\n#GrainSocial \(url)")
    }

    func testBuildPostText_WhitespaceTitle_IsJustTheLink() {
        XCTAssertEqual(BlueskyPost.buildPostText(url: url, title: " \n "), "#GrainSocial \(url)")
    }

    /// The budget pays for the two joining newlines too: without them a
    /// truncated post lands over 300 graphemes and the PDS rejects it.
    func testBuildPostText_LongTitle_FitsGraphemeLimit() {
        let text = BlueskyPost.buildPostText(url: url, title: String(repeating: "a", count: 600))

        XCTAssertEqual(text.count, 300)
        XCTAssertLessThanOrEqual(text.utf8.count, 3000)
        XCTAssertTrue(text.hasSuffix("…\n\n#GrainSocial \(url)"))
    }

    /// Multi-byte content is capped by graphemes, not by bytes.
    func testBuildPostText_LongEmojiTitle_FitsBothLimits() {
        let text = BlueskyPost.buildPostText(url: url, title: String(repeating: "🌄", count: 400))

        XCTAssertLessThanOrEqual(text.count, 300)
        XCTAssertLessThanOrEqual(text.utf8.count, 3000)
        XCTAssertTrue(text.hasSuffix("#GrainSocial \(url)"))
    }

    /// Graphemes made of many bytes hit the byte cap before the grapheme cap.
    func testBuildPostText_ManyByteGraphemes_FitByteLimit() {
        let family = "👨‍👩‍👧‍👦" // one grapheme, 25 bytes
        let text = BlueskyPost.buildPostText(url: url, title: String(repeating: family, count: 250))

        XCTAssertLessThanOrEqual(text.count, 300)
        XCTAssertLessThanOrEqual(text.utf8.count, 3000)
        XCTAssertTrue(text.hasSuffix("…\n\n#GrainSocial \(url)"))
    }

    /// A URL long enough to eat the whole budget drops the title rather than
    /// emitting a lone ellipsis that still overflows.
    func testBuildPostText_SuffixFillsBudget_DropsTitle() {
        let longURL = "https://grain.social/" + String(repeating: "x", count: 400)
        let text = BlueskyPost.buildPostText(url: longURL, title: "Autumn walk")

        XCTAssertEqual(text, "#GrainSocial \(longURL)")
    }
}

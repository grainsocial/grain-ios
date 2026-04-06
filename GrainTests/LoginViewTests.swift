@testable import Grain
import XCTest

@MainActor
final class LoginViewTests: XCTestCase {
    func testLegalTextContainsAllThreeLinks() throws {
        let attributed = try AttributedString(markdown: LoginView.legalMarkdown)
        var urls: [String] = []
        for run in attributed.runs {
            if let url = run.link {
                urls.append(url.absoluteString)
            }
        }
        XCTAssertTrue(urls.contains("https://grain.social/support/terms"), "Missing Terms link")
        XCTAssertTrue(urls.contains("https://grain.social/support/privacy"), "Missing Privacy Policy link")
        XCTAssertTrue(urls.contains("https://grain.social/support/community-guidelines"), "Missing Community Guidelines link")
        XCTAssertEqual(urls.count, 3, "Expected exactly 3 links")
    }
}

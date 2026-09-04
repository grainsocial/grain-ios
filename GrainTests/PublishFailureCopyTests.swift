import CryptoKit
@testable import Grain
import XCTest

/// What the publish overlay tells someone when a gallery doesn't go out.
///
/// This copy is the entire failure experience — the overlay covers the sheet
/// and offers "try again" or "post later" against it — so a message that says
/// the wrong thing sends people to the wrong remedy. Every branch here has to
/// say what happened and reassure that the work is still on the device.
@MainActor
final class PublishFailureCopyTests: GrainTestCase {
    private func message(_ error: Error) -> String {
        GalleryUploadCenter.message(for: error)
    }

    // MARK: - Connection problems

    /// Offline is the one case where trying again immediately is pointless, so
    /// it gets its own wording.
    func testBeingOfflineSaysSoAndPromisesTheWorkIsSaved() {
        let copy = message(URLError(.notConnectedToInternet))

        XCTAssertTrue(copy.contains("offline"))
        XCTAssertTrue(copy.lowercased().contains("saved"), "The reassurance is the point: \(copy)")
    }

    /// A connection that dropped mid-upload resumes from where it stopped, so
    /// the copy says as much rather than implying a restart.
    func testADroppedConnectionSaysNothingWasLost() {
        for code in [URLError.Code.timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed] {
            let copy = message(URLError(code))
            XCTAssertTrue(copy.contains("Nothing was lost"), "\(code) said: \(copy)")
        }
    }

    /// A URL error the app doesn't have wording for still has to say something
    /// rather than fall through to an empty string.
    func testAnUnrecognisedURLErrorStillGetsAMessage() {
        let copy = message(URLError(.badURL))

        XCTAssertFalse(copy.isEmpty)
        XCTAssertTrue(copy.hasPrefix("Couldn't post"))
    }

    // MARK: - Server responses

    /// An expired session is the one failure with a specific remedy, and
    /// retrying isn't it.
    func testAnExpiredSessionSaysToSignInAgain() {
        let copy = message(XRPCError.unauthorized)

        XCTAssertTrue(copy.lowercased().contains("sign in"))
    }

    func testRateLimitingSaysToWait() {
        let copy = message(XRPCError.httpError(statusCode: 429, body: nil))

        XCTAssertTrue(copy.lowercased().contains("rate limit"))
    }

    /// A server error is worth retrying, so it reads like the dropped
    /// connection rather than like a rejection.
    func testAServerErrorIsPresentedAsWorthRetrying() {
        for status in [500, 503, 599] {
            let copy = message(XRPCError.httpError(statusCode: status, body: nil))
            XCTAssertTrue(copy.contains("Nothing was lost"), "HTTP \(status) said: \(copy)")
        }
    }

    /// A rejection the app has no wording for surfaces the server's own
    /// explanation — that is more use than a generic apology.
    func testAnUnrecognisedRejectionQuotesTheServer() {
        let copy = message(XRPCError.httpError(statusCode: 422, body: Data("blob too large".utf8)))

        XCTAssertTrue(copy.contains("422"))
        XCTAssertTrue(copy.contains("blob too large"))
    }

    func testARejectionWithNoBodyStillNamesTheStatus() {
        let copy = message(XRPCError.httpError(statusCode: 422, body: nil))

        XCTAssertTrue(copy.contains("422"))
        XCTAssertFalse(copy.hasSuffix(": "))
    }

    /// A decode failure isn't something the user can act on, but it still has
    /// to read as a sentence.
    func testAnUnrecognisedXRPCErrorStillGetsAMessage() {
        let copy = message(XRPCError.decodingError(URLError(.badServerResponse)))

        XCTAssertTrue(copy.hasPrefix("Couldn't post"))
    }

    // MARK: - Problems with the photos

    /// A photo the library won't hand over names itself, because the remedy is
    /// to remove that specific one.
    func testAnUnreadablePhotoNamesWhichOneToRemove() {
        let copy = message(GalleryDraftError.photoUnavailable(index: 2))

        XCTAssertTrue(copy.contains("Photo 3"), "Counted from one, as the picker shows them: \(copy)")
        XCTAssertTrue(copy.lowercased().contains("remove"))
    }

    // MARK: - Anything else

    func testAnyOtherErrorFallsBackToItsOwnDescription() {
        struct Odd: LocalizedError {
            var errorDescription: String? {
                "something specific went wrong"
            }
        }

        let copy = message(Odd())

        XCTAssertTrue(copy.contains("something specific went wrong"))
    }

    /// Every branch has to produce something a person can read — no empty
    /// strings, no debug formatting or type names leaking through.
    ///
    /// Deliberately not asserting punctuation: several of these end in text the
    /// server supplied, and that is not ours to tidy.
    func testEveryFailureProducesReadableCopy() {
        let errors: [Error] = [
            URLError(.notConnectedToInternet),
            URLError(.timedOut),
            URLError(.badURL),
            XRPCError.unauthorized,
            XRPCError.httpError(statusCode: 429, body: nil),
            XRPCError.httpError(statusCode: 500, body: nil),
            XRPCError.httpError(statusCode: 400, body: Data("nope".utf8)),
            XRPCError.decodingError(URLError(.badServerResponse)),
            XRPCError.invalidURL,
            GalleryDraftError.photoUnavailable(index: 0),
        ]

        for error in errors {
            let copy = message(error)
            XCTAssertFalse(copy.isEmpty, "\(error) produced no message")
            XCTAssertGreaterThan(copy.count, 10, "Too terse to be useful: \(copy)")
            XCTAssertFalse(copy.contains("Optional("), "Debug formatting leaked: \(copy)")
            XCTAssertFalse(copy.contains("Grain."), "A type name leaked: \(copy)")
        }
    }
}

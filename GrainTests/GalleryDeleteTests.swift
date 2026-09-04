import Foundation
@testable import Grain
import Testing

/// Deleting a gallery, which every screen showing a card can do.
///
/// Six screens used to run this inline with `try?` and drop the row locally
/// whether or not the server agreed, so a rejected delete was indistinguishable
/// from a successful one until the next refresh. These pin the reporting.
///
/// Written with Swift Testing rather than XCTest: it is the current default for
/// new tests, and the storage and session seams mean a test like this no longer
/// has to save and restore the real Keychain to be safe to run.
@MainActor
struct GalleryDeleteTests {
    private static let uri = "at://did:plc:test/social.grain.gallery/abc"

    @Test func aRejectedDeleteIsReportedRatherThanSwallowed() async {
        await withGrainEnvironment {
            let account = TestAccount()
            defer { account.restore() }
            let auth = AuthManager(session: MockURLProtocol.mockSession())
            await account.activate(auth)

            MockURLProtocol.respondWithError(statusCode: 500)
            defer { MockURLProtocol.handler = nil }

            let result = await GalleryService.delete(
                galleryUri: Self.uri,
                client: XRPCClient(baseURL: AuthManager.serverURL, session: MockURLProtocol.mockSession()),
                auth: auth
            )
            switch result {
            case .success:
                Issue.record("a 500 must not report success — that is the bug this replaced")
            case let .failure(error):
                #expect(!error.localizedDescription.isEmpty, "the screen has to have something to show")
            }
        }
    }

    @Test func anAcceptedDeleteSucceeds() async {
        await withGrainEnvironment {
            let account = TestAccount()
            defer { account.restore() }
            let auth = AuthManager(session: MockURLProtocol.mockSession())
            await account.activate(auth)

            MockURLProtocol.respondWithJSON("{}")
            defer { MockURLProtocol.handler = nil }

            let result = await GalleryService.delete(
                galleryUri: Self.uri,
                client: XRPCClient(baseURL: AuthManager.serverURL, session: MockURLProtocol.mockSession()),
                auth: auth
            )
            #expect(result.isSuccess)
        }
    }

    /// Signed out is the one failure reachable before the network, and it has to
    /// be distinguishable from a server error so the copy can differ.
    @Test func deletingWhileSignedOutFailsWithoutAskingTheServer() async {
        await withGrainEnvironment {
            var sawRequest = false
            MockURLProtocol.handler = { _ in
                sawRequest = true
                throw URLError(.badServerResponse)
            }
            defer { MockURLProtocol.handler = nil }

            let auth = AuthManager(session: MockURLProtocol.mockSession())
            let result = await GalleryService.delete(
                galleryUri: Self.uri,
                client: XRPCClient(baseURL: AuthManager.serverURL, session: MockURLProtocol.mockSession()),
                auth: auth
            )
            guard case let .failure(error) = result else {
                Issue.record("signed out cannot be a successful delete")
                return
            }
            #expect(error as? GalleryDeleteError == .notSignedIn)
            #expect(!sawRequest, "no point spending a round trip without credentials")
        }
    }
}

/// The state a gallery card's modals are driven by.
@MainActor
struct GalleryCardModalsTests {
    @Test func confirmingADeleteRecordsBothTheTargetAndTheFlag() {
        let modals = GalleryCardModals()
        #expect(modals.pendingDeleteUri == nil)
        #expect(!modals.isConfirmingDelete)

        modals.confirmDelete("at://g")

        // Two assignments that had to agree were made by hand on six screens.
        #expect(modals.pendingDeleteUri == "at://g")
        #expect(modals.isConfirmingDelete)
    }

    @Test func modalsStartClosed() {
        let modals = GalleryCardModals()
        #expect(modals.commentUri == nil)
        #expect(modals.report == nil)
        #expect(modals.storyAuthor == nil)
        #expect(modals.deleteError == nil)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

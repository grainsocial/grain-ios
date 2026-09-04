@testable import Grain
import XCTest

/// Pins the mechanism `GrainTestCase` relies on.
///
/// The load-bearing question is whether a task-local bound on `invokeTest`'s
/// synchronous stack is still bound inside an `async` test body, since XCTest
/// runs those on a task it creates itself. If that ever stops holding, every
/// credential test silently goes back to reading the real Keychain, so it is
/// worth asserting directly rather than inferring from tests that pass.
final class StorageNamespaceTests: GrainTestCase {
    func testNamespaceIsBoundInASynchronousTest() {
        XCTAssertEqual(StorageEnvironment.credentialService, "\(namespace).oauth")
        XCTAssertEqual(StorageEnvironment.defaultsSuiteName, namespace)
    }

    func testNamespaceIsBoundInAnAsyncTest() {
        XCTAssertEqual(StorageEnvironment.credentialService, "\(namespace).oauth")
        XCTAssertEqual(StorageEnvironment.dpopService, "\(namespace).dpop")
        XCTAssertEqual(StorageEnvironment.defaultsSuiteName, namespace)
    }

    func testNamespaceSurvivesAnAwaitAndAnUnstructuredTask() async {
        try? await Task.sleep(for: .milliseconds(1))
        XCTAssertEqual(StorageEnvironment.credentialService, "\(namespace).oauth")

        let inherited = await Task { StorageEnvironment.credentialService }.value
        XCTAssertEqual(inherited, "\(namespace).oauth", "unstructured Task should inherit the binding")
    }

    /// The point of the whole exercise: a write here must not be visible to the
    /// real store the installed app reads.
    func testCredentialsDoNotReachTheRealStore() {
        TokenStorage.activeDID = "did:plc:namespaced"
        XCTAssertEqual(TokenStorage.activeDID, "did:plc:namespaced")

        StorageEnvironment.$credentialService.withValue("social.grain.oauth") {
            XCTAssertNotEqual(TokenStorage.activeDID, "did:plc:namespaced",
                              "the real service must not see this test's write")
        }
    }
}

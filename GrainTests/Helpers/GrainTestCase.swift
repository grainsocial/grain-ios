@testable import Grain
import XCTest

/// Base class that gives every test its own Keychain services and `UserDefaults`
/// suite.
///
/// The unit-test bundle is hosted by the app, so it inherits the Keychain access
/// group and defaults suite of the copy of Grain installed on the simulator.
/// Before this, tests that touched credentials had to save the real values and
/// put them back in `tearDown`, and a crash between the two signed the developer
/// out. Binding the namespace around `invokeTest` means the real store is never
/// opened at all.
///
/// The binding is a task-local rather than a mutable global so it is scoped to
/// this test's task tree, which is what makes it safe if tests ever run
/// concurrently.
class GrainTestCase: XCTestCase {
    /// Unique per test, so a leftover value can't reach the next one.
    private(set) var namespace = ""

    override func invokeTest() {
        namespace = "grain.test.\(UUID().uuidString)"
        StorageEnvironment.withNamespace(namespace) {
            // Everything that isn't handed an explicit session goes through
            // `MockURLProtocol` too, so no test has to register a protocol class
            // against `URLSession.shared` for the whole process.
            NetworkEnvironment.$session.withValue(MockURLProtocol.mockSession()) {
                super.invokeTest()
            }
        }
    }
}

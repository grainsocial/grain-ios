import Foundation
@testable import Grain
import Testing

/// The Swift Testing counterpart of `GrainTestCase`.
///
/// Swift Testing has no `invokeTest` to hook, so the namespace is bound around
/// the body instead. Same guarantee: the Keychain services, the `UserDefaults`
/// suite and the fallback `URLSession` are this test's own, so nothing here can
/// read or overwrite the credentials of the app installed on the same simulator.
///
/// Because the binding is a task-local rather than a mutable global, tests using
/// this can run concurrently — which is the whole reason the storage seams
/// exist. Note `Task.detached` does not inherit it.
func withGrainEnvironment<T>(
    isolation: isolated (any Actor)? = #isolation,
    _ body: () async throws -> T
) async rethrows -> T {
    try await StorageEnvironment.withNamespace("grain.test.\(UUID().uuidString)", isolation: isolation) {
        try await NetworkEnvironment.$session.withValue(MockURLProtocol.mockSession(), operation: {
            try await body()
        }, isolation: isolation)
    }
}

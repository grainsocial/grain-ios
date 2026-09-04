import Foundation

/// The `URLSession` used by code that isn't handed one, overridable per task.
///
/// `XRPCClient` and `AuthManager` take a session explicitly, because they are
/// constructed somewhere a test can reach. The stragglers can't be: handle
/// resolution inside a login field, mention autocomplete, a link preview fetched
/// while building a cross-post. Those used `URLSession.shared`, which left tests
/// registering a `URLProtocol` against the shared session for the whole process
/// — a global mutation that has to be undone in `tearDown` and that no two tests
/// can hold at once.
///
/// Binding this per task instead means an override is scoped to the test that
/// makes it. Note that `Task.detached` does not inherit task-locals; anything
/// dispatching a request from a detached task needs the session passed to it.
enum NetworkEnvironment {
    @TaskLocal static var session: URLSession = .shared
}

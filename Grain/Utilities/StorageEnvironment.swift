import Foundation

/// The persistent stores the app reads and writes, overridable per task.
///
/// The unit-test bundle is hosted by the app, so it inherits the Keychain access
/// group and defaults suite belonging to the copy of Grain installed on that
/// simulator. A test that wrote straight through signed the developer out, or
/// left the app pointed at a synthetic DID.
///
/// These are task-locals rather than plain mutable globals so an override is
/// scoped to the task tree that makes it. A test binds its own namespace for the
/// duration of its body and nothing leaks to whatever else is running, which is
/// what makes it safe for tests to touch storage concurrently.
///
/// Each is stored as a *name* rather than a live store: `UserDefaults` is
/// explicitly not `Sendable` and so cannot cross a task-local boundary, and
/// `Keychain` is a value wrapper over query attributes that costs nothing to
/// rebuild. Both lookups are cheap and neither does I/O.
enum StorageEnvironment {
    /// Keychain service for OAuth credentials. See `TokenStorage`.
    @TaskLocal static var credentialService = "social.grain.oauth"

    /// Keychain service for DPoP signing keys. See `DPoP`.
    @TaskLocal static var dpopService = "social.grain.dpop"

    /// `UserDefaults` suite for non-sensitive local state — cached feeds, read
    /// state, recent searches. `nil` means the standard suite.
    @TaskLocal static var defaultsSuiteName: String?

    /// Non-sensitive local state, in whichever suite is currently bound.
    static var defaults: UserDefaults {
        guard let name = defaultsSuiteName, let suite = UserDefaults(suiteName: name) else {
            return .standard
        }
        return suite
    }

    /// Binds all three to a namespace unique to `name` for the duration of
    /// `body`, then discards the defaults suite so runs don't accumulate on disk.
    static func withNamespace<T>(_ name: String, perform body: () throws -> T) rethrows -> T {
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        return try $credentialService.withValue("\(name).oauth") {
            try $dpopService.withValue("\(name).dpop") {
                try $defaultsSuiteName.withValue(name) {
                    try body()
                }
            }
        }
    }

    /// Async counterpart of `withNamespace(_:perform:)`.
    ///
    /// Takes the caller's isolation so `body` isn't sent across an actor
    /// boundary — a `@MainActor` test can pass a closure that touches
    /// `@MainActor` state without it having to be `Sendable`.
    static func withNamespace<T>(
        _ name: String,
        isolation: isolated (any Actor)? = #isolation,
        perform body: () async throws -> T
    ) async rethrows -> T {
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        return try await $credentialService.withValue("\(name).oauth", operation: {
            try await $dpopService.withValue("\(name).dpop", operation: {
                try await $defaultsSuiteName.withValue(name, operation: {
                    try await body()
                }, isolation: isolation)
            }, isolation: isolation)
        }, isolation: isolation)
    }
}

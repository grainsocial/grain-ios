import Foundation
import os

private let logger = Logger(subsystem: "social.grain.grain", category: "NetworkRetry")

/// Retries network calls that dropped for reasons a second attempt can fix.
///
/// Only wrap operations that are safe to repeat. Blob uploads qualify — blobs
/// are content-addressed, so re-uploading the same bytes yields the same ref —
/// as do record writes with a client-assigned rkey. Wrapping a server-assigned
/// `createRecord` would be exactly the bug this file exists to prevent: the
/// first call succeeds, the response is lost, and the retry posts a duplicate.
enum NetworkRetry {
    /// Errors worth another attempt: the connection dropped or timed out, or
    /// the server asked us to back off. A 4xx, a decode failure, or an auth
    /// error will fail identically no matter how many times we try.
    static func isTransient(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .resourceUnavailable, .secureConnectionFailed,
                 .internationalRoamingOff, .callIsActive, .dataNotAllowed:
                return true
            default:
                return false
            }
        }
        if let xrpcError = error as? XRPCError, case let .httpError(statusCode, _) = xrpcError {
            return statusCode == 408 || statusCode == 425 || statusCode == 429 || (500 ... 599).contains(statusCode)
        }
        return false
    }

    /// Run `operation`, retrying transient failures with exponential backoff.
    ///
    /// Delays run 0.5s, 1s, 2s… with ±25% jitter, so twenty photo uploads that
    /// all hit the same dead cell don't come back in lockstep.
    @discardableResult
    static func run<T>(
        attempts: Int = 4,
        isolation _: isolated (any Actor)? = #isolation,
        onRetry: ((_ attempt: Int, _ error: Error) -> Void)? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch {
                guard attempt < attempts, isTransient(error) else { throw error }
                try Task.checkCancellation()
                let backoff = pow(2.0, Double(attempt - 1)) * 0.5
                let delay = backoff * Double.random(in: 0.75 ... 1.25)
                logger.info("Attempt \(attempt) failed (\(error.localizedDescription)); retrying in \(delay, format: .fixed(precision: 2))s")
                onRetry?(attempt, error)
                try await Task.sleep(for: .seconds(delay))
                attempt += 1
            }
        }
    }
}

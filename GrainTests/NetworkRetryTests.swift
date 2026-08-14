@testable import Grain
import XCTest

final class NetworkRetryTests: XCTestCase {
    // MARK: - Classification

    func testDroppedConnectionsAreTransient() {
        for code in [URLError.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed] {
            XCTAssertTrue(NetworkRetry.isTransient(URLError(code)), "\(code) should be retried")
        }
    }

    func testServerAndRateLimitStatusesAreTransient() {
        for status in [408, 425, 429, 500, 502, 503, 504] {
            XCTAssertTrue(
                NetworkRetry.isTransient(XRPCError.httpError(statusCode: status, body: nil)),
                "HTTP \(status) should be retried"
            )
        }
    }

    /// The important half: retrying these would either fail identically or, if
    /// the call weren't idempotent, duplicate work.
    func testClientErrorsAndCancellationAreNotTransient() {
        for status in [400, 401, 403, 404, 409, 413] {
            XCTAssertFalse(
                NetworkRetry.isTransient(XRPCError.httpError(statusCode: status, body: nil)),
                "HTTP \(status) should not be retried"
            )
        }
        XCTAssertFalse(NetworkRetry.isTransient(CancellationError()))
        XCTAssertFalse(NetworkRetry.isTransient(XRPCError.unauthorized))
        XCTAssertFalse(NetworkRetry.isTransient(URLError(.badURL)))
    }

    // MARK: - Behaviour

    func testRetriesUntilTheOperationSucceeds() async throws {
        var attempts = 0
        let result = try await NetworkRetry.run(attempts: 4) { () -> String in
            attempts += 1
            if attempts < 3 {
                throw URLError(.networkConnectionLost)
            }
            return "posted"
        }
        XCTAssertEqual(result, "posted")
        XCTAssertEqual(attempts, 3)
    }

    func testGivesUpAfterTheAttemptBudgetAndRethrows() async {
        var attempts = 0
        do {
            _ = try await NetworkRetry.run(attempts: 3) { () -> String in
                attempts += 1
                throw URLError(.timedOut)
            }
            XCTFail("expected the final failure to propagate")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(attempts, 3)
    }

    func testDoesNotRetryNonTransientFailures() async {
        var attempts = 0
        do {
            _ = try await NetworkRetry.run(attempts: 4) { () -> String in
                attempts += 1
                throw XRPCError.httpError(statusCode: 400, body: nil)
            }
            XCTFail("expected the failure to propagate")
        } catch {
            // expected
        }
        XCTAssertEqual(attempts, 1, "a 400 must not be repeated")
    }

    func testReportsEachRetryToTheCaller() async throws {
        var retries: [Int] = []
        var attempts = 0
        _ = try await NetworkRetry.run(attempts: 4, onRetry: { attempt, _ in retries.append(attempt) }) { () -> Int in
            attempts += 1
            if attempts < 3 {
                throw URLError(.timedOut)
            }
            return attempts
        }
        XCTAssertEqual(retries, [1, 2])
    }
}

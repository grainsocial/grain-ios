@testable import Grain
import XCTest

@MainActor
final class NotificationsViewModelTests: GrainTestCase {
    private var client: XRPCClient!
    private var vm: NotificationsViewModel!

    override func setUp() {
        super.setUp()
        client = XRPCClient(baseURL: URL(string: "https://test.local")!, session: MockURLProtocol.mockSession())
        vm = NotificationsViewModel(client: client)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - loadInitial

    func testLoadInitialPopulatesNotifications() async {
        MockURLProtocol.respondByPath([
            "listNotifications": """
            {
                "notifications": [
                    {
                        "uri": "at://did:plc:a/notif/1",
                        "reason": "follow",
                        "createdAt": "2024-06-15T12:00:00Z",
                        "indexedAt": "2024-06-15T12:00:00Z",
                        "isRead": false,
                        "author": {"cid": "c1", "did": "did:plc:a", "handle": "alice.test"}
                    }
                ],
                "cursor": "next"
            }
            """,
            "getUnreadCount": #"{"count": 3}"#,
        ])

        await vm.loadInitial()
        XCTAssertEqual(vm.notifications.count, 1)
        XCTAssertEqual(vm.unseenCount, 3)
        XCTAssertFalse(vm.isLoading)
    }

    /// Without a count, the page's unread ones are the count.
    func testLoadInitialCountsThePageWhenTheCountFails() async {
        MockURLProtocol.respondWithJSON("""
        {
            "notifications": [
                {
                    "uri": "at://did:plc:a/notif/1",
                    "reason": "follow",
                    "createdAt": "2024-06-15T12:00:00Z",
                    "indexedAt": "2024-06-15T12:00:00Z",
                    "isRead": false,
                    "author": {"cid": "c1", "did": "did:plc:a", "handle": "alice.test"}
                },
                {
                    "uri": "at://did:plc:a/notif/2",
                    "reason": "follow",
                    "createdAt": "2024-06-14T12:00:00Z",
                    "indexedAt": "2024-06-14T12:00:00Z",
                    "isRead": true,
                    "author": {"cid": "c1", "did": "did:plc:a", "handle": "alice.test"}
                }
            ]
        }
        """)

        await vm.loadInitial()
        XCTAssertEqual(vm.notifications.count, 2)
        XCTAssertEqual(vm.unseenCount, 1)
    }

    func testFetchUnseenCountAsksForTheUnreadCount() async {
        let seen = PathLog()
        MockURLProtocol.handler = { request in
            seen.append(request.url?.path ?? "")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"count": 4}"#.utf8), response)
        }

        await vm.fetchUnseenCount()
        XCTAssertEqual(seen.paths, ["/xrpc/social.grain.notification.getUnreadCount"])
        XCTAssertEqual(vm.unseenCount, 4)
    }

    func testMarkAsSeenUpdatesSeenAt() async {
        vm.unseenCount = 2
        let seen = PathLog()
        MockURLProtocol.handler = { request in
            seen.append(request.url?.path ?? "")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        await vm.markAsSeen()
        XCTAssertEqual(seen.paths, ["/xrpc/social.grain.notification.updateSeen"])
    }

    func testLoadInitialGuardsAgainstConcurrent() async {
        // If already loading, loadInitial should bail
        vm.isLoading = true
        MockURLProtocol.respondWithJSON("""
        {"notifications": [], "cursor": null}
        """)
        await vm.loadInitial()
        // Should still be "loading" since we skipped
        XCTAssertTrue(vm.isLoading)
        XCTAssertTrue(vm.notifications.isEmpty)
    }

    // MARK: - markAsSeen

    func testMarkAsSeenOptimisticallyZerosCount() async {
        vm.unseenCount = 5
        MockURLProtocol.respondWithJSON("{}")

        await vm.markAsSeen()
        XCTAssertEqual(vm.unseenCount, 0)
    }

    func testMarkAsSeenSkipsWhenAlreadyZero() async {
        vm.unseenCount = 0
        var requestMade = false
        MockURLProtocol.handler = { _ in
            requestMade = true
            return (Data("{}".utf8), HTTPURLResponse(url: URL(string: "https://test.local")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await vm.markAsSeen()
        XCTAssertFalse(requestMade)
    }

    func testMarkAsSeenRollsBackOnFailure() async {
        vm.unseenCount = 7
        MockURLProtocol.respondWithError(statusCode: 500)

        await vm.markAsSeen()
        XCTAssertEqual(vm.unseenCount, 7)
    }

    // MARK: - Pagination

    func testLoadMoreAppendsResults() async {
        // Set up initial state
        MockURLProtocol.respondWithJSON("""
        {
            "notifications": [
                {
                    "uri": "at://did:plc:a/notif/1",
                    "reason": "follow",
                    "createdAt": "2024-06-15T12:00:00Z",
                    "author": {"cid": "c1", "did": "did:plc:a", "handle": "alice.test"}
                }
            ],
            "cursor": "page2"
        }
        """)
        await vm.loadInitial()
        XCTAssertEqual(vm.notifications.count, 1)

        // Load more
        MockURLProtocol.respondWithJSON("""
        {
            "notifications": [
                {
                    "uri": "at://did:plc:b/notif/2",
                    "reason": "gallery-favorite",
                    "createdAt": "2024-06-15T13:00:00Z",
                    "author": {"cid": "c2", "did": "did:plc:b", "handle": "bob.test"}
                }
            ],
            "cursor": null
        }
        """)
        await vm.loadMore()
        XCTAssertEqual(vm.notifications.count, 2)
    }
}

/// The paths the mock was asked for, from outside the main actor.
private final class PathLog: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []

    func append(_ path: String) {
        lock.withLock { all.append(path) }
    }

    var paths: [String] {
        lock.withLock { all }
    }
}

@testable import Grain
import XCTest

@MainActor
final class NotificationsViewModelTests: XCTestCase {
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
            "cursor": "next",
            "unseenCount": 3
        }
        """)

        await vm.loadInitial()
        XCTAssertEqual(vm.notifications.count, 1)
        XCTAssertEqual(vm.unseenCount, 3)
        XCTAssertFalse(vm.isLoading)
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
            "cursor": "page2",
            "unseenCount": 0
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

@testable import Grain
import SwiftUI
import XCTest

/// The search tab once something has actually been searched for. Everything
/// below the field — the gallery cards, the profile rows, the empty state per
/// tab — only appears when the view model has a query in it, so the results
/// half of the screen is unreachable from a plain render.
@MainActor
final class SearchResultsRenderTests: GrainTestCase {
    private var account: TestAccount!

    /// Async overrides: the synchronous `setUp`/`tearDown` are nonisolated, so
    /// touching main-actor state from them warns.
    override func setUp() async throws {
        try await super.setUp()
        account = TestAccount()
        MockURLProtocol.respondByPath(Fixtures.routes)
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        account.restore()
        try await super.tearDown()
    }

    private let settle: TimeInterval = 0.35

    private func gallery(_ index: Int, creator: String) -> GrainGallery {
        GrainGallery(
            uri: "at://\(creator)/social.grain.gallery/\(index)",
            cid: "bafyg\(index)",
            title: "Result \(index)",
            description: "A found gallery with a #hashtag in its description.",
            locationDisplay: "Lisboa, Portugal",
            creator: GrainProfile(
                cid: "c\(index)",
                did: creator,
                handle: "\(creator).test",
                displayName: "Someone",
                avatar: "https://test.local/a.jpg"
            ),
            items: [GrainPhoto(
                uri: "at://\(creator)/social.grain.photo/\(index)",
                cid: "bafyp\(index)",
                thumb: "https://test.local/thumb.jpg",
                fullsize: "https://test.local/full.jpg",
                alt: "A found photo",
                aspectRatio: AspectRatio(width: 3, height: 2)
            )],
            favCount: 12,
            commentCount: 2,
            createdAt: "2025-01-02T00:00:00Z",
            indexedAt: "2025-01-02T00:00:00Z"
        )
    }

    private func searched(
        _ query: String,
        tab: SearchViewModel.SearchTab,
        galleries: [GrainGallery] = [],
        profiles: [ProfileSearchResult] = [],
        env: TestEnvironment
    ) -> SearchViewModel {
        let viewModel = SearchViewModel(client: env.client)
        viewModel.searchText = query
        viewModel.selectedTab = tab
        viewModel.galleryResults = galleries
        viewModel.profileResults = profiles
        return viewModel
    }

    private func render(_ viewModel: SearchViewModel, env: TestEnvironment) {
        ViewRender.render(
            SearchView(client: env.client, viewModel: viewModel).withTestEnvironment(env),
            settle: settle
        )
    }

    // MARK: - Gallery results

    /// A page of found galleries — each is a full card, with the same actions
    /// the feed's cards have.
    func testRendersGalleryResults() {
        let env = TestEnvironment()
        let results = (1 ... 3).map { gallery($0, creator: "did:plc:someone") }

        render(searched("film", tab: .galleries, galleries: results, env: env), env: env)
    }

    /// Your own gallery in the results gets a delete action where someone
    /// else's gets report.
    func testRendersYourOwnGalleryInTheResults() {
        let env = TestEnvironment()
        let results = [gallery(1, creator: "did:plc:test"), gallery(2, creator: "did:plc:someone")]

        render(searched("film", tab: .galleries, galleries: results, env: env), env: env)
    }

    /// A query that matched nothing is a different state from one that hasn't
    /// been run yet.
    func testRendersTheGalleriesTabWithNoMatches() {
        let env = TestEnvironment()

        render(searched("nothing matches this", tab: .galleries, env: env), env: env)
    }

    /// Mid-search the tab shows a spinner over whatever was there before.
    func testRendersTheGalleriesTabWhileSearching() {
        let env = TestEnvironment()
        let viewModel = searched("film", tab: .galleries, galleries: [gallery(1, creator: "did:plc:someone")], env: env)
        viewModel.isSearching = true

        render(viewModel, env: env)
    }

    // MARK: - Profile results

    func testRendersProfileResults() {
        let env = TestEnvironment()
        let people = [
            ProfileSearchResult(
                did: "did:plc:alpha", handle: "alpha.test", displayName: "Alpha",
                description: "A bio long enough to wrap onto a second line in the row.",
                avatar: "https://test.local/a.jpg"
            ),
            ProfileSearchResult(did: "did:plc:beta", handle: "beta.test"),
        ]

        render(searched("al", tab: .profiles, profiles: people, env: env), env: env)
    }

    func testRendersTheProfilesTabWithNoMatches() {
        let env = TestEnvironment()

        render(searched("nobody", tab: .profiles, env: env), env: env)
    }

    /// A profile with a live story gets a ring in the results row.
    func testRendersAProfileResultWithAStory() {
        let env = TestEnvironment()
        env.storyStatus.update(from: [
            GrainStoryAuthor(
                profile: GrainProfile(cid: "c", did: "did:plc:alpha", handle: "alpha.test"),
                storyCount: 2,
                latestAt: Fixtures.freshTimestamp
            ),
        ])
        let people = [ProfileSearchResult(did: "did:plc:alpha", handle: "alpha.test", displayName: "Alpha")]

        render(searched("al", tab: .profiles, profiles: people, env: env), env: env)
    }

    // MARK: - Signed out

    /// Signed out the results still render, without the actions that need an
    /// account behind them.
    func testRendersResultsWhileSignedOut() {
        let env = TestEnvironment(authenticated: false)
        let results = [gallery(1, creator: "did:plc:someone")]

        render(searched("film", tab: .galleries, galleries: results, env: env), env: env)
    }

    // MARK: - Recent searches

    /// With history and no query the tab shows the recents list instead.
    func testRendersRecentSearchesWithBothKinds() {
        let did = AccountScopedStorage.activeAccountID
        let recents = RecentSearchStorage(did: did)
        recents.addTextSearch("portra")
        recents.addTextSearch("film")
        recents.addProfile(did: "did:plc:alpha", displayName: "Alpha", handle: "alpha.test", avatar: nil)
        defer { recents.clearAll() }

        let env = TestEnvironment()
        render(searched("", tab: .galleries, env: env), env: env)
    }

    /// A fresh account has no history at all, which is the placeholder state.
    func testRendersTheEmptySearchPlaceholder() {
        let did = AccountScopedStorage.activeAccountID
        RecentSearchStorage(did: did).clearAll()

        let env = TestEnvironment()
        render(searched("", tab: .profiles, env: env), env: env)
    }
}

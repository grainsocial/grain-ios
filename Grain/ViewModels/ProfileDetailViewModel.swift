import Foundation
import UIKit

@Observable
@MainActor
final class ProfileDetailViewModel {
    var profile: GrainProfileDetailed?
    var galleries: [GrainGallery] = []
    var stories: [GrainStory] = []
    var archivedStories: [GrainStory] = []
    var favoriteGalleries: [GrainGallery] = []
    var knownFollowers: [FollowerItem] = []
    var isLoading = false
    var error: Error?
    var showReauthAlert = false

    private var galleryCursor: String?
    private var hasMoreGalleries = true
    private var archiveCursor: String?
    private var hasMoreArchive = true
    private var archiveLoaded = false
    private var favoritesCursor: String?
    private var hasMoreFavorites = true
    private var favoritesLoaded = false
    private let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
    }

    func load(did: String, viewer: String? = nil, auth: AuthContext? = nil) async {
        isLoading = true
        error = nil

        do {
            async let profileFetch = client.getActorProfile(actor: did, viewer: viewer, auth: auth)
            async let feedFetch = client.getFeed(feed: "actor", actor: did, auth: auth)
            async let storiesFetch = client.getStories(actor: did, auth: auth)
            async let knownFollowersFetch: [FollowerItem] = {
                guard let viewer, viewer != did else { return [] }
                let response = try? await client.getKnownFollowers(actor: did, viewer: viewer, auth: auth)
                return response?.items ?? []
            }()
            let profileResult = try await profileFetch
            let feedResult = try await feedFetch
            let storiesResult = try await storiesFetch

            profile = profileResult
            galleries = feedResult.items ?? []
            galleryCursor = feedResult.cursor
            hasMoreGalleries = feedResult.cursor != nil
            stories = storiesResult.stories
            knownFollowers = await knownFollowersFetch
            favoritesLoaded = false
            archiveLoaded = false
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func loadMoreGalleries(did: String, auth: AuthContext? = nil) async {
        guard !isLoading, hasMoreGalleries, let cursor = galleryCursor else { return }
        isLoading = true

        do {
            let response = try await client.getFeed(feed: "actor", cursor: cursor, actor: did, auth: auth)
            galleries.append(contentsOf: response.items ?? [])
            galleryCursor = response.cursor
            hasMoreGalleries = response.cursor != nil
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func loadStoryArchive(did: String, auth: AuthContext? = nil) async {
        guard !archiveLoaded else { return }
        archiveLoaded = true
        do {
            let response = try await client.getStoryArchive(actor: did, auth: auth)
            archivedStories = response.stories
            archiveCursor = response.cursor
            hasMoreArchive = response.cursor != nil
        } catch {}
    }

    func loadMoreArchive(did: String, auth: AuthContext? = nil) async {
        guard !isLoading, hasMoreArchive, let cursor = archiveCursor else { return }
        isLoading = true
        do {
            let response = try await client.getStoryArchive(actor: did, cursor: cursor, auth: auth)
            archivedStories.append(contentsOf: response.stories)
            archiveCursor = response.cursor
            hasMoreArchive = response.cursor != nil
        } catch {}
        isLoading = false
    }

    func loadFavorites(did: String, auth: AuthContext? = nil) async {
        guard !favoritesLoaded else { return }
        favoritesLoaded = true
        do {
            let response = try await client.getActorFavorites(actor: did, auth: auth)
            favoriteGalleries = response.items ?? []
            favoritesCursor = response.cursor
            hasMoreFavorites = response.cursor != nil
        } catch {}
    }

    func loadMoreFavorites(did: String, auth: AuthContext? = nil) async {
        guard !isLoading, hasMoreFavorites, let cursor = favoritesCursor else { return }
        isLoading = true
        do {
            let response = try await client.getActorFavorites(actor: did, cursor: cursor, auth: auth)
            favoriteGalleries.append(contentsOf: response.items ?? [])
            favoritesCursor = response.cursor
            hasMoreFavorites = response.cursor != nil
        } catch {}
        isLoading = false
    }

    /// Whether the profile content should be hidden due to a block
    var isBlockHidden: Bool {
        profile?.viewer?.blocking != nil || profile?.viewer?.blockedBy == true
    }

    func toggleBlock(auth: AuthContext?) async {
        guard let profile, let auth else { return }
        let prevViewer = profile.viewer
        let did = profile.did

        if let blockUri = profile.viewer?.blocking {
            // Optimistic unblock
            self.profile?.viewer?.blocking = nil
            do {
                try await client.unblockActor(blockUri: blockUri, auth: auth)
            } catch {
                self.profile?.viewer = prevViewer
            }
        } else {
            // Optimistic block
            self.profile?.viewer?.blocking = "pending"
            do {
                let response = try await client.blockActor(did: did, auth: auth)
                self.profile?.viewer?.blocking = response.uri
            } catch {
                self.profile?.viewer = prevViewer
                showReauthAlert = true
            }
        }
    }

    func toggleMute(auth: AuthContext?) async {
        guard let profile, let auth else { return }
        let prevViewer = profile.viewer
        let did = profile.did

        if profile.viewer?.muted == true {
            // Optimistic unmute
            self.profile?.viewer?.muted = false
            do {
                try await client.unmuteActor(did: did, auth: auth)
            } catch {
                self.profile?.viewer = prevViewer
            }
        } else {
            // Optimistic mute
            self.profile?.viewer?.muted = true
            do {
                try await client.muteActor(did: did, auth: auth)
            } catch {
                self.profile?.viewer = prevViewer
            }
        }
    }

    func toggleFollow(auth: AuthContext?) async {
        guard profile != nil, let auth else { return }

        // Capture all values before any mutation
        let followUri = profile?.viewer?.following
        let prevViewer = profile?.viewer
        let prevCount = profile?.followersCount
        let did = profile!.did

        if let followUri {
            // Optimistic unfollow
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            profile?.viewer?.following = nil
            profile?.followersCount = max((prevCount ?? 1) - 1, 0)

            let rkey = followUri.split(separator: "/").last.map(String.init) ?? ""
            do {
                try await client.deleteRecord(collection: "social.grain.graph.follow", rkey: rkey, auth: auth)
            } catch {
                profile?.viewer = prevViewer
                profile?.followersCount = prevCount
            }
        } else {
            // Optimistic follow — preserve existing block/mute state
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            profile?.viewer?.following = "pending"
            profile?.followersCount = (prevCount ?? 0) + 1

            let record = AnyCodable([
                "subject": did,
                "createdAt": DateFormatting.nowISO(),
            ])
            let repo = TokenStorage.userDID ?? ""
            do {
                let response = try await client.createRecord(
                    collection: "social.grain.graph.follow",
                    repo: repo,
                    record: record,
                    auth: auth
                )
                profile?.viewer?.following = response.uri
            } catch {
                profile?.viewer = prevViewer
                profile?.followersCount = prevCount
            }
        }
    }
}

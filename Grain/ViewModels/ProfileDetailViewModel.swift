import Foundation

@Observable
@MainActor
final class ProfileDetailViewModel {
    var profile: GrainProfileDetailed?
    var galleries: [GrainGallery] = []
    var stories: [GrainStory] = []
    var isLoading = false
    var error: Error?

    private var galleryCursor: String?
    private var hasMoreGalleries = true
    private let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
    }

    func load(did: String, viewer: String? = nil, auth: AuthContext? = nil) async {
        isLoading = true
        error = nil

        do {
            let p = try await client.getActorProfile(actor: did, viewer: viewer, auth: auth)
            let f = try await client.getFeed(feed: "actor", actor: did, auth: auth)
            let s = try await client.getStories(actor: did, auth: auth)
            profile = p
            galleries = f.items ?? []
            galleryCursor = f.cursor
            hasMoreGalleries = f.cursor != nil
            stories = s.stories
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

    func toggleFollow(auth: AuthContext?) async {
        guard profile != nil, let auth else { return }

        // Capture all values before any mutation
        let followUri = profile?.viewer?.following
        let prevViewer = profile?.viewer
        let prevCount = profile?.followersCount
        let did = profile!.did

        if let followUri {
            // Optimistic unfollow
            self.profile?.viewer?.following = nil
            self.profile?.followersCount = max((prevCount ?? 1) - 1, 0)

            let rkey = followUri.split(separator: "/").last.map(String.init) ?? ""
            do {
                try await client.deleteRecord(collection: "social.grain.graph.follow", rkey: rkey, auth: auth)
            } catch {
                self.profile?.viewer = prevViewer
                self.profile?.followersCount = prevCount
            }
        } else {
            // Optimistic follow
            self.profile?.viewer = ActorViewerState(following: "pending")
            self.profile?.followersCount = (prevCount ?? 0) + 1

            let record = AnyCodable([
                "subject": did,
                "createdAt": DateFormatting.nowISO()
            ])
            let repo = TokenStorage.userDID ?? ""
            do {
                let response = try await client.createRecord(collection: "social.grain.graph.follow", repo: repo, record: record, auth: auth)
                self.profile?.viewer?.following = response.uri
            } catch {
                self.profile?.viewer = prevViewer
                self.profile?.followersCount = prevCount
            }
        }
    }
}

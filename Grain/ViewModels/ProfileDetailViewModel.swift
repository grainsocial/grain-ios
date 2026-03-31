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

    func load(did: String, auth: AuthContext? = nil) async {
        isLoading = true
        error = nil

        do {
            async let profileResponse = client.getActorProfile(actor: did, auth: auth)
            async let feedResponse = client.getFeed(feed: "actor", actor: did, auth: auth)
            async let storiesResponse = client.getStories(actor: did, auth: auth)

            let (p, f, s) = try await (profileResponse, feedResponse, storiesResponse)
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
        guard let profile, let auth else { return }
        if let followUri = profile.viewer?.following {
            let rkey = followUri.split(separator: "/").last.map(String.init) ?? ""
            try? await client.deleteRecord(collection: "social.grain.graph.follow", rkey: rkey, auth: auth)
            self.profile?.viewer?.following = nil
            self.profile?.followersCount = (self.profile?.followersCount ?? 1) - 1
        } else {
            let record = AnyCodable([
                "subject": profile.did,
                "createdAt": ISO8601DateFormatter().string(from: Date())
            ])
            let repo = TokenStorage.userDID ?? ""
            let response = try? await client.createRecord(collection: "social.grain.graph.follow", repo: repo, record: record, auth: auth)
            self.profile?.viewer?.following = response?.uri
            self.profile?.followersCount = (self.profile?.followersCount ?? 0) + 1
        }
    }
}

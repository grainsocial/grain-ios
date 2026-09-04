import SwiftUI

/// Somewhere in the app you can push to.
///
/// Screens used to keep one `@State` optional per destination and one
/// `navigationDestination(item:)` per optional — fifteen and seventeen of them
/// respectively on the feed. That represents far more states than are legal
/// (nothing stopped two being non-nil at once) and it puts every destination's
/// body inside a closure that only runs once somebody taps, which is most of
/// what the test suite can't reach.
///
/// A route is a value instead. The stack holds an array of them, so where the
/// user is is something you can read, assert on and restore.
///
/// Cases carry identifiers only — never a model object, a closure or a binding.
/// A route outlives the data it points at: it survives relaunch, and the record
/// it names may have changed by the time it's popped back to.
enum Route: Hashable, Codable {
    case gallery(uri: String)
    case profile(did: String)
    case hashtag(String)
    /// `name` is the H3 cell's display name, carried because it titles the
    /// screen and isn't derivable from the index without a lookup.
    case location(h3Index: String, name: String)
    case galleryFavorites(uri: String)
}

/// The view a `Route` names.
///
/// Registered once per `NavigationStack` with `navigationDestination(for:)`,
/// which is the arrangement Apple's migration guide prescribes. Being a plain
/// `Route -> View` function, it can be exercised directly rather than through a
/// tap.
struct RouteDestination: View {
    let route: Route
    let client: XRPCClient

    /// Set by the gallery detail screen when it deletes what it was showing, so
    /// the list underneath can drop the row. It lives on the builder rather than
    /// in the `Route` because a route has to stay a plain value — carrying a
    /// binding would make it uncodable and tie it to one particular caller.
    var deletedGalleryUri: Binding<String?> = .constant(nil)

    var body: some View {
        switch route {
        case let .gallery(uri):
            GalleryDetailView(client: client, galleryUri: uri, deletedGalleryUri: deletedGalleryUri)
        case let .profile(did):
            ProfileView(client: client, did: did)
        case let .hashtag(tag):
            HashtagFeedView(client: client, tag: tag)
        case let .location(h3Index, name):
            LocationFeedView(client: client, h3Index: h3Index, locationName: name)
        case let .galleryFavorites(uri):
            FollowListView(client: client, mode: .galleryFavorites(uri))
        }
    }
}

import SwiftUI

/// The navigation stack's path, as an object descendants can reach.
///
/// The destinations a gallery card can send you to are decided several views
/// below the `NavigationStack` that owns the path. Passing a binding down every
/// intermediate view is how the nine per-card callbacks ended up reimplemented
/// on eight screens; putting the path in the environment means a card's action
/// is one call from wherever it happens to be.
///
/// Deliberately only push and pop. Anything that decides *what* to do — deleting
/// a gallery, resolving credentials — belongs in a view model; this type only
/// knows where the user is.
@MainActor
@Observable
final class Router {
    var path: [Route] = []

    init(path: [Route] = []) {
        self.path = path
    }

    func push(_ route: Route) {
        path.append(route)
    }

    /// Replaces the stack, for a deep link arriving while the user is somewhere else.
    func replace(with routes: [Route]) {
        path = routes
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
    }
}

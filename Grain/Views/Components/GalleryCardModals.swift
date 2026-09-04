import SwiftUI

/// What a gallery card can put on screen over the list it sits in.
///
/// Every screen showing a card needs the same five: the story viewer, the
/// comment sheet, the report sheet, the delete confirmation and the alert when
/// a delete fails. Six screens each kept six `@State` properties and ~78 lines
/// of presenters to do it, identical apart from which collection to update
/// afterwards.
@MainActor
@Observable
final class GalleryCardModals {
    var commentUri: String?
    var report: GrainGallery?
    var storyAuthor: GrainStoryAuthor?
    var pendingDeleteUri: String?
    var isConfirmingDelete = false
    var deleteError: String?

    init() {}

    /// Ask before deleting `uri`. The confirmation is what actually deletes.
    func confirmDelete(_ uri: String) {
        pendingDeleteUri = uri
        isConfirmingDelete = true
    }
}

private struct GalleryCardModalsModifier: ViewModifier {
    @Environment(AuthManager.self) private var auth
    @Environment(Router.self) private var router
    let client: XRPCClient
    let modals: GalleryCardModals
    /// The gallery's own comment count lives in whichever collection the screen
    /// is showing, so updating it stays with the screen.
    let onCommentCountChanged: (String, Int) -> Void
    let onDeleted: (String) -> Void

    func body(content: Content) -> some View {
        @Bindable var modals = modals
        return content
            .fullScreenCover(item: $modals.storyAuthor) { author in
                StoryViewer(
                    authors: [author],
                    client: client,
                    onProfileTap: { did in
                        modals.storyAuthor = nil
                        router.push(.profile(did: did))
                    },
                    onDismiss: { modals.storyAuthor = nil }
                )
                .environment(auth)
            }
            .sheet(isPresented: Binding(
                get: { modals.commentUri != nil },
                set: {
                    if !$0 {
                        modals.commentUri = nil
                    }
                }
            )) {
                if let uri = modals.commentUri {
                    CommentSheetView(
                        client: client,
                        galleryUri: uri,
                        onDismiss: { modals.commentUri = nil },
                        onProfileTap: { did in
                            modals.commentUri = nil
                            router.push(.profile(did: did))
                        },
                        onHashtagTap: { tag in
                            modals.commentUri = nil
                            router.push(.hashtag(tag))
                        },
                        onStoryTap: { author in
                            modals.commentUri = nil
                            modals.storyAuthor = author
                        },
                        onCommentCountChanged: { onCommentCountChanged(uri, $0) }
                    )
                }
            }
            .sheet(item: $modals.report) { gallery in
                ReportView(client: client, subjectUri: gallery.uri, subjectCid: gallery.cid)
            }
            .alert("Delete gallery?", isPresented: $modals.isConfirmingDelete) {
                Button("Delete", role: .destructive) {
                    guard let uri = modals.pendingDeleteUri else { return }
                    modals.pendingDeleteUri = nil
                    Task {
                        switch await GalleryService.delete(galleryUri: uri, client: client, auth: auth) {
                        case .success:
                            onDeleted(uri)
                        case let .failure(error):
                            modals.deleteError = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) { modals.pendingDeleteUri = nil }
            } message: {
                Text("This will permanently delete this gallery and all its photos.")
            }
            .alert("Couldn't delete gallery", isPresented: Binding(
                get: { modals.deleteError != nil },
                set: {
                    if !$0 {
                        modals.deleteError = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) { modals.deleteError = nil }
            } message: {
                Text(modals.deleteError ?? "")
            }
    }
}

extension View {
    /// Attach the modals a gallery card can raise.
    func galleryCardModals(
        client: XRPCClient,
        modals: GalleryCardModals,
        onCommentCountChanged: @escaping (String, Int) -> Void,
        onDeleted: @escaping (String) -> Void
    ) -> some View {
        modifier(GalleryCardModalsModifier(
            client: client,
            modals: modals,
            onCommentCountChanged: onCommentCountChanged,
            onDeleted: onDeleted
        ))
    }
}

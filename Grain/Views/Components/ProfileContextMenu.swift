import SwiftUI

extension View {
    /// Long-press context menu for profile avatars/rows.
    /// Omit `onViewProfile` when already on the profile page.
    /// Pass `hasStory: true` and a non-nil `onViewStory` to include "View story".
    func profileContextMenu(
        handle: String?,
        hasStory: Bool,
        onViewProfile: (() -> Void)? = nil,
        onViewStory: (() -> Void)? = nil,
        onAddStory: (() -> Void)? = nil,
        onViewPhoto: (() -> Void)? = nil,
        showSharingActions: Bool = true
    ) -> some View {
        contextMenu {
            profileMenuItems(
                handle: handle,
                hasStory: hasStory,
                onViewProfile: onViewProfile,
                onViewStory: onViewStory,
                onAddStory: onAddStory,
                onViewPhoto: onViewPhoto,
                showSharingActions: showSharingActions
            )
        }
    }

    /// Variant with an explicit preview rendered directly in the system overlay —
    /// use when the default "lift" animation is clipped by the surrounding layout.
    func profileContextMenu(
        handle: String?,
        hasStory: Bool,
        onViewProfile: (() -> Void)? = nil,
        onViewStory: (() -> Void)? = nil,
        onAddStory: (() -> Void)? = nil,
        onViewPhoto: (() -> Void)? = nil,
        showSharingActions: Bool = true,
        @ViewBuilder preview: @escaping () -> some View
    ) -> some View {
        contextMenu {
            profileMenuItems(
                handle: handle,
                hasStory: hasStory,
                onViewProfile: onViewProfile,
                onViewStory: onViewStory,
                onAddStory: onAddStory,
                onViewPhoto: onViewPhoto,
                showSharingActions: showSharingActions
            )
        } preview: {
            preview()
        }
    }

    /// Conditionally apply a view modifier without duplicating the entire view tree.
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

@ViewBuilder
private func profileMenuItems(
    handle: String?,
    hasStory: Bool,
    onViewProfile: (() -> Void)?,
    onViewStory: (() -> Void)?,
    onAddStory: (() -> Void)?,
    onViewPhoto: (() -> Void)?,
    showSharingActions: Bool = true
) -> some View {
    if hasStory, let onViewStory {
        Button(action: onViewStory) {
            Label("View story", systemImage: "play.circle")
        }
    }
    if let onAddStory {
        Button(action: onAddStory) {
            Label("New story", systemImage: "plus.circle")
        }
    }
    if let onViewProfile {
        Button(action: onViewProfile) {
            Label("View profile", systemImage: "person.circle")
        }
    }
    if let onViewPhoto {
        Button(action: onViewPhoto) {
            Label("View profile photo", systemImage: "person.crop.circle.fill")
        }
    }
    if showSharingActions, let handle {
        Divider()
        ShareLink(item: URL(string: "https://grain.social/profile/\(handle)") ?? URL(string: "https://grain.social")!) {
            Label("Share profile", systemImage: "square.and.arrow.up")
        }
    }
}

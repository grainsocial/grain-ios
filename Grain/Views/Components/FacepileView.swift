import SwiftUI

/// Anything that can appear in a `FacepileView` — just a stable identity and an
/// avatar URL. Conformed by the various actor list item types.
protocol FacepileMember {
    var did: String { get }
    var avatar: String? { get }
}

extension GrainProfile: FacepileMember {}
extension FollowerItem: FacepileMember {}
extension FavoriteItem: FacepileMember {}

/// Overlapping row of avatars used to summarize a handful of accounts inline —
/// "followers you know", "favorited by", and friends. The ring is drawn in the
/// background color so avatars read as stacked cards.
struct FacepileView<Member: FacepileMember>: View {
    let people: [Member]
    /// Base avatar diameter at the default text size. Scales with Dynamic Type
    /// so the avatars keep their proportion to the caption beside them.
    var size: CGFloat = 24
    /// How far each avatar tucks under the one before it, at the base size.
    var overlap: CGFloat = 8
    var maxVisible: Int = 3

    @ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 1

    var body: some View {
        let avatarSize = size * scale
        HStack(spacing: -overlap * scale) {
            ForEach(Array(people.prefix(maxVisible).enumerated()), id: \.element.did) { index, person in
                AvatarView(url: person.avatar, size: avatarSize)
                    .background(Circle().fill(Color(.systemBackground)))
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .zIndex(Double(maxVisible - index))
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        FacepileView(people: PreviewData.gallery1.creator.asFacepilePreview(count: 3))
        FacepileView(people: PreviewData.gallery1.creator.asFacepilePreview(count: 2), size: 20)
        FacepileView(people: PreviewData.gallery1.creator.asFacepilePreview(count: 1), size: 18, overlap: 4)
    }
    .padding()
    .previewEnvironments()
}

private extension GrainProfile {
    /// Repeats this profile under distinct DIDs so previews can show a stack.
    func asFacepilePreview(count: Int) -> [GrainProfile] {
        (0 ..< count).map { index in
            GrainProfile(cid: cid, did: "\(did)-\(index)", handle: handle, displayName: displayName, avatar: avatar)
        }
    }
}

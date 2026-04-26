import UIKit

// MARK: - Shared preview content used across all #Preview blocks

enum PreviewData {
    // MARK: - Profiles

    static let profile = GrainProfileDetailed(
        cid: "cid1",
        did: "did:plc:prevuser1",
        handle: "yuki.grain.social",
        displayName: "Yuki Tanaka",
        description: "Analog photographer based in Tokyo 🇯🇵\nLeica M6 · Mamiya RB67 · Kodak Portra\n#35mm #film #analog #streetphoto",
        avatar: bundleImageURL("Penguin_in_Antarctica_jumping_out_of_the_water"),
        cameras: ["Leica M6", "Mamiya RB67"],
        followersCount: 2847,
        followsCount: 412,
        galleryCount: 63,
        viewer: ActorViewerState(following: nil, followedBy: "at://preview/follow/1")
    )

    static let profile1 = GrainProfile(
        cid: "c1",
        did: "did:plc:prevuser1",
        handle: "yuki.grain.social",
        displayName: "Yuki Tanaka",
        avatar: bundleImageURL("Penguin_in_Antarctica_jumping_out_of_the_water")
    )

    static let profile2 = GrainProfile(
        cid: "cid2", did: "did:plc:prevuser2",
        handle: "marcus.grain.social", displayName: "Marcus Webb",
        avatar: bundleImageURL("Union_Bank_Tower,_Portland_(2024)-L1006272")
    )

    static let profile3 = GrainProfile(
        cid: "cid3", did: "did:plc:prevuser3",
        handle: "sofia.grain.social", displayName: "Sofia Reyes",
        avatar: bundleImageURL("Portland_Japanese_Garden_maple")
    )

    static let profile4 = GrainProfile(
        cid: "cid4", did: "did:plc:prevuser4",
        handle: "kai.grain.social", displayName: "Kai Müller",
        avatar: bundleImageURL("Mount_Hood_reflected_in_Mirror_Lake,_Oregon")
    )

    static let profile5 = GrainProfile(
        cid: "cid5", did: "did:plc:prevuser5",
        handle: "leo.grain.social", displayName: "Leo Park",
        avatar: bundleImageURL("Mt_Herschel,_Antarctica,_Jan_2006")
    )

    static let profile6 = GrainProfile(
        cid: "cid6", did: "did:plc:prevuser6",
        handle: "rina.grain.social", displayName: "Rina Watanabe",
        avatar: nil
    )

    static let profile7 = GrainProfile(
        cid: "cid7", did: "did:plc:prevuser7",
        handle: "omar.grain.social", displayName: "Omar Hassan",
        avatar: nil
    )

    static let profile8 = GrainProfile(
        cid: "cid8", did: "did:plc:prevuser8",
        handle: "elena.grain.social", displayName: "Elena Voronova",
        avatar: bundleImageURL("Endeavour_after_STS-126_on_SCA_over_Mojave_from_above")
    )

    // MARK: - Date helpers

    private static func ago(_ seconds: TimeInterval) -> String {
        DateFormatting.nowISO(date: Date().addingTimeInterval(-seconds))
    }

    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 86400

    // MARK: - Bundle image URL helper

    static func bundleImageURL(_ name: String, ext: String = "jpg") -> String {
        Bundle.main.url(forResource: name, withExtension: ext)?.absoluteString ?? ""
    }

    // MARK: - Photos (file:// URLs → real images in preview via Nuke LazyImage)

    static let photos: [GrainPhoto] = [
        GrainPhoto(
            uri: "at://did:plc:prevuser1/social.grain.photo/p1",
            cid: "cid",
            thumb: bundleImageURL("Portland_Japanese_Garden_maple"),
            fullsize: bundleImageURL("Portland_Japanese_Garden_maple"),
            alt: "Japanese Garden, Portland",
            aspectRatio: AspectRatio(width: 4, height: 3)
        ),
        GrainPhoto(
            uri: "at://did:plc:prevuser1/social.grain.photo/p2",
            cid: "cid",
            thumb: bundleImageURL("Mount_Hood_reflected_in_Mirror_Lake,_Oregon"),
            fullsize: bundleImageURL("Mount_Hood_reflected_in_Mirror_Lake,_Oregon"),
            alt: "Mirror Lake, Oregon",
            aspectRatio: AspectRatio(width: 3, height: 2)
        ),
        GrainPhoto(
            uri: "at://did:plc:prevuser1/social.grain.photo/p3",
            cid: "cid",
            thumb: bundleImageURL("Mt_Herschel,_Antarctica,_Jan_2006"),
            fullsize: bundleImageURL("Mt_Herschel,_Antarctica,_Jan_2006"),
            alt: "Mt. Herschel, Antarctica",
            aspectRatio: AspectRatio(width: 4, height: 3)
        ),
        GrainPhoto(
            uri: "at://did:plc:prevuser1/social.grain.photo/p4",
            cid: "cid",
            thumb: bundleImageURL("Penguin_in_Antarctica_jumping_out_of_the_water"),
            fullsize: bundleImageURL("Penguin_in_Antarctica_jumping_out_of_the_water"),
            alt: "Penguin launching from ice shelf",
            aspectRatio: AspectRatio(width: 1, height: 1)
        ),
        GrainPhoto(
            uri: "at://did:plc:prevuser1/social.grain.photo/p5",
            cid: "cid",
            thumb: bundleImageURL("Union_Bank_Tower,_Portland_(2024)-L1006272"),
            fullsize: bundleImageURL("Union_Bank_Tower,_Portland_(2024)-L1006272"),
            alt: "Union Bank Tower, Portland",
            aspectRatio: AspectRatio(width: 2, height: 3)
        ),
        GrainPhoto(
            uri: "at://did:plc:prevuser1/social.grain.photo/p6",
            cid: "cid",
            thumb: bundleImageURL("ACE_EMD_F40PH_Fremont_-_San_Jose"),
            fullsize: bundleImageURL("ACE_EMD_F40PH_Fremont_-_San_Jose"),
            alt: "ACE train, Fremont–San Jose",
            aspectRatio: AspectRatio(width: 16, height: 9)
        ),
        GrainPhoto(
            uri: "at://did:plc:prevuser1/social.grain.photo/p7",
            cid: "cid",
            thumb: bundleImageURL("C-141_Starlifter_contrail"),
            fullsize: bundleImageURL("C-141_Starlifter_contrail"),
            alt: "C-141 Starlifter contrail",
            aspectRatio: AspectRatio(width: 16, height: 9)
        ),
        GrainPhoto(
            uri: "at://did:plc:prevuser1/social.grain.photo/p8",
            cid: "cid",
            thumb: bundleImageURL("Endeavour_after_STS-126_on_SCA_over_Mojave_from_above"),
            fullsize: bundleImageURL("Endeavour_after_STS-126_on_SCA_over_Mojave_from_above"),
            alt: "Space Shuttle Endeavour over Mojave",
            aspectRatio: AspectRatio(width: 4, height: 3)
        ),
    ]

    // MARK: - Galleries

    static let gallery1 = GrainGallery(
        uri: "at://did:plc:prevuser1/social.grain.gallery/r1",
        cid: "cid",
        title: "Golden Hour, Kyoto",
        description: "Shot on Leica M6 with Kodak Portra 400 during autumn in Kyoto. #analog #japan #35mm #film",
        cameras: ["Leica M6"],
        creator: profile1,
        items: photos,
        favCount: 184,
        commentCount: 12,
        indexedAt: "2025-01-10T18:30:00Z"
    )

    static let gallery2 = GrainGallery(
        uri: "at://did:plc:prevuser2/social.grain.gallery/r2",
        cid: "cid",
        title: "Lower East Side",
        description: "Sunday morning light on Orchard St. #nyc #street #leica",
        cameras: ["Leica Q3"],
        creator: profile2,
        items: Array(photos.prefix(2)),
        favCount: 97,
        commentCount: 5,
        indexedAt: "2025-01-08T12:00:00Z"
    )

    static let gallery3 = GrainGallery(
        uri: "at://did:plc:prevuser3/social.grain.gallery/r3",
        cid: "cid",
        title: "Oaxaca Market",
        description: "Colors, light, and life. Shot on Fuji Velvia 50. #mexico #analog #color",
        cameras: ["Nikon FM2"],
        creator: profile3,
        items: Array(photos.prefix(3)),
        favCount: 231,
        commentCount: 18,
        indexedAt: "2025-01-05T09:00:00Z"
    )

    static let galleries: [GrainGallery] = [gallery1, gallery2, gallery3]

    // MARK: - Comments

    static let comments: [GrainComment] = [
        GrainComment(
            uri: "at://did:plc:prevuser2/social.grain.comment/c1",
            cid: "cid",
            author: profile2,
            text: "The light in the third frame is unreal. What film stock did you use?",
            createdAt: "2025-01-10T19:00:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser3/social.grain.comment/c2",
            cid: "cid",
            author: profile3,
            text: "Portra always delivers in that golden hour window 🙌",
            replyTo: "at://did:plc:prevuser2/social.grain.comment/c1",
            createdAt: "2025-01-10T19:15:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser2/social.grain.comment/c3",
            cid: "cid",
            author: profile2,
            text: "Worth every penny shooting on film. Love this series.",
            createdAt: "2025-01-10T20:00:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser4/social.grain.comment/c4",
            cid: "cid",
            author: profile4,
            text: "Adding this to my inspiration board immediately",
            createdAt: "2025-01-10T20:30:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser5/social.grain.comment/c5",
            cid: "cid",
            author: profile5,
            text: "What time of day was this? The shadows are beautiful",
            createdAt: "2025-01-10T21:00:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser2/social.grain.comment/c6",
            cid: "cid",
            author: profile2,
            text: "Late afternoon, maybe 4pm — sun was raking across the maples",
            replyTo: "at://did:plc:prevuser5/social.grain.comment/c5",
            createdAt: "2025-01-10T21:10:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser6/social.grain.comment/c7",
            cid: "cid",
            author: profile6,
            text: "The composition on #2 is everything",
            createdAt: "2025-01-11T08:00:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser7/social.grain.comment/c8",
            cid: "cid",
            author: profile7,
            text: "Can we talk about how clean those highlights are?",
            createdAt: "2025-01-11T08:45:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser8/social.grain.comment/c9",
            cid: "cid",
            author: profile8,
            text: "Saved. This is the kind of work that makes me want to pick up a film camera again.",
            createdAt: "2025-01-11T09:30:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser3/social.grain.comment/c10",
            cid: "cid",
            author: profile3,
            text: "What lens? Looks like 50mm but the compression feels longer",
            createdAt: "2025-01-11T10:00:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser2/social.grain.comment/c11",
            cid: "cid",
            author: profile2,
            text: "85mm — you've got a good eye",
            replyTo: "at://did:plc:prevuser3/social.grain.comment/c10",
            createdAt: "2025-01-11T10:05:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser4/social.grain.comment/c12",
            cid: "cid",
            author: profile4,
            text: "I keep coming back to this one",
            createdAt: "2025-01-11T11:00:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser5/social.grain.comment/c13",
            cid: "cid",
            author: profile5,
            text: "@yuki.grain.social this is the gallery I was telling you about — the autumn series",
            createdAt: "2025-01-11T12:00:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser6/social.grain.comment/c14",
            cid: "cid",
            author: profile6,
            text: "Stunning. The fourth frame especially.",
            createdAt: "2025-01-11T13:00:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser7/social.grain.comment/c15",
            cid: "cid",
            author: profile7,
            text: "Adding Portland to the trip list now",
            createdAt: "2025-01-11T14:00:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser8/social.grain.comment/c16",
            cid: "cid",
            author: profile8,
            text: "The way you frame negative space is something else",
            createdAt: "2025-01-11T15:00:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser3/social.grain.comment/c17",
            cid: "cid",
            author: profile3,
            text: "Bookmarking for the color palette alone",
            createdAt: "2025-01-11T16:00:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser4/social.grain.comment/c18",
            cid: "cid",
            author: profile4,
            text: "This whole set deserves a print run",
            createdAt: "2025-01-11T17:00:00Z"
        ),
    ]

    // MARK: - Stories

    private static let yukiProfile = GrainProfile(
        cid: "c1",
        did: "did:plc:prevuser1",
        handle: "yuki.grain.social",
        displayName: "Yuki Tanaka",
        avatar: bundleImageURL("Penguin_in_Antarctica_jumping_out_of_the_water")
    )

    static let stories: [GrainStory] = [
        GrainStory(
            uri: "at://did:plc:prevuser1/social.grain.story/s1",
            cid: "cid",
            creator: yukiProfile,
            thumb: bundleImageURL("Portland_Japanese_Garden_maple"),
            fullsize: bundleImageURL("Portland_Japanese_Garden_maple"),
            aspectRatio: AspectRatio(width: 4, height: 3),
            location: H3Location(value: "8a2a1072b59ffff", name: "Kyoto, Japan"),
            address: nil,
            createdAt: "2025-01-10T18:00:00Z",
            labels: nil,
            crossPost: nil,
            viewer: StoryViewerState(fav: "at://did:plc:prevuser1/social.grain.fav/f1")
        ),
        GrainStory(
            uri: "at://did:plc:prevuser1/social.grain.story/s2",
            cid: "cid",
            creator: yukiProfile,
            thumb: bundleImageURL("Mount_Hood_reflected_in_Mirror_Lake,_Oregon"),
            fullsize: bundleImageURL("Mount_Hood_reflected_in_Mirror_Lake,_Oregon"),
            aspectRatio: AspectRatio(width: 3, height: 2),
            location: H3Location(value: "8a2a1072b51ffff", name: "Mirror Lake, Oregon"),
            address: nil,
            createdAt: "2025-01-10T16:00:00Z",
            labels: nil,
            crossPost: nil,
            viewer: nil
        ),
        GrainStory(
            uri: "at://did:plc:prevuser1/social.grain.story/s3",
            cid: "cid",
            creator: yukiProfile,
            thumb: bundleImageURL("Union_Bank_Tower,_Portland_(2024)-L1006272"),
            fullsize: bundleImageURL("Union_Bank_Tower,_Portland_(2024)-L1006272"),
            aspectRatio: AspectRatio(width: 2, height: 3),
            location: H3Location(value: "8a2a1072b52ffff", name: "Portland, OR"),
            address: nil,
            createdAt: "2025-01-10T14:00:00Z",
            labels: nil,
            crossPost: nil,
            viewer: nil
        ),
    ]

    static let storyComments: [GrainComment] = [
        GrainComment(
            uri: "at://did:plc:prevuser2/social.grain.comment/sc1",
            cid: "cid",
            author: profile2,
            text: "The sunlight through those maple leaves 😍",
            subject: AnyCodable(stories[0].uri),
            createdAt: "2025-01-10T18:30:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser3/social.grain.comment/sc2",
            cid: "cid",
            author: profile3,
            text: "Kyoto in fall hits different. Which temple is this near?",
            subject: AnyCodable(stories[0].uri),
            createdAt: "2025-01-10T18:42:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser1/social.grain.comment/sc3",
            cid: "cid",
            author: yukiProfile,
            text: "@sofia.grain.social it's Tofuku-ji — the whole valley is lit up right now",
            replyTo: "at://did:plc:prevuser3/social.grain.comment/sc2",
            createdAt: "2025-01-10T18:50:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser4/social.grain.comment/sc4",
            cid: "cid",
            author: profile4,
            text: "Portra 400 pushing 1 stop?",
            subject: AnyCodable(stories[0].uri),
            createdAt: "2025-01-10T19:05:00Z"
        ),
        GrainComment(
            uri: "at://did:plc:prevuser5/social.grain.comment/sc5",
            cid: "cid",
            author: profile5,
            text: "Adding this to my travel bucket list 🍁",
            subject: AnyCodable(stories[0].uri),
            createdAt: "2025-01-10T19:12:00Z"
        ),
    ]

    // MARK: - PhotoItems (UIImage-based, for editor/grid/strip previews)

    static var photoItems: [PhotoItem] {
        let stockImages: [(name: String, alt: String)] = [
            ("Portland_Japanese_Garden_maple", "Japanese Garden, Portland"),
            ("Mount_Hood_reflected_in_Mirror_Lake,_Oregon", "Mirror Lake, Oregon"),
            ("Mt_Herschel,_Antarctica,_Jan_2006", "Mt. Herschel, Antarctica"),
            ("Penguin_in_Antarctica_jumping_out_of_the_water", "Penguin launching from ice shelf"),
            ("Union_Bank_Tower,_Portland_(2024)-L1006272", "Union Bank Tower, Portland"),
            ("ACE_EMD_F40PH_Fremont_-_San_Jose", "ACE train, Fremont–San Jose"),
            ("C-141_Starlifter_contrail", "C-141 Starlifter contrail"),
            ("Endeavour_after_STS-126_on_SCA_over_Mojave_from_above", "Space Shuttle Endeavour over Mojave"),
        ]
        let fallbackColors: [([CGColor], String)] = [
            ([UIColor.systemBrown.cgColor, UIColor.systemOrange.cgColor], ""),
            ([UIColor.systemMint.cgColor, UIColor.systemTeal.cgColor], ""),
            ([UIColor.systemCyan.cgColor, UIColor.systemBlue.cgColor], ""),
            ([UIColor.systemGray.cgColor, UIColor.systemGray3.cgColor], ""),
            ([UIColor.systemPink.cgColor, UIColor.systemRed.cgColor], "Market stalls, morning light"),
            ([UIColor.systemGreen.cgColor, UIColor.systemMint.cgColor], ""),
            ([UIColor.systemOrange.cgColor, UIColor.systemYellow.cgColor], ""),
        ]
        var items: [PhotoItem] = stockImages.compactMap { entry in
            guard let path = Bundle.main.url(forResource: entry.name, withExtension: "jpg")?.path,
                  let fullImage = UIImage(contentsOfFile: path) else { return nil }
            let thumb = PhotoItem.makeThumbnail(from: fullImage)
            let carousel = PhotoItem.makeCarouselPreview(from: fullImage, width: 393)
            var item = PhotoItem(thumbnail: thumb, carouselPreview: carousel, source: .camera(fullImage, metadata: nil))
            item.alt = entry.alt
            return item
        }
        // Pad with gradient fallbacks if fewer than 15 items total
        for (colors, label) in fallbackColors {
            let thumb = gradientThumb(colors: colors)
            var item = PhotoItem(thumbnail: thumb, carouselPreview: thumb, source: .camera(thumb, metadata: nil))
            item.alt = label
            items.append(item)
        }
        return items
    }

    /// Same as `photoItems` but with mock EXIF on every even-indexed item,
    /// so previews that show the ExifChip can see both the with/without states.
    static var photoItemsWithExif: [PhotoItem] {
        let mockExif = ExifSummary(
            camera: "RICOH GR IIIx",
            lens: nil,
            exposure: nil,
            shutterSpeed: "1/250",
            iso: "400",
            focalLength: "40mm",
            aperture: "f/2.8"
        )
        var items = photoItems
        for i in stride(from: 0, to: items.count, by: 2) {
            items[i].exifSummary = mockExif
        }
        return items
    }

    // MARK: - Story authors

    static let storyAuthors: [GrainStoryAuthor] = [
        GrainStoryAuthor(profile: yukiProfile, storyCount: 3, latestAt: "2025-01-10T18:00:00Z"),
        GrainStoryAuthor(profile: profile2, storyCount: 1, latestAt: "2025-01-10T15:00:00Z"),
        GrainStoryAuthor(profile: profile3, storyCount: 2, latestAt: "2025-01-10T12:00:00Z"),
        GrainStoryAuthor(profile: profile4, storyCount: 1, latestAt: "2025-01-10T10:00:00Z"),
        GrainStoryAuthor(profile: profile5, storyCount: 4, latestAt: "2025-01-10T08:00:00Z"),
    ]

    // MARK: - Notifications

    static let notifications: [GrainNotification] = [
        // — Gallery favorite group: 4 users liked gallery1 within 48h → "Marcus and 3 others favorited your gallery"
        GrainNotification(
            uri: "at://did:plc:prevuser2/social.grain.notification/n1",
            reason: "gallery-favorite",
            createdAt: ago(2 * minute),
            author: profile2,
            galleryUri: gallery1.uri,
            galleryTitle: gallery1.title,
            galleryThumb: bundleImageURL("Mount_Hood_reflected_in_Mirror_Lake,_Oregon_thumb")
        ),
        GrainNotification(
            uri: "at://did:plc:prevuser6/social.grain.notification/n1b",
            reason: "gallery-favorite",
            createdAt: ago(15 * minute),
            author: profile6,
            galleryUri: gallery1.uri,
            galleryTitle: gallery1.title,
            galleryThumb: bundleImageURL("Mount_Hood_reflected_in_Mirror_Lake,_Oregon_thumb")
        ),
        GrainNotification(
            uri: "at://did:plc:prevuser7/social.grain.notification/n1c",
            reason: "gallery-favorite",
            createdAt: ago(1 * hour),
            author: profile7,
            galleryUri: gallery1.uri,
            galleryTitle: gallery1.title,
            galleryThumb: bundleImageURL("Mount_Hood_reflected_in_Mirror_Lake,_Oregon_thumb")
        ),
        GrainNotification(
            uri: "at://did:plc:prevuser8/social.grain.notification/n1d",
            reason: "gallery-favorite",
            createdAt: ago(2 * hour),
            author: profile8,
            galleryUri: gallery1.uri,
            galleryTitle: gallery1.title,
            galleryThumb: bundleImageURL("Mount_Hood_reflected_in_Mirror_Lake,_Oregon_thumb")
        ),
        // — Single gallery comment
        GrainNotification(
            uri: "at://did:plc:prevuser3/social.grain.notification/n2",
            reason: "gallery-comment",
            createdAt: ago(3 * hour),
            author: profile3,
            galleryUri: gallery1.uri,
            galleryTitle: gallery1.title,
            galleryThumb: bundleImageURL("Mount_Hood_reflected_in_Mirror_Lake,_Oregon_thumb"),
            commentText: "The light in the third frame is unreal. What film stock?"
        ),
        // — Follow group: 3 users followed within 48h → "Kai and 2 others followed you"
        GrainNotification(
            uri: "at://did:plc:prevuser4/social.grain.notification/n3",
            reason: "follow",
            createdAt: ago(5 * hour),
            author: profile4
        ),
        GrainNotification(
            uri: "at://did:plc:prevuser6/social.grain.notification/n3b",
            reason: "follow",
            createdAt: ago(8 * hour),
            author: profile6
        ),
        GrainNotification(
            uri: "at://did:plc:prevuser7/social.grain.notification/n3c",
            reason: "follow",
            createdAt: ago(10 * hour),
            author: profile7
        ),
        // — Story favorite group: 2 users liked the same story → "Sofia and 1 other favorited your story"
        GrainNotification(
            uri: "at://did:plc:prevuser3/social.grain.notification/n6",
            reason: "story-favorite",
            createdAt: ago(1 * day),
            author: profile3,
            storyUri: stories[0].uri,
            storyThumb: bundleImageURL("Portland_Japanese_Garden_maple_thumb")
        ),
        GrainNotification(
            uri: "at://did:plc:prevuser5/social.grain.notification/n6b",
            reason: "story-favorite",
            createdAt: ago(1 * day + 2 * hour),
            author: profile5,
            storyUri: stories[0].uri,
            storyThumb: bundleImageURL("Portland_Japanese_Garden_maple_thumb")
        ),
        // — Single gallery favorite (different gallery, no group)
        GrainNotification(
            uri: "at://did:plc:prevuser2/social.grain.notification/n4",
            reason: "gallery-favorite",
            createdAt: ago(2 * day),
            author: profile2,
            galleryUri: gallery2.uri,
            galleryTitle: gallery2.title,
            galleryThumb: bundleImageURL("Mount_Hood_reflected_in_Mirror_Lake,_Oregon_thumb")
        ),
        // — Single comment mention. `commentUri` targets a comment well down
        // the preview list so tapping the row scrolls the comment sheet to
        // demonstrate the deep-link behavior.
        GrainNotification(
            uri: "at://did:plc:prevuser5/social.grain.notification/n5",
            reason: "gallery-comment-mention",
            createdAt: ago(3 * day),
            author: profile5,
            galleryUri: gallery1.uri,
            galleryTitle: gallery1.title,
            galleryThumb: bundleImageURL("Portland_Japanese_Garden_maple_thumb"),
            commentText: "@yuki.grain.social this is the gallery I was telling you about — the autumn series",
            commentUri: "at://did:plc:prevuser5/social.grain.comment/c13"
        ),
        // — Single gallery mention
        GrainNotification(
            uri: "at://did:plc:prevuser4/social.grain.notification/n7",
            reason: "gallery-mention",
            createdAt: ago(3 * day + 2 * hour),
            author: profile4,
            galleryUri: gallery3.uri,
            galleryTitle: gallery3.title,
            galleryThumb: bundleImageURL("Mt_Herschel,_Antarctica,_Jan_2006_thumb")
        ),
        // — Single story comment
        GrainNotification(
            uri: "at://did:plc:prevuser6/social.grain.notification/n8",
            reason: "story-comment",
            createdAt: ago(3 * day + 5 * hour),
            author: profile6,
            storyUri: stories[0].uri,
            storyThumb: bundleImageURL("Portland_Japanese_Garden_maple_thumb"),
            commentText: "Love the autumn colors here"
        ),
        // — Single reply
        GrainNotification(
            uri: "at://did:plc:prevuser7/social.grain.notification/n9",
            reason: "reply",
            createdAt: ago(4 * day),
            author: profile7,
            galleryUri: gallery1.uri,
            galleryTitle: gallery1.title,
            galleryThumb: bundleImageURL("Portland_Japanese_Garden_maple_thumb"),
            commentText: "Totally agree, Portra is unmatched for skin tones"
        ),
        // — Single story favorite (different story, won't group with the pair above)
        GrainNotification(
            uri: "at://did:plc:prevuser8/social.grain.notification/n10",
            reason: "story-favorite",
            createdAt: ago(4 * day + 3 * hour),
            author: profile8,
            storyUri: stories[1].uri,
            storyThumb: bundleImageURL("Mount_Hood_reflected_in_Mirror_Lake,_Oregon_thumb")
        ),
        // — Single follow (>48h from the group, won't merge)
        GrainNotification(
            uri: "at://did:plc:prevuser5/social.grain.notification/n11",
            reason: "follow",
            createdAt: ago(5 * day),
            author: profile5
        ),
    ]

    // MARK: - Image generation

    static func gradientThumb(
        colors: [CGColor],
        size: CGSize = CGSize(width: 300, height: 300)
    ) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            let cgCtx = ctx.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: colors as CFArray,
                locations: nil
            ) else { return }
            cgCtx.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }
    }
}

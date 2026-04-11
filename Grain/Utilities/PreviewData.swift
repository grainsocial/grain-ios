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
        avatar: nil,
        cameras: ["Leica M6", "Mamiya RB67"],
        followersCount: 2847,
        followsCount: 412,
        galleryCount: 63,
        viewer: ActorViewerState(following: nil, followedBy: "at://preview/follow/1")
    )

    static let profile2 = GrainProfile(
        cid: "cid2", did: "did:plc:prevuser2",
        handle: "marcus.grain.social", displayName: "Marcus Webb"
    )

    static let profile3 = GrainProfile(
        cid: "cid3", did: "did:plc:prevuser3",
        handle: "sofia.grain.social", displayName: "Sofia Reyes"
    )

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
        creator: GrainProfile(
            cid: "cid", did: "did:plc:prevuser1",
            handle: "yuki.grain.social", displayName: "Yuki Tanaka"
        ),
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
        creator: GrainProfile(
            cid: "cid", did: "did:plc:prevuser2",
            handle: "marcus.grain.social", displayName: "Marcus Webb"
        ),
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
        creator: GrainProfile(
            cid: "cid", did: "did:plc:prevuser3",
            handle: "sofia.grain.social", displayName: "Sofia Reyes"
        ),
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
        GrainStoryAuthor(profile: GrainProfile(cid: "c1", did: "did:plc:prevuser1", handle: "yuki.grain.social", displayName: "Yuki"), storyCount: 3, latestAt: "2025-01-10T18:00:00Z"),
        GrainStoryAuthor(profile: GrainProfile(cid: "c2", did: "did:plc:prevuser2", handle: "marcus.grain.social", displayName: "Marcus"), storyCount: 1, latestAt: "2025-01-10T15:00:00Z"),
        GrainStoryAuthor(profile: GrainProfile(cid: "c3", did: "did:plc:prevuser3", handle: "sofia.grain.social", displayName: "Sofia"), storyCount: 2, latestAt: "2025-01-10T12:00:00Z"),
        GrainStoryAuthor(profile: GrainProfile(cid: "c4", did: "did:plc:prevuser4", handle: "kai.grain.social", displayName: "Kai"), storyCount: 1, latestAt: "2025-01-10T10:00:00Z"),
        GrainStoryAuthor(profile: GrainProfile(cid: "c5", did: "did:plc:prevuser5", handle: "leo.grain.social", displayName: "Leo"), storyCount: 4, latestAt: "2025-01-10T08:00:00Z"),
    ]

    // MARK: - Notifications

    static let notifications: [GrainNotification] = [
        GrainNotification(
            uri: "at://did:plc:prevuser2/social.grain.notification/n1",
            reason: "gallery-favorite",
            createdAt: "2025-01-10T19:30:00Z",
            author: profile2,
            galleryUri: gallery1.uri,
            galleryTitle: gallery1.title,
            galleryThumb: ""
        ),
        GrainNotification(
            uri: "at://did:plc:prevuser3/social.grain.notification/n2",
            reason: "gallery-comment",
            createdAt: "2025-01-10T19:00:00Z",
            author: profile3,
            galleryUri: gallery1.uri,
            galleryTitle: gallery1.title,
            galleryThumb: "",
            commentText: "The light in the third frame is unreal. What film stock?"
        ),
        GrainNotification(
            uri: "at://did:plc:prevuser4/social.grain.notification/n3",
            reason: "follow",
            createdAt: "2025-01-10T18:00:00Z",
            author: GrainProfile(cid: "c4", did: "did:plc:prevuser4", handle: "kai.grain.social", displayName: "Kai Müller")
        ),
        GrainNotification(
            uri: "at://did:plc:prevuser2/social.grain.notification/n4",
            reason: "gallery-favorite",
            createdAt: "2025-01-09T12:00:00Z",
            author: profile2,
            galleryUri: gallery2.uri,
            galleryTitle: gallery2.title,
            galleryThumb: ""
        ),
        GrainNotification(
            uri: "at://did:plc:prevuser5/social.grain.notification/n5",
            reason: "gallery-comment-mention",
            createdAt: "2025-01-09T10:00:00Z",
            author: GrainProfile(cid: "c5", did: "did:plc:prevuser5", handle: "leo.grain.social", displayName: "Leo Park"),
            galleryUri: gallery1.uri,
            galleryTitle: gallery1.title,
            galleryThumb: "",
            commentText: "Tagged you in a comment: @yuki.grain.social beautiful work!"
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

#if DEBUG
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

        // MARK: - Photos (thumb URLs empty → gray placeholder in preview)

        static let photos: [GrainPhoto] = [
            GrainPhoto(
                uri: "at://did:plc:prevuser1/social.grain.photo/p1",
                cid: "cid", thumb: "", fullsize: "",
                alt: "Rain-slicked street in Shinjuku at dusk, neon signs reflected in puddles",
                aspectRatio: AspectRatio(width: 4, height: 3)
            ),
            GrainPhoto(
                uri: "at://did:plc:prevuser1/social.grain.photo/p2",
                cid: "cid", thumb: "", fullsize: "",
                alt: "Cyclist passing a red torii gate",
                aspectRatio: AspectRatio(width: 3, height: 2)
            ),
            GrainPhoto(
                uri: "at://did:plc:prevuser1/social.grain.photo/p3",
                cid: "cid", thumb: "", fullsize: "",
                aspectRatio: AspectRatio(width: 1, height: 1)
            ),
            GrainPhoto(
                uri: "at://did:plc:prevuser1/social.grain.photo/p4",
                cid: "cid", thumb: "", fullsize: "",
                aspectRatio: AspectRatio(width: 16, height: 9)
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
            let specs: [(colors: [CGColor], label: String)] = [
                ([UIColor.systemOrange.cgColor, UIColor.systemPink.cgColor], ""),
                ([UIColor.systemBlue.cgColor, UIColor.systemIndigo.cgColor], ""),
                ([UIColor.systemGreen.cgColor, UIColor.systemTeal.cgColor], "Rain on Orchard St."),
                ([UIColor.systemPurple.cgColor, UIColor.systemPink.cgColor], ""),
                ([UIColor.systemRed.cgColor, UIColor.systemOrange.cgColor], ""),
                ([UIColor.systemTeal.cgColor, UIColor.systemBlue.cgColor], ""),
                ([UIColor.systemYellow.cgColor, UIColor.systemGreen.cgColor], "Torii gate at dusk"),
                ([UIColor.systemIndigo.cgColor, UIColor.systemPurple.cgColor], ""),
                ([UIColor.systemBrown.cgColor, UIColor.systemOrange.cgColor], ""),
                ([UIColor.systemMint.cgColor, UIColor.systemTeal.cgColor], ""),
                ([UIColor.systemCyan.cgColor, UIColor.systemBlue.cgColor], ""),
                ([UIColor.systemGray.cgColor, UIColor.systemGray3.cgColor], ""),
                ([UIColor.systemPink.cgColor, UIColor.systemRed.cgColor], "Market stalls, morning light"),
                ([UIColor.systemGreen.cgColor, UIColor.systemMint.cgColor], ""),
                ([UIColor.systemOrange.cgColor, UIColor.systemYellow.cgColor], ""),
            ]
            return specs.map { spec in
                let thumb = gradientThumb(colors: spec.colors)
                var item = PhotoItem(thumbnail: thumb, source: .camera(thumb))
                item.alt = spec.label
                return item
            }
        }

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
#endif

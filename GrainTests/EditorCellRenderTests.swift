@testable import Grain
import SwiftUI
import XCTest

/// The cells and chrome inside the create flow, plus the story ring that wraps
/// avatars everywhere else. All are small views with several visual states, and
/// none of them was reachable from the suite.
@MainActor
final class EditorCellRenderTests: GrainTestCase {
    private var account: TestAccount!

    /// Async overrides: the synchronous `setUp`/`tearDown` are nonisolated, so
    /// touching main-actor state from them warns.
    override func setUp() async throws {
        try await super.setUp()
        account = TestAccount()
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        account.restore()
        try await super.tearDown()
    }

    private func makeItem(alt: String = "", exif: ExifSummary? = nil) -> PhotoItem {
        let image = UIImage(systemName: "photo")!
        return PhotoItem(
            thumbnail: image,
            carouselPreview: image,
            source: .camera(image, metadata: nil),
            alt: alt,
            exifSummary: exif
        )
    }

    private func renderCell(
        item: PhotoItem,
        mode: EditorMode,
        isSelected: Bool = false,
        isDragging: Bool = false,
        hideDelete: Bool = false,
        deleteOpacity: CGFloat = 1,
        exifState: ExifState = .absent
    ) {
        var bound = item
        ViewRender.render(
            PhotoThumbnailCell(
                item: Binding(get: { bound }, set: { bound = $0 }),
                geometry: CellGeometry(mode: mode, maskSide: 72, photoAspect: bound.naturalAspect),
                isSelected: isSelected,
                isDragging: isDragging,
                hideDelete: hideDelete,
                deleteOpacity: deleteOpacity,
                exifState: exifState,
                onTap: {},
                onDelete: {}
            ),
            settle: 0
        )
    }

    // MARK: - PhotoThumbnailCell

    func testRendersAThumbnailCellInEveryMode() {
        for mode in EditorMode.allCases {
            renderCell(item: makeItem(), mode: mode)
        }
    }

    /// Selected, dragging and mid-fade are the states the strip and grid put a
    /// cell through, and each draws different chrome.
    func testRendersAThumbnailCellInItsInteractionStates() {
        renderCell(item: makeItem(), mode: .preview, isSelected: true)
        renderCell(item: makeItem(), mode: .reorder, isDragging: true)
        renderCell(item: makeItem(), mode: .preview, hideDelete: true)
        renderCell(item: makeItem(), mode: .preview, deleteOpacity: 0.4)
    }

    /// The captions cell shows the alt text it already has, which is a
    /// different layout from an empty one prompting for it.
    func testRendersACaptionsCellWithAndWithoutAltText() {
        renderCell(item: makeItem(alt: "A long alt description that wraps onto a second line."), mode: .captions)
        renderCell(item: makeItem(), mode: .captions)
    }

    func testRendersAThumbnailCellForEachExifState() {
        let exif = ExifSummary(
            camera: "Fujifilm X100V",
            lens: "23mm",
            exposure: nil,
            shutterSpeed: "1/500s",
            iso: "ISO 400",
            focalLength: "35mm",
            aperture: "f/2"
        )
        for state in [ExifState.absent, .inactive, .active] {
            renderCell(item: makeItem(exif: exif), mode: .captions, exifState: state)
        }
    }

    // MARK: - ExifChip

    private func chipSize(_ state: ExifState) -> CGSize {
        UIHostingController(rootView: ExifChip(state: state))
            .sizeThatFits(in: CGSize(width: 100, height: 100))
    }

    /// The chip is deliberately nothing at all when there's no exif, so it must
    /// not take up the badge's room on a photo that has none.
    func testTheExifChipTakesNoRoomWhenThereIsNoExif() {
        let absent = chipSize(.absent)
        let present = chipSize(.active)

        XCTAssertLessThan(absent.width, present.width)
        XCTAssertLessThan(absent.height, present.height)
        XCTAssertEqual(present.width, 19, accuracy: 0.5)
        XCTAssertEqual(present.height, 19, accuracy: 0.5)
    }

    /// Inactive and active are the same badge at different opacities, so they
    /// have to occupy identical space.
    func testTheInactiveChipIsTheSameSizeAsTheActiveOne() {
        XCTAssertEqual(chipSize(.inactive), chipSize(.active))
    }

    // MARK: - StoryRingView

    func testRendersAStoryRingInEachState() {
        for (hasStory, viewed) in [(false, false), (true, false), (true, true)] {
            ViewRender.render(
                StoryRingView(hasStory: hasStory, viewed: viewed, size: 48) {
                    AvatarView(url: nil, size: 48)
                },
                settle: 0
            )
        }
    }

    /// The ring is drawn as an overlay that spills outside the avatar, so it
    /// must never change the footprint — otherwise every row in the story strip
    /// and every avatar in a list would shift as story state loaded in.
    func testTheRingNeverChangesTheAvatarsFootprint() {
        func ringedSize(size: CGFloat, hasStory: Bool, viewed: Bool = false) -> CGSize {
            UIHostingController(
                rootView: StoryRingView(hasStory: hasStory, viewed: viewed, size: size) {
                    Color.clear.frame(width: size, height: size)
                }
            )
            .sizeThatFits(in: CGSize(width: 400, height: 400))
        }

        for size in [CGFloat(24), 32, 48, 68] {
            let plain = ringedSize(size: size, hasStory: false)
            XCTAssertEqual(plain.height, size, accuracy: 0.5, "Avatar of \(size) didn't measure as itself")
            XCTAssertEqual(ringedSize(size: size, hasStory: true), plain, "An unviewed ring resized the avatar")
            XCTAssertEqual(
                ringedSize(size: size, hasStory: true, viewed: true), plain,
                "A viewed ring resized the avatar"
            )
        }
    }

    // MARK: - Expandable description

    /// Three nested copies of the text are laid out to decide whether "more"
    /// belongs there, and the language check runs in a `.task` alongside.
    func testRendersAnExpandableDescription() {
        ViewRender.render(ExpandableDescriptionView(text: "Short caption."), settle: 0.2)
        ViewRender.render(
            ExpandableDescriptionView(
                text: String(repeating: "A caption long enough to need truncating. ", count: 8),
                onMentionTap: { _ in },
                onHashtagTap: { _ in }
            ),
            settle: 0.2
        )
    }

    /// A caption in another language grows a translate affordance, which is the
    /// branch the detector exists to drive.
    func testRendersADescriptionInAnotherLanguage() {
        ViewRender.render(
            ExpandableDescriptionView(text: "Fotografia tirada ao pôr do sol sobre a cidade."),
            settle: 0.3
        )
    }
}

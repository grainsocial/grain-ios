@testable import Grain
import SwiftUI
import XCTest

/// The facepile sits next to a caption that can wrap. When the caption wants
/// more room the row proposes less width to the facepile, so the facepile has
/// to report the same size regardless of what it is offered.
@MainActor
final class FacepileLayoutTests: XCTestCase {
    private struct Member: FacepileMember {
        let did: String
        let avatar: String?
    }

    private static let people = (0 ..< 3).map { Member(did: "did:plc:\($0)", avatar: nil) }

    /// Size the facepile reports when offered `proposedWidth` of horizontal room.
    private func facepileSize(proposedWidth: CGFloat, size: CGFloat = 20) -> CGSize {
        let host = UIHostingController(rootView: FacepileView(people: Self.people, size: size))
        return host.sizeThatFits(in: CGSize(width: proposedWidth, height: .greatestFiniteMagnitude))
    }

    func testFacepileIgnoresACrampedWidthProposal() {
        let roomy = facepileSize(proposedWidth: 350)
        let cramped = facepileSize(proposedWidth: 24)

        XCTAssertEqual(roomy.width, cramped.width, accuracy: 0.5, "Facepile narrowed when squeezed")
        XCTAssertEqual(roomy.height, cramped.height, accuracy: 0.5, "Facepile shrank when squeezed")
    }

    func testThreeTwentyPointAvatarsOverlappingByEight() {
        let size = facepileSize(proposedWidth: 350)

        XCTAssertEqual(size.width, 20 * 3 - 8 * 2, accuracy: 0.5)
        XCTAssertEqual(size.height, 20, accuracy: 0.5)
    }

    func testFacepileSizeScalesWithTheSizeParameter() {
        XCTAssertEqual(facepileSize(proposedWidth: 350, size: 24).height, 24, accuracy: 0.5)
    }

    /// Measures the facepile as laid out inside the real caption row, where the
    /// caption competes for width. ImageRenderer runs a full layout pass, so the
    /// GeometryReader below reports the size the row actually granted.
    private func facepileSizeInRow(caption: String, width: CGFloat) -> CGSize {
        final class Box {
            var size = CGSize.zero
        }
        let box = Box()

        let row = HStack(spacing: 6) {
            FacepileView(people: Self.people, size: 20)
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear { box.size = geo.size }
                    }
                )
            Text(caption)
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(width: width)

        let renderer = ImageRenderer(content: row)
        _ = renderer.uiImage
        return box.size
    }

    /// Caption height vs facepile height as Dynamic Type grows.
    private func rowMetrics(_ type: DynamicTypeSize) -> (caption: CGFloat, facepile: CGFloat) {
        let caption = UIHostingController(
            rootView: Text("Favorited by Someone and Someone Else")
                .font(.caption)
                .lineLimit(2)
                .dynamicTypeSize(type)
        ).sizeThatFits(in: CGSize(width: 250, height: CGFloat.greatestFiniteMagnitude))

        let facepile = UIHostingController(
            rootView: FacepileView(people: Self.people, size: 20).dynamicTypeSize(type)
        ).sizeThatFits(in: CGSize(width: 350, height: CGFloat.greatestFiniteMagnitude))

        return (caption.height, facepile.height)
    }

    func testFacepileGrowsWithTheCaptionUnderDynamicType() {
        let small = rowMetrics(.large)
        let big = rowMetrics(.accessibility3)

        XCTAssertGreaterThan(big.caption, small.caption, "Caption should grow with Dynamic Type")
        XCTAssertGreaterThan(
            big.facepile, small.facepile,
            "Facepile should grow with the caption, not stay pinned while text around it doubles"
        )
    }

    func testFacepileIsUnchangedAtTheDefaultTextSize() {
        XCTAssertEqual(rowMetrics(.large).facepile, 20, accuracy: 0.5)
    }

    func testFacepileKeepsItsSizeWhenTheCaptionWraps() {
        let short = facepileSizeInRow(caption: "Favorited by A", width: 350)
        let wrapping = facepileSizeInRow(
            caption: "Favorited by Bartholomew Cubbins-Fitzgerald, Wilhelmina Featherstonehaugh and others you follow",
            width: 350
        )

        XCTAssertNotEqual(short, .zero, "Measurement harness failed to lay out")
        XCTAssertEqual(short.width, wrapping.width, accuracy: 0.5, "Facepile width changed when the caption wrapped")
        XCTAssertEqual(short.height, wrapping.height, accuracy: 0.5, "Facepile height changed when the caption wrapped")
    }
}

@testable import Grain
import SwiftUI
import XCTest

/// The photo strip is scrolled by hand rather than by a ScrollView, so its
/// bounds, snapping and edge fade are all arithmetic this class owns. Getting
/// the clamp wrong lets the strip drift off its own content, which is invisible
/// in a screenshot and obvious the moment you drag.
@MainActor
final class StripScrollStateTests: XCTestCase {
    /// Matches the layout constants: 72pt thumbs, 20pt apart.
    private let thumbStride: CGFloat = 92
    private let width: CGFloat = 402

    /// Five thumbs are 440pt of content in a 402pt window — wider than the
    /// window, so there is real scrolling range to clamp against.
    private let overflowingCount = 5

    /// Two thumbs are 164pt of content, which fits, so the strip must not move.
    private let fittingCount = 2

    // MARK: - clamp

    func testClampRefusesToScrollPastTheStart() {
        XCTAssertEqual(
            StripScrollState.clamp(200, itemCount: overflowingCount, containerWidth: width),
            0
        )
    }

    func testClampRefusesToScrollPastTheEnd() {
        // 402 - (5 * 72 + 4 * 20) = -38pt of travel.
        XCTAssertEqual(
            StripScrollState.clamp(-1000, itemCount: overflowingCount, containerWidth: width),
            -38,
            accuracy: 0.01
        )
    }

    func testClampLeavesAnOffsetInsideTheRangeAlone() {
        XCTAssertEqual(
            StripScrollState.clamp(-20, itemCount: overflowingCount, containerWidth: width),
            -20,
            accuracy: 0.01
        )
    }

    func testContentNarrowerThanTheWindowCannotScroll() {
        XCTAssertEqual(StripScrollState.clamp(-50, itemCount: fittingCount, containerWidth: width), 0)
        XCTAssertEqual(StripScrollState.clamp(50, itemCount: fittingCount, containerWidth: width), 0)
    }

    /// Called during layout before the container has been measured, so both
    /// degenerate inputs have to return something rather than divide by zero.
    func testClampIsZeroWithNoItemsOrNoWidth() {
        XCTAssertEqual(StripScrollState.clamp(-50, itemCount: 0, containerWidth: width), 0)
        XCTAssertEqual(StripScrollState.clamp(-50, itemCount: overflowingCount, containerWidth: 0), 0)
    }

    // MARK: - offset(forIndex:)

    func testOffsetForAnIndexIsAlwaysInsideTheScrollableRange() {
        for index in 0 ..< overflowingCount {
            let offset = StripScrollState.offset(
                forIndex: index, itemCount: overflowingCount, containerWidth: width
            )
            XCTAssertLessThanOrEqual(offset, 0)
            XCTAssertGreaterThanOrEqual(offset, -38.01)
        }
    }

    func testOffsetMovesLeftAsTheIndexGrows() throws {
        let offsets = (0 ..< 12).map {
            StripScrollState.offset(forIndex: $0, itemCount: 12, containerWidth: width)
        }
        for (earlier, later) in zip(offsets, offsets.dropFirst()) {
            XCTAssertLessThanOrEqual(later, earlier, "Scrolling forward should never move the strip right")
        }
        XCTAssertLessThan(try XCTUnwrap(offsets.last), try XCTUnwrap(offsets.first), "The last thumb should sit further along than the first")
    }

    /// A thumb far enough from either end gets centred exactly.
    func testAMiddleThumbIsCentred() {
        let index = 6
        let offset = StripScrollState.offset(forIndex: index, itemCount: 12, containerWidth: width)
        let centreOfThumb = offset + CGFloat(index) * thumbStride + 36

        XCTAssertEqual(centreOfThumb, width / 2, accuracy: 0.01)
    }

    func testOffsetIsZeroWithNoItems() {
        XCTAssertEqual(StripScrollState.offset(forIndex: 0, itemCount: 0, containerWidth: width), 0)
    }

    // MARK: - currentOffset

    func testCurrentOffsetTracksTheLiveDrag() {
        let state = StripScrollState()
        state.baseOffset = -30
        state.dragTranslation = -12

        XCTAssertEqual(state.currentOffset, -42, accuracy: 0.01)
    }

    // MARK: - handleDragEnded

    func testADragEndSnapsToAThumbAndClearsTheLiveTranslation() {
        let state = StripScrollState()
        state.dragTranslation = -40

        state.handleDragEnded(
            translation: -40, predictedEnd: -60,
            containerWidth: width, itemCount: 12
        )

        XCTAssertEqual(state.dragTranslation, 0, "Translation must fold into the base or the strip double-counts it")

        let restPositions = (0 ..< 12).map {
            StripScrollState.offset(forIndex: $0, itemCount: 12, containerWidth: width)
        }
        XCTAssertTrue(
            restPositions.contains { abs($0 - state.baseOffset) < 0.01 },
            "Rest position \(state.baseOffset) is not any thumb's centred offset"
        )
    }

    /// Flicking hard should land further along than releasing dead — the
    /// predicted end is the whole point of taking velocity into account.
    func testAFastFlickTravelsFurtherThanASlowRelease() {
        let gentle = StripScrollState()
        gentle.handleDragEnded(translation: -40, predictedEnd: -40, containerWidth: width, itemCount: 12)

        let flick = StripScrollState()
        flick.handleDragEnded(translation: -40, predictedEnd: -400, containerWidth: width, itemCount: 12)

        XCTAssertLessThan(flick.baseOffset, gentle.baseOffset)
    }

    func testADragCannotEndPastTheEndOfTheContent() {
        let state = StripScrollState()
        state.handleDragEnded(
            translation: -5000, predictedEnd: -9000,
            containerWidth: width, itemCount: overflowingCount
        )

        XCTAssertEqual(state.baseOffset, -38, accuracy: 0.01)
    }

    // MARK: - scrollToIndex

    func testScrollingToAnIndexCentresIt() {
        let state = StripScrollState()
        state.scrollToIndex(6, itemCount: 12, containerWidth: width, animated: false)

        XCTAssertEqual(
            state.baseOffset,
            StripScrollState.offset(forIndex: 6, itemCount: 12, containerWidth: width),
            accuracy: 0.01
        )
    }

    /// Selection changes fire this constantly; re-animating to the position the
    /// strip is already in would interrupt an in-flight drag for nothing.
    func testScrollingToWhereTheStripAlreadyIsDoesNothing() {
        let state = StripScrollState()
        let target = StripScrollState.offset(forIndex: 3, itemCount: 12, containerWidth: width)
        state.baseOffset = target - 0.2

        state.scrollToIndex(3, itemCount: 12, containerWidth: width, animated: false)

        XCTAssertEqual(state.baseOffset, target - 0.2, accuracy: 0.001, "A sub-half-point move should be skipped")
    }

    // MARK: - deleteOpacity

    func testTheDeleteButtonIsFullyVisibleForAThumbInView() {
        let state = StripScrollState()
        XCTAssertEqual(state.deleteOpacity(cellIndex: 0, containerWidth: width), 1, accuracy: 0.01)
        XCTAssertEqual(state.deleteOpacity(cellIndex: 1, containerWidth: width), 1, accuracy: 0.01)
    }

    func testTheDeleteButtonIsGoneForAThumbScrolledOffTheLeft() {
        let state = StripScrollState()
        state.baseOffset = -400

        XCTAssertEqual(state.deleteOpacity(cellIndex: 0, containerWidth: width), 0, accuracy: 0.01)
    }

    /// The button fades rather than popping, so a thumb partway off the edge
    /// has to land strictly between the two extremes.
    func testTheDeleteButtonFadesAtTheLeftEdge() {
        let state = StripScrollState()
        // Leaves the button's centre 7pt inside the clip, mid-fade.
        state.baseOffset = -65

        let opacity = state.deleteOpacity(cellIndex: 0, containerWidth: width)

        XCTAssertGreaterThan(opacity, 0)
        XCTAssertLessThan(opacity, 1)
    }

    func testTheDeleteButtonFadesAtTheRightEdge() {
        let state = StripScrollState()
        // Cell 0 pushed until only 7pt of it is left inside the right edge.
        state.baseOffset = width - 7

        let opacity = state.deleteOpacity(cellIndex: 0, containerWidth: width)

        XCTAssertGreaterThan(opacity, 0)
        XCTAssertLessThan(opacity, 1)
    }

    func testTheFadeIsMonotonicAsAThumbLeavesTheLeftEdge() {
        var previous: CGFloat = 1
        for offset in stride(from: CGFloat(-50), through: -75, by: -1) {
            let state = StripScrollState()
            state.baseOffset = offset
            let opacity = state.deleteOpacity(cellIndex: 0, containerWidth: width)
            XCTAssertLessThanOrEqual(opacity, previous + 0.001, "Opacity rose while the thumb kept leaving")
            previous = opacity
        }
        XCTAssertEqual(previous, 0, accuracy: 0.01, "The button should be gone by the time the thumb is")
    }
}

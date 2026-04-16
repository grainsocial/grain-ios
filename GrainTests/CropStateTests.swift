@testable import Grain
import XCTest

@MainActor
final class CropStateTests: XCTestCase {
    private var state: CropState!

    override func setUp() {
        super.setUp()
        state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)
        state.cropRect = CGRect(x: 0, y: 0, width: 400, height: 600)
    }

    // MARK: - Coordinate transforms

    func testViewToOverlayIdentityAtDefaultScaleAndOffset() {
        let point = CGPoint(x: 150, y: 300)
        let result = state.viewToOverlayPoint(point)
        XCTAssertEqual(result.x, point.x, accuracy: 0.001)
        XCTAssertEqual(result.y, point.y, accuracy: 0.001)
    }

    func testOverlayToScreenIdentityAtDefaultScaleAndOffset() {
        let point = CGPoint(x: 150, y: 300)
        let result = state.overlayToScreenPoint(point)
        XCTAssertEqual(result.x, point.x, accuracy: 0.001)
        XCTAssertEqual(result.y, point.y, accuracy: 0.001)
    }

    func testViewToOverlayAndBackIsRoundTrip() {
        state.imageScale = 2.5
        state.imageOffset = CGSize(width: 30, height: -20)

        let original = CGPoint(x: 120, y: 350)
        let overlay = state.viewToOverlayPoint(original)
        let backToView = state.overlayToScreenPoint(overlay)

        XCTAssertEqual(backToView.x, original.x, accuracy: 0.001)
        XCTAssertEqual(backToView.y, original.y, accuracy: 0.001)
    }

    func testOverlayToScreenAndBackIsRoundTrip() {
        state.imageScale = 1.8
        state.imageOffset = CGSize(width: -15, height: 40)

        let original = CGPoint(x: 200, y: 100)
        let screen = state.overlayToScreenPoint(original)
        let backToOverlay = state.viewToOverlayPoint(screen)

        XCTAssertEqual(backToOverlay.x, original.x, accuracy: 0.001)
        XCTAssertEqual(backToOverlay.y, original.y, accuracy: 0.001)
    }

    func testScale2xMagnifiesPointsAwayFromCenter() {
        state.imageScale = 2.0
        state.imageOffset = .zero

        // Center of the frame should be unchanged
        let center = CGPoint(x: 200, y: 300)
        let centerScreen = state.overlayToScreenPoint(center)
        XCTAssertEqual(centerScreen.x, center.x, accuracy: 0.001)
        XCTAssertEqual(centerScreen.y, center.y, accuracy: 0.001)

        // A point 50px right of center should be 100px right in screen space
        let offCenter = CGPoint(x: 250, y: 300)
        let offCenterScreen = state.overlayToScreenPoint(offCenter)
        XCTAssertEqual(offCenterScreen.x, 300, accuracy: 0.001)
        XCTAssertEqual(offCenterScreen.y, 300, accuracy: 0.001)

        // Top-left corner should move further away from center
        let topLeft = CGPoint(x: 0, y: 0)
        let topLeftScreen = state.overlayToScreenPoint(topLeft)
        XCTAssertEqual(topLeftScreen.x, -200, accuracy: 0.001)
        XCTAssertEqual(topLeftScreen.y, -300, accuracy: 0.001)
    }

    func testViewToOverlayTranslationScalesDown() {
        state.imageScale = 3.0
        let translation = CGSize(width: 90, height: 60)
        let result = state.viewToOverlayTranslation(translation)
        XCTAssertEqual(result.width, 30, accuracy: 0.001)
        XCTAssertEqual(result.height, 20, accuracy: 0.001)
    }

    // MARK: - Crop clamping (nearestValidCrop)

    func testNearestValidCropKeepsRectInsideBounds() {
        // Rect shifted outside to the right
        let shifted = CGRect(x: 350, y: 0, width: 200, height: 100)
        let clamped = state.nearestValidCrop(shifted)

        XCTAssertLessThanOrEqual(clamped.maxX, 400)
        XCTAssertGreaterThanOrEqual(clamped.minX, 0)
        XCTAssertLessThanOrEqual(clamped.maxY, 600)
        XCTAssertGreaterThanOrEqual(clamped.minY, 0)
    }

    func testNearestValidCropShiftsNegativeOrigin() {
        let shifted = CGRect(x: -50, y: -30, width: 100, height: 100)
        let clamped = state.nearestValidCrop(shifted)

        XCTAssertGreaterThanOrEqual(clamped.minX, 0)
        XCTAssertGreaterThanOrEqual(clamped.minY, 0)
        // Size should be preserved since it fits within bounds
        XCTAssertEqual(clamped.width, 100, accuracy: 0.001)
        XCTAssertEqual(clamped.height, 100, accuracy: 0.001)
    }

    func testNearestValidCropShrinksTooLargeRect() {
        let huge = CGRect(x: 0, y: 0, width: 800, height: 1200)
        let clamped = state.nearestValidCrop(huge)

        XCTAssertLessThanOrEqual(clamped.width, 400)
        XCTAssertLessThanOrEqual(clamped.height, 600)
    }

    func testNearestValidCropWithRatioMaintainsAspect() {
        let ratio: CGFloat = 16.0 / 9.0
        let rect = CGRect(x: 50, y: 50, width: 300, height: 300)
        let clamped = state.nearestValidCrop(rect, ratio: ratio)

        let resultRatio = clamped.width / clamped.height
        XCTAssertEqual(resultRatio, ratio, accuracy: 0.01)
        XCTAssertLessThanOrEqual(clamped.maxX, 400)
        XCTAssertLessThanOrEqual(clamped.maxY, 600)
    }

    func testNearestValidCropEnforcesMinimumSize() {
        let tiny = CGRect(x: 100, y: 100, width: 10, height: 10)
        let clamped = state.nearestValidCrop(tiny)

        XCTAssertGreaterThanOrEqual(clamped.width, 44)
        XCTAssertGreaterThanOrEqual(clamped.height, 44)
    }

    func testNearestValidCropWithRatioStaysInBounds() {
        // Tall ratio that would exceed height
        let ratio: CGFloat = 4.0 / 5.0
        let rect = CGRect(x: 0, y: 0, width: 400, height: 400)
        let clamped = state.nearestValidCrop(rect, ratio: ratio)

        XCTAssertLessThanOrEqual(clamped.maxX, 400)
        XCTAssertLessThanOrEqual(clamped.maxY, 600)
        let resultRatio = clamped.width / clamped.height
        XCTAssertEqual(resultRatio, ratio, accuracy: 0.01)
    }

    // MARK: - Reset methods

    func testResetAllResetsEverything() {
        state.rotationAngle = 90
        state.selectedPreset = .square
        state.isRatioLocked = true
        state.lockedRatio = 1.0
        state.isPortrait = true
        state.imageScale = 2.0
        state.imageOffset = CGSize(width: 50, height: 50)
        state.cropRect = CGRect(x: 50, y: 50, width: 100, height: 100)

        state.resetAll()

        XCTAssertEqual(state.rotationAngle, 0)
        XCTAssertEqual(state.selectedPreset, .free)
        XCTAssertFalse(state.isRatioLocked)
        XCTAssertNil(state.lockedRatio)
        XCTAssertFalse(state.isPortrait)
        XCTAssertEqual(state.imageScale, 1.0)
        XCTAssertEqual(state.imageOffset, .zero)
        XCTAssertEqual(state.cropRect, state.imageDisplayFrame)
    }

    func testResetViewOnlyResetsZoomAndPan() {
        state.rotationAngle = 180
        state.cropRect = CGRect(x: 50, y: 50, width: 200, height: 200)
        state.imageScale = 3.0
        state.imageOffset = CGSize(width: 40, height: -20)

        let savedCrop = state.cropRect
        let savedRotation = state.rotationAngle

        state.resetView()

        XCTAssertEqual(state.imageScale, 1.0)
        XCTAssertEqual(state.imageOffset, .zero)
        // Crop rect and rotation should be preserved
        XCTAssertEqual(state.cropRect, savedCrop)
        XCTAssertEqual(state.rotationAngle, savedRotation)
    }

    func testIsViewModifiedWhenZoomed() {
        XCTAssertFalse(state.isViewModified)

        state.imageScale = 1.5
        XCTAssertTrue(state.isViewModified)
    }

    func testIsViewModifiedWhenPanned() {
        XCTAssertFalse(state.isViewModified)

        state.imageOffset = CGSize(width: 10, height: 0)
        XCTAssertTrue(state.isViewModified)
    }

    func testIsViewModifiedFalseAfterResetView() {
        state.imageScale = 2.0
        state.imageOffset = CGSize(width: 20, height: 30)
        XCTAssertTrue(state.isViewModified)

        state.resetView()
        XCTAssertFalse(state.isViewModified)
    }

    // MARK: - Aspect ratios

    func testEffectiveLockedRatioForSquare() {
        state.selectedPreset = .square
        XCTAssertEqual(state.effectiveLockedRatio, 1.0)
    }

    func testEffectiveLockedRatioFor4x3Landscape() throws {
        state.selectedPreset = .ratio4x3
        state.isPortrait = false
        XCTAssertEqual(try XCTUnwrap(state.effectiveLockedRatio), 4.0 / 3.0, accuracy: 0.001)
    }

    func testEffectiveLockedRatioFor4x3Portrait() throws {
        state.selectedPreset = .ratio4x3
        state.isPortrait = true
        XCTAssertEqual(try XCTUnwrap(state.effectiveLockedRatio), 3.0 / 4.0, accuracy: 0.001)
    }

    func testEffectiveLockedRatioFor4x5() throws {
        state.selectedPreset = .ratio4x5
        state.isPortrait = false
        XCTAssertEqual(try XCTUnwrap(state.effectiveLockedRatio), 4.0 / 5.0, accuracy: 0.001)
    }

    func testEffectiveLockedRatioFor16x9() throws {
        state.selectedPreset = .ratio16x9
        state.isPortrait = false
        XCTAssertEqual(try XCTUnwrap(state.effectiveLockedRatio), 16.0 / 9.0, accuracy: 0.001)
    }

    func testEffectiveLockedRatioForFreeIsNil() {
        state.selectedPreset = .free
        state.isRatioLocked = false
        XCTAssertNil(state.effectiveLockedRatio)
    }

    func testEffectiveLockedRatioForOriginalUsesImageRatio() throws {
        state.selectedPreset = .original
        state.originalImageRatio = 1.5
        XCTAssertEqual(try XCTUnwrap(state.effectiveLockedRatio), 1.5, accuracy: 0.001)
    }

    func testEffectiveLockedRatioForFreeWithLock() throws {
        state.selectedPreset = .free
        state.isRatioLocked = true
        state.lockedRatio = 1.25
        XCTAssertEqual(try XCTUnwrap(state.effectiveLockedRatio), 1.25, accuracy: 0.001)
    }

    func testToggleOrientationFlipsRatio() throws {
        state.selectedPreset = .ratio4x3
        state.isPortrait = false
        let landscapeRatio = try XCTUnwrap(state.effectiveLockedRatio)

        state.toggleOrientation()

        XCTAssertTrue(state.isPortrait)
        let portraitRatio = try XCTUnwrap(state.effectiveLockedRatio)
        XCTAssertEqual(portraitRatio, 1.0 / landscapeRatio, accuracy: 0.001)
    }

    func testToggleRatioLockCapturesCurrentCropAspect() throws {
        state.cropRect = CGRect(x: 0, y: 0, width: 300, height: 200)
        state.selectedPreset = .free
        state.isRatioLocked = false

        state.toggleRatioLock()

        XCTAssertTrue(state.isRatioLocked)
        XCTAssertEqual(try XCTUnwrap(state.lockedRatio), 300.0 / 200.0, accuracy: 0.001)
    }

    func testToggleRatioLockUnlockClearsRatio() {
        state.selectedPreset = .free
        state.isRatioLocked = true
        state.lockedRatio = 1.5

        state.toggleRatioLock()

        XCTAssertFalse(state.isRatioLocked)
        XCTAssertNil(state.lockedRatio)
    }

    func testShowOrientationToggle() {
        state.selectedPreset = .ratio4x3
        XCTAssertTrue(state.showOrientationToggle)

        state.selectedPreset = .square
        XCTAssertFalse(state.showOrientationToggle)

        state.selectedPreset = .free
        XCTAssertFalse(state.showOrientationToggle)
    }

    // MARK: - Hit testing

    func testCornerHitTestHasHighestPriority() {
        state.cropRect = CGRect(x: 50, y: 50, width: 300, height: 400)

        // Point exactly at top-left corner
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 50, y: 50)), .topLeft)
        // Point exactly at top-right corner
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 350, y: 50)), .topRight)
        // Point exactly at bottom-left corner
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 50, y: 450)), .bottomLeft)
        // Point exactly at bottom-right corner
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 350, y: 450)), .bottomRight)
    }

    func testCornerNearbyPointDetected() {
        state.cropRect = CGRect(x: 50, y: 50, width: 300, height: 400)

        // A few pixels from top-left corner
        let result = state.hitTest(point: CGPoint(x: 55, y: 55))
        XCTAssertEqual(result, .topLeft)
    }

    func testInsideCropReturnsMoveCrop() {
        state.cropRect = CGRect(x: 50, y: 50, width: 300, height: 400)

        // Center of crop rect
        let result = state.hitTest(point: CGPoint(x: 200, y: 250))
        XCTAssertEqual(result, .moveCrop)
    }

    func testOutsideCropReturnsPanImage() {
        state.cropRect = CGRect(x: 100, y: 100, width: 200, height: 200)

        // Well outside crop rect and edge hit zones
        let result = state.hitTest(point: CGPoint(x: 5, y: 5))
        XCTAssertEqual(result, .panImage)
    }

    func testTopEdgeNotHandledByHitTest() {
        // Top edge is handled by the move indicator (screen-space check in
        // the gesture coordinator), so hitTest returns .moveCrop for points
        // along the top edge that are still inside the crop rect.
        state.cropRect = CGRect(x: 50, y: 100, width: 300, height: 400)

        let result = state.hitTest(point: CGPoint(x: 200, y: 100))
        XCTAssertEqual(result, .moveCrop)
    }

    func testEdgeHitTestOnBottomEdge() {
        state.cropRect = CGRect(x: 50, y: 100, width: 300, height: 400)

        // Point along the bottom edge, midway horizontally (at the bar)
        let result = state.hitTest(point: CGPoint(x: 200, y: 500))
        XCTAssertEqual(result, .bottom)
    }

    func testEdgeHitTestOnLeftEdge() {
        state.cropRect = CGRect(x: 50, y: 100, width: 300, height: 400)

        // Point along the left edge, midway vertically (at the bar)
        let result = state.hitTest(point: CGPoint(x: 50, y: 300))
        XCTAssertEqual(result, .left)
    }

    func testEdgeHitTestOnRightEdge() {
        state.cropRect = CGRect(x: 50, y: 100, width: 300, height: 400)

        // Point along the right edge, midway vertically (at the bar)
        let result = state.hitTest(point: CGPoint(x: 350, y: 300))
        XCTAssertEqual(result, .right)
    }

    func testCornerTakesPriorityOverEdge() {
        state.cropRect = CGRect(x: 50, y: 50, width: 300, height: 400)

        // Point near top-left corner — within corner hit radius but also near top edge
        let result = state.hitTest(point: CGPoint(x: 52, y: 50))
        XCTAssertEqual(result, .topLeft)
    }

    func testEdgeBetweenCornerAndBarReturnsMoveOrPan() {
        // Large crop so edge bars are visible
        state.cropRect = CGRect(x: 50, y: 50, width: 300, height: 400)

        // Point on the bottom edge but far from both corner and midpoint bar —
        // between the corner arm tip and the edge bar. Should NOT return .bottom.
        let result = state.hitTest(point: CGPoint(x: 120, y: 450))
        XCTAssertNotEqual(result, .bottom,
                          "Gap between corner and edge bar should not register as edge handle")
    }

    func testEdgeHandlesHiddenOnSmallCrop() {
        // Tiny crop where edge bars would overlap corners
        state.cropRect = CGRect(x: 150, y: 250, width: 80, height: 80)

        // Midpoint of bottom edge — should NOT return .bottom when crop is too small
        let result = state.hitTest(point: CGPoint(x: 190, y: 330))
        XCTAssertNotEqual(result, .bottom,
                          "Edge handles should be hidden when crop rect is too small")
    }

    func testEdgeHandlesVisibleOnLargeCrop() {
        // Large crop where edge bars fit comfortably
        state.cropRect = CGRect(x: 0, y: 0, width: 400, height: 600)

        // Midpoint of bottom edge
        let result = state.hitTest(point: CGPoint(x: 200, y: 600))
        XCTAssertEqual(result, .bottom)
    }

    func testCornerWinsOverEdgeNearDiagonal() {
        state.cropRect = CGRect(x: 50, y: 50, width: 300, height: 400)

        // Point slightly off the bottom-left corner diagonally — should still
        // be caught by the 1.5× corner radius, not the left or bottom edge
        let result = state.hitTest(point: CGPoint(x: 65, y: 435))
        XCTAssertEqual(result, .bottomLeft)
    }

    // MARK: - Image offset clamping

    func testClampImageOffsetAtScale1ReturnsZero() {
        state.imageScale = 1.0
        let result = state.clampImageOffset(CGSize(width: 100, height: -50))
        XCTAssertEqual(result.width, 0, accuracy: 0.001)
        XCTAssertEqual(result.height, 0, accuracy: 0.001)
    }

    func testClampImageOffsetAtScale2AllowsHalfFrame() {
        state.imageScale = 2.0
        // At 2x on a 400-wide frame, max offset is 400 * (2-1)/2 = 200
        let result = state.clampImageOffset(CGSize(width: 300, height: -400))
        XCTAssertEqual(result.width, 200, accuracy: 0.001)
        XCTAssertEqual(result.height, -300, accuracy: 0.001) // 600*(2-1)/2 = 300
    }

    // MARK: - Rotation helpers

    func testRotationDegreesNormalization() {
        state.rotationAngle = 0
        XCTAssertEqual(state.rotationDegrees, 0)

        state.rotationAngle = 90
        XCTAssertEqual(state.rotationDegrees, 90)

        state.rotationAngle = 360
        XCTAssertEqual(state.rotationDegrees, 0)

        state.rotationAngle = 450
        XCTAssertEqual(state.rotationDegrees, 90)

        state.rotationAngle = -90
        XCTAssertEqual(state.rotationDegrees, 270)
    }

    // MARK: - screenCropRect

    func testScreenCropRectMatchesCropAtDefaultTransform() {
        state.cropRect = CGRect(x: 50, y: 50, width: 200, height: 300)
        let screen = state.screenCropRect
        XCTAssertEqual(screen.origin.x, 50, accuracy: 0.001)
        XCTAssertEqual(screen.origin.y, 50, accuracy: 0.001)
        XCTAssertEqual(screen.width, 200, accuracy: 0.001)
        XCTAssertEqual(screen.height, 300, accuracy: 0.001)
    }

    func testScreenCropRectScalesWithZoom() {
        state.cropRect = CGRect(x: 150, y: 200, width: 100, height: 100)
        state.imageScale = 2.0
        state.imageOffset = .zero

        let screen = state.screenCropRect
        // Width/height should double
        XCTAssertEqual(screen.width, 200, accuracy: 0.001)
        XCTAssertEqual(screen.height, 200, accuracy: 0.001)
    }
}

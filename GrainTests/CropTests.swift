@testable import Grain
import UIKit
import XCTest

final class CropTests: XCTestCase {
    private let eps: CGFloat = 1e-6

    // MARK: - Helpers

    /// Solid-color 1x-scale image with exact point dimensions.
    private func makeImage(width: Int, height: Int) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: fmt
        ).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func assertRectEqual(
        _ a: CGRect, _ b: CGRect,
        accuracy: CGFloat = 1e-6, _ msg: String = "", line: UInt = #line
    ) {
        XCTAssertEqual(a.origin.x, b.origin.x, accuracy: accuracy, msg, line: line)
        XCTAssertEqual(a.origin.y, b.origin.y, accuracy: accuracy, msg, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: accuracy, msg, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: accuracy, msg, line: line)
    }

    // MARK: - viewRectToNormalized

    /// Full crop with no pan/zoom must produce the unit rect.
    func testViewToNormalized_identity() {
        let frame = CGRect(x: 50, y: 100, width: 300, height: 400)
        let result = ImageCropper.viewRectToNormalized(
<<<<<<< Updated upstream
            frame, imageDisplayFrame: frame, imageOffset: .zero, imageScale: 1
        )
=======
            frame, imageDisplayFrame: frame, imageOffset: .zero, imageScale: 1)
>>>>>>> Stashed changes
        assertRectEqual(result, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Left half of the image → x=0, w=0.5.
    func testViewToNormalized_leftHalf() {
        let frame = CGRect(x: 50, y: 100, width: 300, height: 400)
        let crop = CGRect(x: 50, y: 100, width: 150, height: 400)
        let result = ImageCropper.viewRectToNormalized(
<<<<<<< Updated upstream
            crop, imageDisplayFrame: frame, imageOffset: .zero, imageScale: 1
        )
=======
            crop, imageDisplayFrame: frame, imageOffset: .zero, imageScale: 1)
>>>>>>> Stashed changes
        assertRectEqual(result, CGRect(x: 0, y: 0, width: 0.5, height: 1))
    }

    /// At 2x zoom, the full view covers the center 25% of the image.
    /// Traced through the formula:
    ///   scaledW/H = 400, imgOrigin = -100,
    ///   relX = (0 - -100)/400 = 0.25
    func testViewToNormalized_zoom2x() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let result = ImageCropper.viewRectToNormalized(
<<<<<<< Updated upstream
            frame, imageDisplayFrame: frame, imageOffset: .zero, imageScale: 2
        )
=======
            frame, imageDisplayFrame: frame, imageOffset: .zero, imageScale: 2)
>>>>>>> Stashed changes
        assertRectEqual(result, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    }

    /// Pan right 50px shifts normalized rect left by 50/scaledW.
    /// imgOriginX = 100+50-100 = 50, relX = (0-50)/200 = -0.25
    func testViewToNormalized_panRight() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let result = ImageCropper.viewRectToNormalized(
            frame, imageDisplayFrame: frame,
<<<<<<< Updated upstream
            imageOffset: CGSize(width: 50, height: 0), imageScale: 1
        )
=======
            imageOffset: CGSize(width: 50, height: 0), imageScale: 1)
>>>>>>> Stashed changes
        XCTAssertEqual(result.origin.x, -0.25, accuracy: eps)
        XCTAssertEqual(result.width, 1, accuracy: eps)
    }

    /// Zoom + offset. 2x zoom, pan right 40px.
    /// scaledW = 400, imgOriginX = 100+40-200 = -60
    /// relX = (0 - -60)/400 = 0.15
    func testViewToNormalized_zoomAndPan() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let result = ImageCropper.viewRectToNormalized(
            frame, imageDisplayFrame: frame,
<<<<<<< Updated upstream
            imageOffset: CGSize(width: 40, height: 0), imageScale: 2
        )
=======
            imageOffset: CGSize(width: 40, height: 0), imageScale: 2)
>>>>>>> Stashed changes
        XCTAssertEqual(result.origin.x, 0.15, accuracy: eps)
        XCTAssertEqual(result.origin.y, 0.25, accuracy: eps)
        XCTAssertEqual(result.width, 0.5, accuracy: eps)
    }

    // MARK: - normalizedRectToPixels

    /// Full normalized rect → full pixel rect.
    func testNormalizedToPixels_full() {
        let result = ImageCropper.normalizedRectToPixels(
            CGRect(x: 0, y: 0, width: 1, height: 1),
<<<<<<< Updated upstream
            imageSize: CGSize(width: 3000, height: 4000)
        )
=======
            imageSize: CGSize(width: 3000, height: 4000))
>>>>>>> Stashed changes
        assertRectEqual(result, CGRect(x: 0, y: 0, width: 3000, height: 4000))
    }

    /// Top-left quarter.
    func testNormalizedToPixels_quarter() {
        let result = ImageCropper.normalizedRectToPixels(
            CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
<<<<<<< Updated upstream
            imageSize: CGSize(width: 1000, height: 800)
        )
=======
            imageSize: CGSize(width: 1000, height: 800))
>>>>>>> Stashed changes
        assertRectEqual(result, CGRect(x: 0, y: 0, width: 500, height: 400))
    }

    // MARK: - Round-trip: view → normalized → pixels

    /// Identity crop through the full pipeline equals original pixel dimensions.
    func testRoundTrip_identityCropMatchesImageSize() {
        let frame = CGRect(x: 20, y: 30, width: 350, height: 500)
        let imageSize = CGSize(width: 3500, height: 5000)

        let norm = ImageCropper.viewRectToNormalized(
<<<<<<< Updated upstream
            frame, imageDisplayFrame: frame, imageOffset: .zero, imageScale: 1
        )
=======
            frame, imageDisplayFrame: frame, imageOffset: .zero, imageScale: 1)
>>>>>>> Stashed changes
        let px = ImageCropper.normalizedRectToPixels(norm, imageSize: imageSize)

        XCTAssertEqual(px.origin.x, 0, accuracy: eps)
        XCTAssertEqual(px.origin.y, 0, accuracy: eps)
        XCTAssertEqual(px.width, 3500, accuracy: eps)
        XCTAssertEqual(px.height, 5000, accuracy: eps)
    }

    // MARK: - ImageCropper.rotate (image dimensions)

    /// 90° rotation swaps width and height.
    func testRotateImage_90swapsDimensions() {
        let img = makeImage(width: 100, height: 200)
        let rotated = ImageCropper.rotate(img, degrees: 90)
        XCTAssertEqual(Int(rotated.size.width), 200)
        XCTAssertEqual(Int(rotated.size.height), 100)
    }

    /// 180° preserves dimensions.
    func testRotateImage_180preservesDimensions() {
        let img = makeImage(width: 100, height: 200)
        let rotated = ImageCropper.rotate(img, degrees: 180)
        XCTAssertEqual(Int(rotated.size.width), 100)
        XCTAssertEqual(Int(rotated.size.height), 200)
    }

    /// 0° returns the image unchanged.
    func testRotateImage_0isNoop() {
        let img = makeImage(width: 100, height: 200)
        let rotated = ImageCropper.rotate(img, degrees: 0)
        // Should be the exact same object (guard early-return)
        XCTAssertTrue(img === rotated)
    }

    // MARK: - ImageCropper.applyCrop (end-to-end)

    /// Identity crop (full image, no rotation) → same dimensions.
    func testApplyCrop_identity() {
        let img = makeImage(width: 100, height: 200)
        let result = ImageCropper.applyCrop(
<<<<<<< Updated upstream
            to: img, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1), rotation: 0
        )
=======
            to: img, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1), rotation: 0)
>>>>>>> Stashed changes
        XCTAssertEqual(Int(result.size.width), 100)
        XCTAssertEqual(Int(result.size.height), 200)
    }

    /// Crop to top-left quarter, no rotation → 50×100.
    func testApplyCrop_topLeftQuarter() {
        let img = makeImage(width: 100, height: 200)
        let result = ImageCropper.applyCrop(
<<<<<<< Updated upstream
            to: img, normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), rotation: 0
        )
=======
            to: img, normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), rotation: 0)
>>>>>>> Stashed changes
        XCTAssertEqual(Int(result.size.width), 50)
        XCTAssertEqual(Int(result.size.height), 100)
    }

    /// 90° rotation, full crop → dimensions swap to 200×100.
    func testApplyCrop_rotation90_fullCrop() {
        let img = makeImage(width: 100, height: 200)
        let result = ImageCropper.applyCrop(
<<<<<<< Updated upstream
            to: img, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1), rotation: 90
        )
=======
            to: img, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1), rotation: 90)
>>>>>>> Stashed changes
        XCTAssertEqual(Int(result.size.width), 200)
        XCTAssertEqual(Int(result.size.height), 100)
    }

    /// 90° rotation then half-crop.
    /// After rotation: 200×100. Left half crop → 100×100.
    func testApplyCrop_rotation90_thenHalfCrop() {
        let img = makeImage(width: 100, height: 200)
        let result = ImageCropper.applyCrop(
<<<<<<< Updated upstream
            to: img, normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 1), rotation: 90
        )
=======
            to: img, normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 1), rotation: 90)
>>>>>>> Stashed changes
        XCTAssertEqual(Int(result.size.width), 100)
        XCTAssertEqual(Int(result.size.height), 100)
    }

    /// 270° rotation, full crop → same as 90° (dimensions swap).
    func testApplyCrop_rotation270_fullCrop() {
        let img = makeImage(width: 100, height: 200)
        let result = ImageCropper.applyCrop(
<<<<<<< Updated upstream
            to: img, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1), rotation: 270
        )
=======
            to: img, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1), rotation: 270)
>>>>>>> Stashed changes
        XCTAssertEqual(Int(result.size.width), 200)
        XCTAssertEqual(Int(result.size.height), 100)
    }

    /// 180° rotation, full crop → dimensions unchanged.
    func testApplyCrop_rotation180_fullCrop() {
        let img = makeImage(width: 100, height: 200)
        let result = ImageCropper.applyCrop(
<<<<<<< Updated upstream
            to: img, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1), rotation: 180
        )
=======
            to: img, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1), rotation: 180)
>>>>>>> Stashed changes
        XCTAssertEqual(Int(result.size.width), 100)
        XCTAssertEqual(Int(result.size.height), 200)
    }

    // MARK: - CropState: effectiveLockedRatio

    @MainActor
    func testEffectiveLockedRatio_free() {
        let state = CropState()
        state.selectedPreset = .free
        XCTAssertNil(state.effectiveLockedRatio)
    }

    @MainActor
    func testEffectiveLockedRatio_square() {
        let state = CropState()
        state.selectedPreset = .square
        XCTAssertEqual(state.effectiveLockedRatio, 1.0)
    }

    @MainActor
<<<<<<< Updated upstream
    func testEffectiveLockedRatio_4x3Landscape() throws {
        let state = CropState()
        state.selectedPreset = .ratio4x3
        state.isPortrait = false
        XCTAssertEqual(try XCTUnwrap(state.effectiveLockedRatio), 4.0 / 3.0, accuracy: eps)
    }

    @MainActor
    func testEffectiveLockedRatio_4x3Portrait() throws {
=======
    func testEffectiveLockedRatio_4x3Landscape() {
        let state = CropState()
        state.selectedPreset = .ratio4x3
        state.isPortrait = false
        XCTAssertEqual(state.effectiveLockedRatio!, 4.0 / 3.0, accuracy: eps)
    }

    @MainActor
    func testEffectiveLockedRatio_4x3Portrait() {
>>>>>>> Stashed changes
        let state = CropState()
        state.selectedPreset = .ratio4x3
        state.isPortrait = true
        // Portrait flips: 1 / (4/3) = 3/4
<<<<<<< Updated upstream
        XCTAssertEqual(try XCTUnwrap(state.effectiveLockedRatio), 3.0 / 4.0, accuracy: eps)
    }

    @MainActor
    func testEffectiveLockedRatio_original() throws {
        let state = CropState()
        state.selectedPreset = .original
        state.originalImageRatio = 16.0 / 9.0
        XCTAssertEqual(try XCTUnwrap(state.effectiveLockedRatio), 16.0 / 9.0, accuracy: eps)
=======
        XCTAssertEqual(state.effectiveLockedRatio!, 3.0 / 4.0, accuracy: eps)
    }

    @MainActor
    func testEffectiveLockedRatio_original() {
        let state = CropState()
        state.selectedPreset = .original
        state.originalImageRatio = 16.0 / 9.0
        XCTAssertEqual(state.effectiveLockedRatio!, 16.0 / 9.0, accuracy: eps)
>>>>>>> Stashed changes
    }

    /// Square ignores portrait toggle (1/1 = 1).
    @MainActor
    func testEffectiveLockedRatio_squareIgnoresPortrait() {
        let state = CropState()
        state.selectedPreset = .square
        state.isPortrait = true
        XCTAssertEqual(state.effectiveLockedRatio, 1.0)
    }

    /// Custom locked ratio returned when preset is free + lock is on.
    @MainActor
    func testEffectiveLockedRatio_customLock() {
        let state = CropState()
        state.selectedPreset = .free
        state.isRatioLocked = true
        state.lockedRatio = 2.5
        XCTAssertEqual(state.effectiveLockedRatio, 2.5)
    }

    // MARK: - CropState: rotationDegrees

    @MainActor
    func testRotationDegrees_normalization() {
        let state = CropState()

        state.rotationAngle = 0
        XCTAssertEqual(state.rotationDegrees, 0)

        state.rotationAngle = 90
        XCTAssertEqual(state.rotationDegrees, 90)

        state.rotationAngle = 360
        XCTAssertEqual(state.rotationDegrees, 0)

        state.rotationAngle = -90
        XCTAssertEqual(state.rotationDegrees, 270)

        state.rotationAngle = 450
        XCTAssertEqual(state.rotationDegrees, 90)

        state.rotationAngle = -270
        XCTAssertEqual(state.rotationDegrees, 90)
    }

    // MARK: - CropState: transformedImageBounds

    /// transformedImageBounds returns imageDisplayFrame directly.
    @MainActor
    func testTransformedImageBounds_equalsFrame() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 30, y: 50, width: 300, height: 400)
        assertRectEqual(state.transformedImageBounds(), state.imageDisplayFrame)
    }

    // MARK: - CropState: hitTest

    @MainActor
    func testHitTest_corners() {
        let state = CropState()
        state.cropRect = CGRect(x: 100, y: 100, width: 200, height: 300)

        // Exactly on each corner
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 100, y: 100)), .topLeft)
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 300, y: 100)), .topRight)
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 100, y: 400)), .bottomLeft)
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 300, y: 400)), .bottomRight)
    }

    @MainActor
    func testHitTest_edges() {
        let state = CropState()
        state.cropRect = CGRect(x: 100, y: 100, width: 200, height: 300)

        // Midpoint of each edge, far from corners
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 200, y: 100)), .top)
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 200, y: 400)), .bottom)
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 100, y: 250)), .left)
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 300, y: 250)), .right)
    }

    @MainActor
    func testHitTest_interior() {
        let state = CropState()
        state.cropRect = CGRect(x: 100, y: 100, width: 200, height: 300)
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 200, y: 250)), .moveCrop)
    }

    @MainActor
    func testHitTest_dimZone() {
        let state = CropState()
        state.cropRect = CGRect(x: 100, y: 100, width: 200, height: 300)
        // Far from edges and outside crop → pan image
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 0, y: 0)), .panImage)
        XCTAssertEqual(state.hitTest(point: CGPoint(x: 500, y: 500)), .panImage)
    }

    /// Corner takes priority over edge when within both hit zones.
    @MainActor
    func testHitTest_cornerPriorityOverEdge() {
        let state = CropState()
        state.cropRect = CGRect(x: 100, y: 100, width: 200, height: 300)
        // 15px from topLeft corner — within 30px hit radius of both corner and edge
        let point = CGPoint(x: 110, y: 110)
        XCTAssertEqual(state.hitTest(point: point), .topLeft)
    }

    // MARK: - CropState: nearestValidCrop

    /// Rect already inside bounds → unchanged.
    @MainActor
    func testNearestValidCrop_alreadyValid() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)

        let rect = CGRect(x: 50, y: 50, width: 200, height: 300)
        XCTAssertEqual(state.nearestValidCrop(rect), rect)
    }

    /// Rect hanging off right edge → shifted left, size preserved.
    @MainActor
    func testNearestValidCrop_shiftsRight() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)

        let rect = CGRect(x: 300, y: 50, width: 200, height: 200)
        let result = state.nearestValidCrop(rect)
        // maxX was 500, bounds maxX is 400 → shift to x=200
        XCTAssertEqual(result.origin.x, 200, accuracy: eps)
        XCTAssertEqual(result.width, 200, accuracy: eps)
        XCTAssertEqual(result.height, 200, accuracy: eps)
    }

    /// Too wide for bounds → shrunk.
    @MainActor
    func testNearestValidCrop_shrinksWidth() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)

        let rect = CGRect(x: 0, y: 0, width: 500, height: 200)
        let result = state.nearestValidCrop(rect)
        XCTAssertEqual(result.width, 400, accuracy: eps)
    }

    /// Ratio enforcement — output width/height equals requested ratio.
    @MainActor
    func testNearestValidCrop_enforcesRatio() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)

        let rect = CGRect(x: 50, y: 50, width: 300, height: 200)
        let ratio: CGFloat = 4.0 / 3.0
        let result = state.nearestValidCrop(rect, ratio: ratio)
        XCTAssertEqual(result.width / result.height, ratio, accuracy: 0.01)
    }

    /// Tiny rect → enforces minimum crop size (60pt).
    @MainActor
    func testNearestValidCrop_enforcesMinSize() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)

        let result = state.nearestValidCrop(CGRect(x: 100, y: 100, width: 10, height: 10))
        XCTAssertGreaterThanOrEqual(result.width, 60)
        XCTAssertGreaterThanOrEqual(result.height, 60)
    }

    /// Result is always contained within image bounds (property).
    @MainActor
    func testNearestValidCrop_resultInsideBounds() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)

        let bounds = state.transformedImageBounds()
        // Try several problematic rects
        let cases: [CGRect] = [
            CGRect(x: -50, y: -50, width: 100, height: 100),
            CGRect(x: 350, y: 550, width: 200, height: 200),
            CGRect(x: 0, y: 0, width: 800, height: 800),
            CGRect(x: 200, y: 300, width: 60, height: 60),
        ]
        for rect in cases {
            let result = state.nearestValidCrop(rect)
            XCTAssertGreaterThanOrEqual(result.minX, bounds.minX, "minX for \(rect)")
            XCTAssertGreaterThanOrEqual(result.minY, bounds.minY, "minY for \(rect)")
            XCTAssertLessThanOrEqual(result.maxX, bounds.maxX, "maxX for \(rect)")
            XCTAssertLessThanOrEqual(result.maxY, bounds.maxY, "maxY for \(rect)")
        }
    }

    // MARK: - CropState: resetCrop

    @MainActor
    func testResetCrop_setsCropRectToFrame() {
        let state = CropState()
        let frame = CGRect(x: 10, y: 20, width: 300, height: 400)
        state.imageDisplayFrame = frame
        state.cropRect = CGRect(x: 50, y: 60, width: 100, height: 100)

        state.resetCrop()

        XCTAssertEqual(state.cropRect, frame)
    }

    // MARK: - CropState: resetAll

    @MainActor
    func testResetAll_clearsEverything() {
        let state = CropState()
        let frame = CGRect(x: 0, y: 0, width: 300, height: 400)
        state.imageDisplayFrame = frame

        // Dirty all the state
        state.rotationAngle = 180
        state.selectedPreset = .ratio4x3
        state.isRatioLocked = true
        state.lockedRatio = 1.5
        state.isPortrait = true
        state.cropRect = CGRect(x: 10, y: 10, width: 50, height: 50)

        state.resetAll()

        XCTAssertEqual(state.rotationAngle, 0)
        XCTAssertEqual(state.selectedPreset, .free)
        XCTAssertFalse(state.isRatioLocked)
        XCTAssertNil(state.lockedRatio)
        XCTAssertFalse(state.isPortrait)
        XCTAssertEqual(state.cropRect, frame)
    }

    // MARK: - CropState: selectPreset

    @MainActor
    func testSelectPreset_squareSetsLock() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)
        state.cropRect = CGRect(x: 0, y: 0, width: 400, height: 600)

        state.selectPreset(.square)

        XCTAssertEqual(state.selectedPreset, .square)
        XCTAssertEqual(state.lockedRatio, 1.0)
        // Crop rect should now be square
        XCTAssertEqual(state.cropRect.width, state.cropRect.height, accuracy: eps)
    }

    @MainActor
    func testSelectPreset_freeClearsLock() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)
        state.cropRect = CGRect(x: 0, y: 0, width: 400, height: 600)

        state.selectPreset(.square)
        state.selectPreset(.free)

        XCTAssertEqual(state.selectedPreset, .free)
        XCTAssertNil(state.lockedRatio)
    }

    @MainActor
<<<<<<< Updated upstream
    func testSelectPreset_originalUsesImageRatio() throws {
=======
    func testSelectPreset_originalUsesImageRatio() {
>>>>>>> Stashed changes
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)
        state.cropRect = CGRect(x: 0, y: 0, width: 400, height: 600)
        state.originalImageRatio = 3.0 / 2.0

        state.selectPreset(.original)

<<<<<<< Updated upstream
        XCTAssertEqual(try XCTUnwrap(state.lockedRatio), 3.0 / 2.0, accuracy: eps)
=======
        XCTAssertEqual(state.lockedRatio!, 3.0 / 2.0, accuracy: eps)
>>>>>>> Stashed changes
    }

    // MARK: - CropState: toggleOrientation

    @MainActor
<<<<<<< Updated upstream
    func testToggleOrientation_flipsRatio() throws {
=======
    func testToggleOrientation_flipsRatio() {
>>>>>>> Stashed changes
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)
        state.cropRect = CGRect(x: 0, y: 0, width: 400, height: 600)

        state.selectPreset(.ratio4x3)
<<<<<<< Updated upstream
        let landscapeRatio = try XCTUnwrap(state.lockedRatio)

        state.toggleOrientation()
        let portraitRatio = try XCTUnwrap(state.lockedRatio)
=======
        let landscapeRatio = state.lockedRatio!

        state.toggleOrientation()
        let portraitRatio = state.lockedRatio!
>>>>>>> Stashed changes

        // 4:3 landscape → 3:4 portrait
        XCTAssertEqual(landscapeRatio * portraitRatio, 1.0, accuracy: eps)
    }

    // MARK: - CropState: toggleRatioLock

    @MainActor
<<<<<<< Updated upstream
    func testToggleRatioLock_capturesCurrentRatio() throws {
=======
    func testToggleRatioLock_capturesCurrentRatio() {
>>>>>>> Stashed changes
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)
        state.cropRect = CGRect(x: 0, y: 0, width: 200, height: 100)

        XCTAssertFalse(state.isRatioLocked)

        state.toggleRatioLock()

        XCTAssertTrue(state.isRatioLocked)
        // Locked ratio = width/height of current crop = 200/100 = 2.0
<<<<<<< Updated upstream
        XCTAssertEqual(try XCTUnwrap(state.lockedRatio), 2.0, accuracy: eps)
=======
        XCTAssertEqual(state.lockedRatio!, 2.0, accuracy: eps)
>>>>>>> Stashed changes
    }

    @MainActor
    func testToggleRatioLock_unlockClearsWhenFree() {
        let state = CropState()
        state.selectedPreset = .free
        state.cropRect = CGRect(x: 0, y: 0, width: 200, height: 100)

<<<<<<< Updated upstream
        state.toggleRatioLock() // lock
        state.toggleRatioLock() // unlock
=======
        state.toggleRatioLock()  // lock
        state.toggleRatioLock()  // unlock
>>>>>>> Stashed changes

        XCTAssertFalse(state.isRatioLocked)
        XCTAssertNil(state.lockedRatio)
    }

    // MARK: - CropState: showOrientationToggle

    @MainActor
    func testShowOrientationToggle() {
        let state = CropState()

        state.selectedPreset = .free
        XCTAssertFalse(state.showOrientationToggle)

        state.selectedPreset = .square
        XCTAssertFalse(state.showOrientationToggle)

        state.selectedPreset = .original
        XCTAssertFalse(state.showOrientationToggle)

        state.selectedPreset = .ratio4x3
        XCTAssertTrue(state.showOrientationToggle)

        state.selectedPreset = .ratio4x5
        XCTAssertTrue(state.showOrientationToggle)

        state.selectedPreset = .ratio16x9
        XCTAssertTrue(state.showOrientationToggle)
    }

    // MARK: - CropState: isCropValid

    @MainActor
    func testIsCropValid_insideBounds() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)
        state.cropRect = CGRect(x: 10, y: 10, width: 200, height: 200)
        XCTAssertTrue(state.isCropValid())
    }

    @MainActor
    func testIsCropValid_outsideBounds() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)
        state.cropRect = CGRect(x: 300, y: 500, width: 200, height: 200)
        XCTAssertFalse(state.isCropValid())
    }

    // MARK: - AspectRatioPreset properties

<<<<<<< Updated upstream
    func testAspectRatioPreset_baseRatios() throws {
        XCTAssertNil(AspectRatioPreset.free.baseRatio)
        XCTAssertNil(AspectRatioPreset.original.baseRatio)
        XCTAssertEqual(AspectRatioPreset.square.baseRatio, 1)
        XCTAssertEqual(try XCTUnwrap(AspectRatioPreset.ratio4x3.baseRatio), 4.0 / 3.0, accuracy: eps)
        XCTAssertEqual(try XCTUnwrap(AspectRatioPreset.ratio4x5.baseRatio), 4.0 / 5.0, accuracy: eps)
        XCTAssertEqual(try XCTUnwrap(AspectRatioPreset.ratio16x9.baseRatio), 16.0 / 9.0, accuracy: eps)
=======
    func testAspectRatioPreset_baseRatios() {
        XCTAssertNil(AspectRatioPreset.free.baseRatio)
        XCTAssertNil(AspectRatioPreset.original.baseRatio)
        XCTAssertEqual(AspectRatioPreset.square.baseRatio, 1)
        XCTAssertEqual(AspectRatioPreset.ratio4x3.baseRatio!, 4.0 / 3.0, accuracy: eps)
        XCTAssertEqual(AspectRatioPreset.ratio4x5.baseRatio!, 4.0 / 5.0, accuracy: eps)
        XCTAssertEqual(AspectRatioPreset.ratio16x9.baseRatio!, 16.0 / 9.0, accuracy: eps)
>>>>>>> Stashed changes
    }

    func testAspectRatioPreset_allPresetsCount() {
        XCTAssertEqual(AspectRatioPreset.allPresets.count, 6)
    }

    // MARK: - CropState: clampImageOffset

    /// At scale 1 there's no room to pan — any offset clamps to zero.
    @MainActor
    func testClampImageOffset_scale1_clampsToZero() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 200, height: 200)
        // imageScale defaults to 1.0

        let result = state.clampImageOffset(CGSize(width: 50, height: -30))
        XCTAssertEqual(result.width, 0, accuracy: eps)
        XCTAssertEqual(result.height, 0, accuracy: eps)
    }

    /// At scale 2, offset within ±frame*(scale-1)/2 is preserved.
    /// maxX = 200*(2-1)/2 = 100, so (50,-30) stays.
    @MainActor
    func testClampImageOffset_scale2_withinBounds() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 200, height: 200)
        state.imageScale = 2

        let result = state.clampImageOffset(CGSize(width: 50, height: -30))
        XCTAssertEqual(result.width, 50, accuracy: eps)
        XCTAssertEqual(result.height, -30, accuracy: eps)
    }

    /// Offset exceeding max clamps to boundary.
    /// maxX = 100, so 150 → 100.
    @MainActor
    func testClampImageOffset_scale2_clampsToBounds() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 200, height: 200)
        state.imageScale = 2

        let result = state.clampImageOffset(CGSize(width: 150, height: -200))
        XCTAssertEqual(result.width, 100, accuracy: eps)
        XCTAssertEqual(result.height, -100, accuracy: eps)
    }

    // MARK: - CropState: viewToOverlayPoint

    /// At scale 1, offset zero — identity transform.
    @MainActor
    func testViewToOverlayPoint_identity() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 200, height: 200)

        let result = state.viewToOverlayPoint(CGPoint(x: 150, y: 80))
        XCTAssertEqual(result.x, 150, accuracy: eps)
        XCTAssertEqual(result.y, 80, accuracy: eps)
    }

    /// At 2x zoom, points converge toward center.
    /// cx=100, point 150 → 100 + (150-100)/2 = 125
    @MainActor
    func testViewToOverlayPoint_zoomed() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 200, height: 200)
        state.imageScale = 2

        let result = state.viewToOverlayPoint(CGPoint(x: 150, y: 80))
        XCTAssertEqual(result.x, 125, accuracy: eps)
        XCTAssertEqual(result.y, 90, accuracy: eps)
    }

    /// Center of view maps to center of overlay regardless of zoom.
    @MainActor
    func testViewToOverlayPoint_centerIsFixed() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 200, height: 300)
        state.imageScale = 3

        let result = state.viewToOverlayPoint(CGPoint(x: 100, y: 150))
        XCTAssertEqual(result.x, 100, accuracy: eps)
        XCTAssertEqual(result.y, 150, accuracy: eps)
    }

    // MARK: - CropState: viewToOverlayTranslation

    @MainActor
    func testViewToOverlayTranslation_scale1() {
        let state = CropState()
        state.imageScale = 1
        let result = state.viewToOverlayTranslation(CGSize(width: 40, height: -20))
        XCTAssertEqual(result.width, 40, accuracy: eps)
        XCTAssertEqual(result.height, -20, accuracy: eps)
    }

    @MainActor
    func testViewToOverlayTranslation_scale2() {
        let state = CropState()
        state.imageScale = 2
        let result = state.viewToOverlayTranslation(CGSize(width: 40, height: -20))
        XCTAssertEqual(result.width, 20, accuracy: eps)
        XCTAssertEqual(result.height, -10, accuracy: eps)
    }

    // MARK: - CropState: handleCropMove

    /// Move within bounds — position shifts, size preserved.
    @MainActor
    func testHandleCropMove_withinBounds() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)
        state.dragStartCropRect = CGRect(x: 50, y: 50, width: 200, height: 200)

        state.handleCropMove(translation: CGSize(width: 10, height: 20))

        XCTAssertEqual(state.cropRect.origin.x, 60, accuracy: eps)
        XCTAssertEqual(state.cropRect.origin.y, 70, accuracy: eps)
        XCTAssertEqual(state.cropRect.width, 200, accuracy: eps)
        XCTAssertEqual(state.cropRect.height, 200, accuracy: eps)
    }

    /// Move past right edge — clamps, size preserved.
    @MainActor
    func testHandleCropMove_clampsToEdge() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)
        state.dragStartCropRect = CGRect(x: 50, y: 50, width: 200, height: 200)

        state.handleCropMove(translation: CGSize(width: 300, height: 0))

        // maxX would be 550 > 400, so clamped: x = 400-200 = 200
        XCTAssertEqual(state.cropRect.origin.x, 200, accuracy: eps)
        XCTAssertEqual(state.cropRect.width, 200, accuracy: eps)
    }

    // MARK: - CropState: handleDrag (no-ops)

    /// moveCrop and panImage are no-ops in handleDrag (handled separately).
    @MainActor
    func testHandleDrag_moveCropIsNoop() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)
        let original = CGRect(x: 50, y: 50, width: 200, height: 200)
        state.cropRect = original
        state.dragStartCropRect = original

        state.handleDrag(handle: .moveCrop, translation: CGSize(width: 100, height: 100))
        XCTAssertEqual(state.cropRect, original)

        state.handleDrag(handle: .panImage, translation: CGSize(width: 100, height: 100))
        XCTAssertEqual(state.cropRect, original)
    }

    /// Dragging a handle while a preset is active (but unlocked) switches to free.
    @MainActor
    func testHandleDrag_switchesToFreeWhenUnlocked() {
        let state = CropState()
        state.imageDisplayFrame = CGRect(x: 0, y: 0, width: 400, height: 600)
        state.cropRect = CGRect(x: 0, y: 0, width: 400, height: 400)
        state.dragStartCropRect = state.cropRect
        state.selectPreset(.square)
        state.isRatioLocked = false

        state.handleDrag(handle: .right, translation: CGSize(width: -50, height: 0))

        XCTAssertEqual(state.selectedPreset, .free)
        XCTAssertNil(state.lockedRatio)
    }
}

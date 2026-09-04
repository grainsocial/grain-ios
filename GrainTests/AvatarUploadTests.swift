@testable import Grain
import UIKit
import XCTest

/// Preparing a profile picture for upload: shrinking it to something the PDS
/// will take, and describing the resulting blob in the shape the profile
/// record expects.
@MainActor
final class AvatarUploadTests: XCTestCase {
    /// `scale` defaults to 1 — the picker decodes from data, which gives a
    /// scale-1 image — but it is settable, because an image carrying a scale is
    /// exactly what used to make the resize overshoot.
    private func image(width: CGFloat, height: CGFloat, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            context.cgContext.setFillColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Pixels, which is what the upload limit is actually in.
    private func pixelSize(_ data: Data) throws -> CGSize {
        let decoded = try XCTUnwrap(UIImage(data: data))
        return CGSize(width: decoded.size.width * decoded.scale, height: decoded.size.height * decoded.scale)
    }

    private func editor() -> EditProfileView {
        EditProfileView(client: XRPCClient(
            baseURL: URL(string: "https://test.local")!,
            session: MockURLProtocol.mockSession()
        ))
    }

    // MARK: - Resizing

    /// An avatar straight off a modern camera roll is far too big to upload,
    /// and the PDS rejects an oversized blob only after the transfer is paid
    /// for.
    func testALargeAvatarIsBroughtUnderBothLimits() throws {
        let data = editor().resizeImage(image(width: 3000, height: 2000), maxSize: 1000, maxBytes: 200_000)

        XCTAssertLessThanOrEqual(data.count, 200_000)
        let size = try pixelSize(data)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 1001)
    }

    /// A `UIImage` that carries a scale — anything rendered rather than decoded
    /// — describes itself in points, so measuring `size` alone reports a third
    /// of the real pixels. That gap used to produce a 3000px avatar for a
    /// `maxSize` of 1000, and then spend the entire byte budget compressing the
    /// pixels it shouldn't have had.
    func testAnImageCarryingAScaleIsMeasuredInPixels() throws {
        let data = editor().resizeImage(image(width: 1000, height: 1000, scale: 3), maxSize: 500, maxBytes: 900_000)

        let size = try pixelSize(data)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 501)
    }

    func testResizingKeepsTheAspectRatio() throws {
        let data = editor().resizeImage(image(width: 3000, height: 2000), maxSize: 1000, maxBytes: 500_000)

        let size = try pixelSize(data)
        XCTAssertEqual(size.width / size.height, 1.5, accuracy: 0.02)
    }

    /// An avatar already small enough shouldn't be blown up to the ceiling.
    func testASmallAvatarIsNotEnlarged() throws {
        let data = editor().resizeImage(image(width: 200, height: 200), maxSize: 1000, maxBytes: 200_000)

        XCTAssertEqual(try pixelSize(data).width, 200, accuracy: 1)
    }

    func testAPortraitAvatarIsMeasuredOnItsLongEdge() throws {
        let data = editor().resizeImage(image(width: 800, height: 1600), maxSize: 400, maxBytes: 500_000)

        let size = try pixelSize(data)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 401)
    }

    // MARK: - Blob description

    /// The avatar blob goes into the profile record as a raw dictionary, and
    /// the PDS is strict about its shape.
    func testTheBlobIsWrittenInTheShapeTheRecordExpects() throws {
        let blob = BlobRef(
            type: "blob",
            ref: BlobRef.BlobLink(link: "bafyavatar"),
            mimeType: "image/jpeg",
            size: 4321
        )

        let encoded = try JSONEncoder().encode(editor().blobRefToAnyCodable(blob))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(dict["$type"] as? String, "blob")
        XCTAssertEqual(dict["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(dict["size"] as? Int, 4321)
        XCTAssertEqual((dict["ref"] as? [String: Any])?["$link"] as? String, "bafyavatar")
    }

    /// A blob missing its optional fields still has to produce something the
    /// server will take rather than nulls.
    func testAnIncompleteBlobStillEncodes() throws {
        let bare = BlobRef(type: nil, ref: nil, mimeType: nil, size: nil)

        let encoded = try JSONEncoder().encode(editor().blobRefToAnyCodable(bare))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(dict["$type"] as? String, "blob")
    }
}

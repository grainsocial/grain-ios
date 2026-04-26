@testable import Grain
import XCTest

final class DeepLinkTests: XCTestCase {
    // MARK: - grain:// scheme

    func testGrainSchemeProfile() throws {
        let url = try XCTUnwrap(URL(string: "grain://profile/did:plc:abc123"))
        let link = DeepLink.from(url: url)
        XCTAssertEqual(link, .profile(did: "did:plc:abc123"))
    }

    func testGrainSchemeGallery() throws {
        let url = try XCTUnwrap(URL(string: "grain://profile/did:plc:abc123/gallery/rkey456"))
        let link = DeepLink.from(url: url)
        XCTAssertEqual(link, .gallery(did: "did:plc:abc123", rkey: "rkey456"))
    }

    func testGrainSchemeStory() throws {
        let url = try XCTUnwrap(URL(string: "grain://profile/did:plc:abc123/story/rkey789"))
        let link = DeepLink.from(url: url)
        XCTAssertEqual(link, .story(did: "did:plc:abc123", rkey: "rkey789"))
    }

    // MARK: - https:// scheme

    func testHTTPSProfile() throws {
        let url = try XCTUnwrap(URL(string: "https://grain.social/profile/did:plc:xyz"))
        let link = DeepLink.from(url: url)
        XCTAssertEqual(link, .profile(did: "did:plc:xyz"))
    }

    func testHTTPSGallery() throws {
        let url = try XCTUnwrap(URL(string: "https://grain.social/profile/did:plc:xyz/gallery/abc"))
        let link = DeepLink.from(url: url)
        XCTAssertEqual(link, .gallery(did: "did:plc:xyz", rkey: "abc"))
    }

    func testHTTPSStory() throws {
        let url = try XCTUnwrap(URL(string: "https://grain.social/profile/did:plc:xyz/story/abc"))
        let link = DeepLink.from(url: url)
        XCTAssertEqual(link, .story(did: "did:plc:xyz", rkey: "abc"))
    }

    // MARK: - Invalid URLs

    func testMissingProfileSegment() throws {
        let url = try XCTUnwrap(URL(string: "grain://gallery/rkey456"))
        let link = DeepLink.from(url: url)
        XCTAssertNil(link)
    }

    func testEmptyPath() throws {
        let url = try XCTUnwrap(URL(string: "https://grain.social/"))
        let link = DeepLink.from(url: url)
        XCTAssertNil(link)
    }

    func testUnknownSubpath() throws {
        // profile/did/unknownsegment/rkey — should fall through to just profile
        let url = try XCTUnwrap(URL(string: "grain://profile/did:plc:abc/settings/foo"))
        let link = DeepLink.from(url: url)
        XCTAssertEqual(link, .profile(did: "did:plc:abc"))
    }

    // MARK: - galleryUri computed property

    func testGalleryUriForGalleryLink() {
        let link = DeepLink.gallery(did: "did:plc:test", rkey: "abc123")
        XCTAssertEqual(link.galleryUri, "at://did:plc:test/social.grain.gallery/abc123")
    }

    func testGalleryUriForNonGalleryLink() {
        let profile = DeepLink.profile(did: "did:plc:test")
        XCTAssertNil(profile.galleryUri)

        let story = DeepLink.story(did: "did:plc:test", rkey: "abc")
        XCTAssertNil(story.galleryUri)
    }

    // MARK: - Gallery commentUri (mention notifications)

    func testGalleryUriIgnoresCommentUri() {
        // commentUri is carried alongside gallery for deep-linking to a comment;
        // the at-URI of the gallery itself should not include it.
        let link = DeepLink.gallery(
            did: "did:plc:test",
            rkey: "abc",
            commentUri: "at://did:plc:other/social.grain.comment/c1"
        )
        XCTAssertEqual(link.galleryUri, "at://did:plc:test/social.grain.gallery/abc")
    }

    func testGalleryDeepLinkTargetIdDistinguishesByCommentUri() {
        // Same gallery, different comment targets must produce distinct ids so
        // SwiftUI navigation treats them as separate destinations.
        let a = GalleryDeepLinkTarget(uri: "at://did:plc:x/social.grain.gallery/a", commentUri: nil)
        let b = GalleryDeepLinkTarget(
            uri: "at://did:plc:x/social.grain.gallery/a",
            commentUri: "at://did:plc:x/social.grain.comment/c1"
        )
        XCTAssertNotEqual(a.id, b.id)
    }
}

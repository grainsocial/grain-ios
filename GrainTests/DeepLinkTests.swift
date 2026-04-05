import XCTest
@testable import Grain

final class DeepLinkTests: XCTestCase {

    // MARK: - grain:// scheme

    func testGrainSchemeProfile() {
        let url = URL(string: "grain://profile/did:plc:abc123")!
        let link = DeepLink.from(url: url)
        XCTAssertEqual(link, .profile(did: "did:plc:abc123"))
    }

    func testGrainSchemeGallery() {
        let url = URL(string: "grain://profile/did:plc:abc123/gallery/rkey456")!
        let link = DeepLink.from(url: url)
        XCTAssertEqual(link, .gallery(did: "did:plc:abc123", rkey: "rkey456"))
    }

    func testGrainSchemeStory() {
        let url = URL(string: "grain://profile/did:plc:abc123/story/rkey789")!
        let link = DeepLink.from(url: url)
        XCTAssertEqual(link, .story(did: "did:plc:abc123", rkey: "rkey789"))
    }

    // MARK: - https:// scheme

    func testHTTPSProfile() {
        let url = URL(string: "https://grain.social/profile/did:plc:xyz")!
        let link = DeepLink.from(url: url)
        XCTAssertEqual(link, .profile(did: "did:plc:xyz"))
    }

    func testHTTPSGallery() {
        let url = URL(string: "https://grain.social/profile/did:plc:xyz/gallery/abc")!
        let link = DeepLink.from(url: url)
        XCTAssertEqual(link, .gallery(did: "did:plc:xyz", rkey: "abc"))
    }

    func testHTTPSStory() {
        let url = URL(string: "https://grain.social/profile/did:plc:xyz/story/abc")!
        let link = DeepLink.from(url: url)
        XCTAssertEqual(link, .story(did: "did:plc:xyz", rkey: "abc"))
    }

    // MARK: - Invalid URLs

    func testMissingProfileSegment() {
        let url = URL(string: "grain://gallery/rkey456")!
        let link = DeepLink.from(url: url)
        XCTAssertNil(link)
    }

    func testEmptyPath() {
        let url = URL(string: "https://grain.social/")!
        let link = DeepLink.from(url: url)
        XCTAssertNil(link)
    }

    func testUnknownSubpath() {
        // profile/did/unknownsegment/rkey — should fall through to just profile
        let url = URL(string: "grain://profile/did:plc:abc/settings/foo")!
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
}

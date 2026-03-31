# Grain Native iOS App Design

A full-featured Swift iOS app for Grain, targeting feature parity with the SvelteKit web app.

## Constraints

- **iOS 17+**, SwiftUI + MVVM with `@Observable`
- **SPM** for dependencies
- **Bundle ID:** `social.grain.app`
- **Target directory:** `~/code/grain-native`

## Dependencies

- **Nuke** -- image loading, caching, prefetching
- **JOSESwift** or **Swift-JWT** -- ES256 signing for DPoP proofs
- **KeychainAccess** -- Keychain wrapper for key/token storage

## Project Structure

```
Grain/
  Grain.xcodeproj
  Grain/
    GrainApp.swift
    Info.plist
    Assets.xcassets
    Models/
      Records/          # Codable structs from lexicons
      Views/            # API response view types
      Common/           # AspectRatio, Location, Facet, BlobRef
    API/
      XRPCClient.swift
      DPoP.swift
      AuthManager.swift
      TokenStorage.swift
      Endpoints/
    ViewModels/
    Views/
      Feed/
      Gallery/
      Profile/
      Stories/
      Search/
      Notifications/
      Create/
      Settings/
    Utilities/
  GrainTests/
```

## Authentication

OAuth with DPoP against the hatk server.

**Client registration:** Custom URL scheme (`grain://oauth/callback`). Client metadata served or configured on the hatk server to accept this redirect URI.

**Flow:**

1. Generate ES256 P-256 key pair, store private key in Keychain.
2. `POST /oauth/par` with DPoP proof, PKCE challenge (`S256`), `client_id`, redirect URI `grain://oauth/callback`.
3. Open `ASWebAuthenticationSession` to `/oauth/authorize?request_uri=<uri>&client_id=<id>`.
4. Capture callback code, exchange at `POST /oauth/token` with DPoP proof + code verifier.
5. Store access token, refresh token, expiry in Keychain.
6. All requests include `Authorization: DPoP <token>` header and a `DPoP` proof header.
7. On 401 or token expiry, refresh with rotation. Handle `use_dpop_nonce` retry.

**DPoP proof requirements:**

- `typ: dpop+jwt`, `alg: ES256`
- Public key (`jwk`) in header with minimal `kty`, `crv`, `x`, `y`
- Claims: `jti` (UUID), `htm` (method), `htu` (URL without query), `iat` (timestamp)
- For authenticated requests: `ath` (base64url SHA256 of access token)
- For nonce retries: `nonce` claim from `DPoP-Nonce` response header

## API Layer

Hand-written `XRPCClient` with generated `Codable` model types.

```swift
let gallery = try await client.query(
    "social.grain.unspecced.getGallery",
    params: ["uri": galleryUri],
    as: GetGalleryResponse.self
)
```

**Queries (GET):**

- `social.grain.unspecced.getActorProfile` -- profile with stats
- `social.grain.unspecced.getFollowers` / `getFollowing` / `getKnownFollowers`
- `social.grain.unspecced.getSuggestedFollows`
- `social.grain.unspecced.getGallery` -- single gallery with photos
- `social.grain.unspecced.getGalleryThread` -- paginated comments
- `social.grain.unspecced.getStories` / `getStoryArchive` / `getStory`
- `social.grain.unspecced.getStoryAuthors`
- `social.grain.unspecced.searchGalleries` / `searchProfiles`
- `social.grain.unspecced.getLocations` / `getCameras`
- `social.grain.unspecced.getNotifications`
- `dev.hatk.getFeed` -- feeds with cursor pagination (recent, following, actor, camera, location, hashtag)
- `dev.hatk.getRecord` / `getRecords`
- `dev.hatk.getPreferences`

**Procedures (POST):**

- `dev.hatk.createRecord` / `putRecord` / `deleteRecord`
- `dev.hatk.uploadBlob`
- `dev.hatk.putPreference`
- `social.grain.unspecced.deleteGallery`

## Data Model

Generated `Codable` structs from lexicon JSON files.

**Records:**

- `Gallery` -- title, description, location, EXIF camera data, timestamps
- `Photo` -- blob, aspect ratio, alt text, EXIF metadata
- `PhotoExif` -- ISO, aperture, focal length, camera make/model (integers scaled x1,000,000)
- `GalleryItem` -- links photo to gallery with position
- `Comment` -- text, facets, reply threading
- `Story` -- ephemeral 24-hour media with location and aspect ratio
- `Favorite` -- points to gallery URI
- `Follow` -- follow relationship
- `ActorProfile` -- displayName, description, avatar blob

**View types:**

- `GalleryView` -- gallery with photos, creator, stats, cameras, location, viewer state
- `PhotoView` -- photo with thumbnail/fullsize URLs, alt text, aspect ratio, EXIF
- `ProfileView` / `ProfileViewDetailed` -- profile with optional stats and viewer relationship
- `StoryView` -- story with creator, media URLs, timestamps
- `NotificationItem` -- notification with reason, author, gallery/comment context

**Common types:**

- `AspectRatio` -- width/height
- `Location` -- H3 cell + address (country, region, locality, street)
- `Facet` -- rich text mentions, links, hashtags
- `BlobRef` -- blob reference for uploads

## Navigation

`NavigationStack` with `Router` observable managing path state.

**Tab bar (5 tabs):** Feed | Search | Create | Notifications | Profile

## Screens

| Screen | ViewModel | Notes |
|--------|-----------|-------|
| Home feed | `FeedViewModel` | Paginated galleries, pull-to-refresh, cursor pagination |
| Following feed | `FeedViewModel` | Reused with different feed param |
| Gallery detail | `GalleryViewModel` | Photos, comment thread, favorite toggle |
| Profile | `ProfileViewModel` | User info, gallery grid, follow/unfollow, stories |
| Story viewer | `StoryViewModel` | Timed progression, swipe between authors |
| Create gallery | `CreateGalleryViewModel` | Photo picker, EXIF extraction, upload queue, title/description/location |
| Search | `SearchViewModel` | Text search galleries + profiles, camera/location/hashtag discovery |
| Notifications | `NotificationsViewModel` | Paginated list, 6 reason types |
| Edit profile | `SettingsViewModel` | Display name, description, avatar upload |
| Comments | `CommentsViewModel` | Threaded replies, post comment |
| Followers/Following | `FollowListViewModel` | Paginated user lists |
| Camera feed | `FeedViewModel` | Filtered by camera name |
| Location feed | `FeedViewModel` | Filtered by H3 cell |
| Hashtag feed | `FeedViewModel` | Filtered by tag |

## Shared Patterns

- Cursor-based pagination via `loadMore()`
- Pull-to-refresh on all list views
- Nuke `LazyImage` for all photo rendering with prefetching on scroll
- Optimistic UI updates for favorites, follows, comments

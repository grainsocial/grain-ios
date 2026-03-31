# Stories Feature Design

**Goal:** Add Instagram-style ephemeral stories to the native iOS app, matching the web client's functionality for viewing, browsing, and creating stories.

**Scope:** Story strip on feed, story viewer, profile story indicator, story creation. Story archive is out of scope.

---

## 1. Story Strip (Feed)

Horizontal `ScrollView` at the top of `FeedView`, above gallery cards.

- First item: "+" button (opens `StoryCreateView` sheet) for authenticated users
- Remaining items: circular avatars with gradient ring (purple > accent > cyan) for users with active stories (24h window)
- Display name label below each avatar
- Tapping an avatar opens `StoryViewer` as a fullscreen cover, starting at that author
- Data: `getStoryAuthors()` endpoint, fetched on load and pull-to-refresh

**New files:**
- `Grain/Views/Stories/StoryStripView.swift` — horizontal avatar strip component
- `Grain/ViewModels/StoryStripViewModel.swift` — fetches story authors

**Shared component:**
- `Grain/Views/Stories/StoryRingView.swift` — gradient ring wrapper, reused on profile avatar

## 2. Story Viewer

Wire up the existing `StoryViewer.swift` and present it from feed and profile.

- Presented as `.fullScreenCover`
- Receives full authors list + starting index to enable swiping between authors
- Each author's stories fetched on demand via `getStories(actor:)`
- Auto-advance: 5-second timer per story, animated progress bars at top
- Navigation: tap left 1/3 = previous, tap right 2/3 = next
- Swipe left/right to jump between authors
- Dismisses after last story of last author
- Delete button on own stories via `deleteRecord`
- Status bar hidden for immersive experience

**Modified files:**
- `Grain/Views/Stories/StoryViewer.swift` — enhance with auto-advance timer, author list navigation
- `Grain/Views/Feed/FeedView.swift` — add fullscreen cover presentation
- `Grain/Views/Profile/ProfileView.swift` — add fullscreen cover on avatar tap

## 3. Profile Story Indicator

When a user has active stories, their profile avatar shows a gradient ring and becomes tappable to open the viewer.

- `ProfileDetailViewModel` already fetches stories — use `viewModel.stories.isEmpty` to determine ring visibility
- Wrap `AvatarView` with `StoryRingView` when stories exist
- Tap avatar to open `StoryViewer` as fullscreen cover
- No ring and no tap action when no stories

**Modified files:**
- `Grain/Views/Profile/ProfileView.swift` — conditional ring + tap gesture on avatar

## 4. Story Creation

Sheet presented from the "+" button in the story strip. Reuses photo processing from `CreateGalleryView`.

- Single photo selection via `PhotosPicker`
- Photo preview after selection
- Image resize: max 2000px, max 5MB with JPEG quality binary search
- Location auto-populated from EXIF GPS via reverse geocode (Nominatim), converted to H3 index
- Editable location text field
- Optional "Post to Bluesky" toggle
- Post: `uploadBlob` then `createRecord` with collection `social.grain.story`
- Record fields: media (blob ref), aspectRatio, location (H3 value + name), address, createdAt
- On success: refresh story strip, dismiss sheet

**New files:**
- `Grain/Views/Stories/StoryCreateView.swift`

**Reused from gallery creation:**
- Photo processing / resize utilities
- EXIF GPS extraction
- Reverse geocoding
- H3 conversion (SwiftyH3)

---

## Existing Infrastructure

Already built and ready to use:

- **Models:** `GrainStory`, `GrainStoryAuthor`, `StoryRecord` (in `Grain/Models/`)
- **API endpoints:** `getStories`, `getStory`, `getStoryArchive`, `getStoryAuthors` (in `Grain/API/Endpoints/StoryEndpoints.swift`)
- **Viewer component:** `StoryViewer.swift` (needs enhancement but base exists)
- **OAuth scope:** `repo:social.grain.story` already included
- **Photo processing:** resize, EXIF extraction, blob upload all exist in `CreateGalleryView`

# Development

## Requirements

- Xcode 26+
- [Git LFS](https://git-lfs.com) — icons, fonts, and other binary assets are stored in LFS; without it the build fails on an empty asset catalog
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [just](https://github.com/casey/just)
- [xcbeautify](https://github.com/cpisciotta/xcbeautify)
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)
- [SwiftLint](https://github.com/realm/SwiftLint)

```bash
brew install git-lfs xcodegen just xcbeautify swiftformat swiftlint
git lfs install
```

## Setup

Pull the LFS-backed assets, create your `.env`, then generate the Xcode project and open it:

```bash
git lfs pull                 # fetch icons, fonts, and other binary assets
cp .env.example .env         # BUNDLE_NAME must be set or the build produces an empty ".app"
just generate
open Grain.xcodeproj
```

> `just generate` reads `.env` (via `set dotenv-load`). `BUNDLE_NAME` is required even for
> simulator builds — with it unset, generation fails with "Multiple commands produce '.app'".

If using a non-Xcode editor with SourceKit-LSP (e.g. Zed), run once after generating:

```bash
xcode-build-server config -scheme Grain -project Grain.xcodeproj
```

No local backend needed — `just sim` and `just device` both hit the production API at grain.social.

### Device builds

Device builds require an Apple Developer account. Create a `.env` in the repo root:

```
APPLE_TEAM_ID=YOUR_TEAM_ID
BUNDLE_ID=com.yourorg.grain
BUNDLE_NAME=Grain
```

Then re-run `just generate` before building.

Pass your device UDID directly or via an env var:

```bash
just device 00000000-0000000000000000   # explicit UDID
just device $iphonemax                  # via shell env var
```

Find your device UDID with `xcrun devicectl list devices`.

## Commands

```bash
just sim               # Build + install + launch on simulator (production API)
just sim-local         # Build + install + launch on simulator (local/dev API)
just sim-fresh         # Same as `just sim`, but uninstalls first (wipes app sandbox)
just sim-local-fresh   # Same as `just sim-local`, but uninstalls first
just device DEVICE_ID  # Build + install to a plugged-in iOS device
just test              # Run tests (iPhone 17 Pro Max simulator)
just generate          # Regenerate Xcode project from project.yml
just format-fix        # Fix formatting in-place
just lint-fix          # Fix lint violations
just release           # Bump build, archive, upload to App Store Connect
```

The `*-fresh` variants `xcrun simctl uninstall` your app's bundle id before installing, which clears URLCache, UserDefaults, on-disk caches (FeedCache, LabelDefinitionsCache), and Documents/Caches. Pass `SIM_UDID=<udid>` to target a specific simulator (otherwise uses the booted one).

> **Note:** The Xcode project is generated from `project.yml` — run `just generate` after adding or removing Swift files, or after pulling changes that touch `project.yml`.

## Releasing

Builds ship to TestFlight from Xcode Cloud. Because `Grain.xcodeproj` is XcodeGen
output and isn't committed, `ci_scripts/ci_post_clone.sh` runs on every Xcode
Cloud build to pull git-lfs assets, generate the project, and copy the committed
package pins into place.

Build numbers are assigned by Xcode Cloud, which overwrites `CFBundleVersion`
with its own run counter at archive time — `CURRENT_PROJECT_VERSION` in
`project.yml` is ignored on CI. They only need to be unique and increasing
within a marketing version, so a new train starting at a low number is fine.

`MARKETING_VERSION` is still bumped by hand. Once a marketing version is
approved on the App Store that train closes, and further uploads against it fail
with `90186`/`90062` — so raise it in `project.yml` before releasing against an
already-approved version.

`just release` still archives and uploads from your Mac if you need it, but
don't mix the two: it uploads `project.yml`'s `CURRENT_PROJECT_VERSION`, which
is far ahead of Xcode Cloud's run counter, and once a higher build number exists
on the current train Xcode Cloud's next run would be rejected as not increasing.

When SPM dependencies change, refresh the committed pins — Xcode Cloud disables
automatic package resolution, and the live file lives inside the gitignored
`.xcodeproj`:

```bash
just generate
xcodebuild -resolvePackageDependencies -project Grain.xcodeproj -scheme Grain
cp Grain.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved .
```

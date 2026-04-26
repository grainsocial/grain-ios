# Development

## Requirements

- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [just](https://github.com/casey/just)
- [xcbeautify](https://github.com/cpisciotta/xcbeautify)
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)
- [SwiftLint](https://github.com/realm/SwiftLint)

```bash
brew install xcodegen just xcbeautify swiftformat swiftlint
```

## Setup

Generate the Xcode project and open it:

```bash
just generate
open Grain.xcodeproj
```

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

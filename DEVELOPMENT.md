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

No local backend needed — `just sim` and `just device` both hit the production API at grain.social.

### Device builds

Device builds require an Apple Developer account. Create a `.env` in the repo root:

```
APPLE_TEAM_ID=YOUR_TEAM_ID
BUNDLE_ID=com.yourorg.grain
BUNDLE_NAME=Grain
```

Then re-run `just generate` before building.

## Commands

```bash
just sim               # Build + install + launch on simulator (production API)
just sim-local         # Build + install + launch on simulator (local/dev API)
just device DEVICE_ID  # Build + install to a plugged-in iOS device
just test              # Run tests (iPhone 17 Pro Max simulator)
just generate          # Regenerate Xcode project from project.yml
just format-fix        # Fix formatting in-place
just lint-fix          # Fix lint violations
just release           # Bump build, archive, upload to App Store Connect
```

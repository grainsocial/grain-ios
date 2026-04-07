# Development

## Requirements

- Xcode 26+
- iOS 26.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [just](https://github.com/casey/just)
- [xcbeautify](https://github.com/cpisciotta/xcbeautify)
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)
- [SwiftLint](https://github.com/realm/SwiftLint)

## Setup

```bash
brew install xcodegen just xcbeautify swiftformat swiftlint
```

Create a `.env` file in the repo root:

```
APPLE_TEAM_ID=YOUR_TEAM_ID
BUNDLE_ID=com.yourorg.grain
BUNDLE_NAME=Grain
```

Then generate the Xcode project and open it:

```bash
just generate
open Grain.xcodeproj
```

The app connects to the [Grain backend](https://tangled.org/grain.social/grain), which must be running for full functionality.

## Commands

```bash
just generate   # Regenerate Xcode project from project.yml
just build      # Build for simulator
just sim-local  # Build + install + launch on simulator (local/dev API)
just sim        # Build + install + launch on simulator (production API)
just test       # Run tests
just format     # Check formatting (list unformatted files)
just format-fix # Fix formatting in-place
just lint       # Lint Swift code
just lint-fix   # Fix lint violations
just device ID  # Build + install to a plugged-in iOS device
just release    # Bump build, archive, upload to App Store Connect
```

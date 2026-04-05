# Grain for iOS

Native iOS client for [Grain](https://grain.social), a photography community built on the [AT Protocol](https://atproto.com).

## Requirements

- Xcode 26+
- iOS 26.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [just](https://github.com/casey/just) (optional, for task running)
- [xcbeautify](https://github.com/cpisciotta/xcbeautify) (for formatted build/test output)
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) (code formatter)
- [SwiftLint](https://github.com/realm/SwiftLint) (linter)

## Setup

```bash
brew install xcodegen just xcbeautify swiftformat swiftlint
xcodegen generate
open Grain.xcodeproj
```

The app connects to the [Grain backend](https://tangled.org/grain.social/grain), which must be running for full functionality.

## Commands

```bash
just generate  # Regenerate Xcode project from project.yml
just build     # Build for simulator
just sim-local # Build + install + launch on simulator (local/dev API)
just sim       # Build + install + launch on simulator (production API)
just test       # Run tests
just format     # Check formatting (list unformatted files)
just format-fix # Fix formatting in-place
just lint       # Lint Swift code
just lint-fix   # Fix lint violations
just device ID # Build + install to a plugged-in iOS device
just release   # Bump build, archive, upload to App Store Connect
```

## License

[MIT](LICENSE) — Copyright (c) 2026 Grain Social

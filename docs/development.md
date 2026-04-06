# Development Setup

## Prerequisites

```bash
brew install xcodegen just xcbeautify swiftformat swiftlint
```

## First-time setup

1. **Copy the env file**
   ```bash
   cp .env.example .env
   ```
   Fill in your `APPLE_TEAM_ID` (find it at developer.apple.com → Account → Membership).

2. **Generate the Xcode project**
   ```bash
   just generate
   ```

3. **Run on simulator**
   ```bash
   just sim
   ```

## Building on a real device

Plug in your iPhone, then:
```bash
just device <your-device-udid>
```

Find your UDID:
```bash
xcrun xctrace list devices
```

> **Note:** Device builds require your Apple ID to have certificate access on the team. If you're on an individual developer account, team members need to use TestFlight or Xcode directly with automatic signing.

## Deploying a build

```bash
just release
```

This bumps the build number, archives, and uploads to App Store Connect. Builds are automatically distributed to the **Devs** internal TestFlight group after processing.

## Environment variables

| Variable | Description |
|---|---|
| `APPLE_TEAM_ID` | Apple Developer Team ID used for signing device builds and releases |

`just` loads `.env` automatically. No shell changes needed.

## Common commands

| Command | Description |
|---|---|
| `just generate` | Regenerate Xcode project from `project.yml` |
| `just sim` | Build + run on booted simulator (production API) |
| `just sim-local` | Build + run on booted simulator (local API) |
| `just device <udid>` | Build + install to plugged-in iPhone |
| `just test` | Run tests |
| `just format-fix` | Auto-fix formatting |
| `just lint-fix` | Auto-fix lint violations |
| `just release` | Bump build, archive, upload to App Store Connect |

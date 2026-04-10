set quiet
set dotenv-load

# Simulator build settings — skip code signing (no team account needed)
sim_sign := 'CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""'

# Apple Developer Team ID (override with APPLE_TEAM_ID env var)
team_id := env_var_or_default("APPLE_TEAM_ID", "54P9BCDR92")

# Bundle identifier (override with BUNDLE_ID env var)
bundle_id := env_var_or_default("BUNDLE_ID", "social.grain.grain")

# Default: list available recipes
default:
    just --list

# Regenerate Xcode project from project.yml
generate:
    BUNDLE_ID={{bundle_id}} xcodegen generate
    git config core.hooksPath .githooks

# Worktree-local DerivedData path (avoids collisions with other worktrees)
derived_data := justfile_directory() + "/.derivedData"

# Build for simulator (production API — matches Xcode Run)
build:
    set -o pipefail && xcodebuild build -scheme Grain -destination 'generic/platform=iOS Simulator' -derivedDataPath {{derived_data}} PRODUCT_BUNDLE_IDENTIFIER={{bundle_id}} {{sim_sign}} 2>&1 | xcbeautify

# Build for simulator (local/dev API — overrides default PRODUCTION_API flag)
build-local:
    set -o pipefail && xcodebuild build -scheme Grain -destination 'generic/platform=iOS Simulator' -derivedDataPath {{derived_data}} PRODUCT_BUNDLE_IDENTIFIER={{bundle_id}} SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG' {{sim_sign}} 2>&1 | xcbeautify

# Build + install + launch on simulator (local/dev API)
sim-local: build-local
    #!/usr/bin/env bash
    set -euo pipefail
    SIM=${SIM_UDID:-booted}
    xcrun simctl boot "$SIM" 2>/dev/null || true
    xcrun simctl bootstatus "$SIM" -b >/dev/null
    APP_PATH=$(find "{{derived_data}}/Build/Products/Debug-iphonesimulator" -name "${BUNDLE_NAME:-Grain}.app" -type d | head -1)
    xcrun simctl install "$SIM" "$APP_PATH"
    xcrun simctl launch "$SIM" {{bundle_id}}
    echo "Installed and launched on simulator (local/dev API)"

# Build + install + launch on simulator (production API — grain.social; same as Xcode Run)
sim:
    #!/usr/bin/env bash
    set -euo pipefail
    SIM=${SIM_UDID:-booted}
    xcrun simctl boot "$SIM" 2>/dev/null || true
    xcrun simctl bootstatus "$SIM" -b >/dev/null
    set -o pipefail && xcodebuild build -scheme Grain -destination 'generic/platform=iOS Simulator' -derivedDataPath "{{derived_data}}" PRODUCT_BUNDLE_IDENTIFIER={{bundle_id}} {{sim_sign}} 2>&1 | xcbeautify
    APP_PATH=$(find "{{derived_data}}/Build/Products/Debug-iphonesimulator" -name "${BUNDLE_NAME:-Grain}.app" -type d | head -1)
    xcrun simctl install "$SIM" "$APP_PATH"
    xcrun simctl launch "$SIM" {{bundle_id}}
    echo "Installed and launched on simulator (grain.social)"

# Run tests
test:
    set -o pipefail && xcodebuild test -scheme Grain -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' PRODUCT_BUNDLE_IDENTIFIER={{bundle_id}} 2>&1 | xcbeautify

# Check formatting (list unformatted files)
format:
    swiftformat Grain GrainTests --lint

# Fix formatting in-place
format-fix:
    swiftformat Grain GrainTests

# Lint Swift code
lint:
    swiftlint lint Grain GrainTests

# Fix lint violations
lint-fix:
    swiftlint lint --fix Grain GrainTests

# Legacy alias for sim-local
install: sim-local

# Build and install to a plugged-in iOS device (same settings as Xcode Run)
device device_id:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building for device {{device_id}}..."
    set -o pipefail && xcodebuild build -scheme Grain -destination 'platform=iOS,id={{device_id}}' PRODUCT_BUNDLE_IDENTIFIER={{bundle_id}} -allowProvisioningUpdates 2>&1 | xcbeautify
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Grain-*/Build/Products/Debug-iphoneos -name "${BUNDLE_NAME:-Grain}.app" -type d | head -1)
    echo "Installing $APP_PATH..."
    xcrun devicectl device install app --device {{device_id}} "$APP_PATH"
    echo "Installed to device {{device_id}}!"

# Bump build number, regenerate project, archive, and upload to App Store Connect
release:
    #!/usr/bin/env bash
    set -euo pipefail
    # Compute next build number (don't write yet — only bump on successful upload)
    current=$(grep 'CURRENT_PROJECT_VERSION' project.yml | head -1 | sed 's/.*"\([0-9]*\)"/\1/')
    next=$((current + 1))
    echo "Preparing build $next (current: $current)"
    sed -i '' "s/CURRENT_PROJECT_VERSION: \"$current\"/CURRENT_PROJECT_VERSION: \"$next\"/" project.yml
    # Restore on any failure so the next attempt reuses the same number
    trap 'sed -i "" "s/CURRENT_PROJECT_VERSION: \"$next\"/CURRENT_PROJECT_VERSION: \"$current\"/" project.yml; BUNDLE_ID={{bundle_id}} xcodegen generate >/dev/null 2>&1 || true' ERR
    BUNDLE_ID={{bundle_id}} xcodegen generate
    echo "Archiving..."
    set -o pipefail && xcodebuild archive -scheme Grain -destination 'generic/platform=iOS' -archivePath /tmp/Grain.xcarchive CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM={{team_id}} PRODUCT_BUNDLE_IDENTIFIER={{bundle_id}} -allowProvisioningUpdates 2>&1 | xcbeautify
    echo "Uploading to App Store Connect..."
    cat > /tmp/ExportOptions.plist << 'PLIST'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>method</key>
        <string>app-store-connect</string>
        <key>destination</key>
        <string>upload</string>
        <key>teamID</key>
        <string>{{team_id}}</string>
    </dict>
    </plist>
    PLIST
    xcodebuild -exportArchive -archivePath /tmp/Grain.xcarchive -exportOptionsPlist /tmp/ExportOptions.plist -exportPath /tmp/GrainExport -allowProvisioningUpdates
    trap - ERR
    echo "Build $next uploaded successfully!"

set quiet

# Default: list available recipes
default:
    just --list

# Regenerate Xcode project from project.yml
generate:
    xcodegen generate

# Build for simulator
build:
    xcodebuild build -scheme Grain -destination 'generic/platform=iOS Simulator' -quiet

# Install to booted simulator
install: build
    xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/Grain-gnyldzofconssnfxpuxpctdsmehu/Build/Products/Debug-iphonesimulator/Grain.app

# Build and install to simulator using production API (grain.social)
sim:
    #!/usr/bin/env bash
    set -euo pipefail
    xcodebuild build -scheme Grain -destination 'generic/platform=iOS Simulator' SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) PRODUCTION_API' -quiet
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Grain-*/Build/Products/Debug-iphonesimulator -name "Grain.app" -type d | head -1)
    xcrun simctl install booted "$APP_PATH"
    xcrun simctl launch booted social.grain.grain
    echo "Installed and launched on simulator (grain.social)"

# Build and install to a plugged-in iOS device
device device_id:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building for device {{device_id}}..."
    xcodebuild build -scheme Grain -destination 'platform=iOS,id={{device_id}}' CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates -quiet
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Grain-*/Build/Products/Debug-iphoneos -name "Grain.app" -type d | head -1)
    echo "Installing $APP_PATH..."
    xcrun devicectl device install app --device {{device_id}} "$APP_PATH"
    echo "Installed to device {{device_id}}!"

# Bump build number, regenerate project, archive, and upload to App Store Connect
release:
    #!/usr/bin/env bash
    set -euo pipefail
    # Read current build number and bump
    current=$(grep 'CURRENT_PROJECT_VERSION' project.yml | head -1 | sed 's/.*"\([0-9]*\)"/\1/')
    next=$((current + 1))
    sed -i '' "s/CURRENT_PROJECT_VERSION: \"$current\"/CURRENT_PROJECT_VERSION: \"$next\"/" project.yml
    echo "Bumped build number: $current → $next"
    xcodegen generate
    echo "Archiving..."
    xcodebuild archive -scheme Grain -destination 'generic/platform=iOS' -archivePath /tmp/Grain.xcarchive CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates -quiet
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
        <string>YN68LN9T7Z</string>
    </dict>
    </plist>
    PLIST
    xcodebuild -exportArchive -archivePath /tmp/Grain.xcarchive -exportOptionsPlist /tmp/ExportOptions.plist -exportPath /tmp/GrainExport -allowProvisioningUpdates
    echo "Build $next uploaded successfully!"

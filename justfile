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
    xcodebuild archive -scheme Grain -destination 'generic/platform=iOS' -archivePath /tmp/Grain.xcarchive -quiet
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
    xcodebuild -exportArchive -archivePath /tmp/Grain.xcarchive -exportOptionsPlist /tmp/ExportOptions.plist -exportPath /tmp/GrainExport
    echo "Build $next uploaded successfully!"

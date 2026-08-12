#!/bin/sh
# Xcode Cloud hook: runs after the repository is cloned, before Xcode Cloud
# looks for the project. Grain.xcodeproj is XcodeGen output and isn't committed,
# so it has to be generated here.
#
# Xcode Cloud finds this script because it sits in ci_scripts/ next to
# Grain.xcodeproj (both at the repo root).
set -ex

brew install xcodegen git-lfs

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Icons, fonts, and images are git-lfs backed. Without the real bytes the asset
# catalog compile fails with the unhelpful "AppIcon did not have any applicable
# content", so fetch them and then prove they actually landed.
git lfs install
git lfs pull
# `if` rather than an && chain: under `set -e` a failing grep as the loop body's
# last command would kill the subshell, so a clean checkout would abort here.
pointers=$(git lfs ls-files -n | while read -r f; do
  if [ -f "$f" ] && head -c 64 "$f" 2>/dev/null | grep -q 'git-lfs.github.com'; then
    echo "$f"
  fi
done) || true
if [ -n "$pointers" ]; then
  echo "error: git-lfs objects are still pointers after 'git lfs pull':"
  echo "$pointers"
  exit 1
fi

# project.yml interpolates all three; PRODUCT_NAME is ${BUNDLE_NAME}, and
# leaving it unset generates an empty .app name that fails the build with
# "Multiple commands produce '.app'".
export APPLE_TEAM_ID="${APPLE_TEAM_ID:-YN68LN9T7Z}"
export BUNDLE_ID="${BUNDLE_ID:-social.grain.grain}"
export BUNDLE_NAME="${BUNDLE_NAME:-Grain}"

# Build numbers are Xcode Cloud's to assign — it overwrites CFBundleVersion with
# its own run counter when it archives, so writing one into project.yml here has
# no effect (run 45 set CURRENT_PROJECT_VERSION to 104 and still uploaded as
# build 45). Build numbers only have to be unique and increasing *within* a
# marketing version, so restarting at a low number on a new train is fine.
#
# MARKETING_VERSION is left alone: bumping the train is manual and deliberate,
# and it has to happen before the current version is approved (see DEVELOPMENT.md).

xcodegen generate

# Xcode Cloud disables automatic package resolution, so the generated project
# needs the committed pins. Update the root Package.resolved when packages
# change — the live one is written inside the gitignored .xcodeproj:
#   just generate && xcodebuild -resolvePackageDependencies -project Grain.xcodeproj -scheme Grain
#   cp Grain.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved .
SWIFTPM_DIR="Grain.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$SWIFTPM_DIR"
cp Package.resolved "$SWIFTPM_DIR/Package.resolved"

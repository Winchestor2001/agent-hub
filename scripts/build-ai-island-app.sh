#!/bin/sh
# Build the standalone native AI Island macOS application.
set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
package="$repo/macos/AIIslandApp"
app="$repo/dist/AI Island.app"
mkdir -p "$repo/dist"
stage=$(mktemp -d "$repo/dist/.ai-island-build.XXXXXX")
staged_app="$stage/AI Island.app"
contents="$staged_app/Contents"

swift build --package-path "$package" -c release
bin_dir=$(swift build --package-path "$package" -c release --show-bin-path)
binary="$bin_dir/AIIslandApp"

mkdir -p "$contents/MacOS"
cp "$binary" "$contents/MacOS/AIIsland"
chmod 755 "$contents/MacOS/AIIsland"

/usr/bin/plutil -create xml1 "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDevelopmentRegion string en' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string AI Island' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string AIIsland' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string local.ai-island.app' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleInfoDictionaryVersion string 6.0' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string AI Island' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.1.0' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 1' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 14.0' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$contents/Info.plist"
/usr/bin/plutil -lint "$contents/Info.plist" >/dev/null

# Stage the complete bundle first so Launch Services never sees the app path
# temporarily disappear while an existing AI Island process is running.
previous="$repo/dist/.AI Island.previous.$$"
if [ -e "$app" ]; then mv "$app" "$previous"; fi
if mv "$staged_app" "$app"; then
    if [ -e "$previous" ]; then rm -rf "$previous"; fi
    rmdir "$stage"
else
    if [ -e "$previous" ]; then mv "$previous" "$app"; fi
    exit 1
fi
echo "Built: $app"

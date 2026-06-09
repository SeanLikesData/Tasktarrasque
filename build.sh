#!/bin/bash
# Build Tasktarrasque and assemble a proper .app bundle.
#
# This compiles the Swift sources directly with `swiftc` rather than using
# Swift Package Manager. On a machine with only the Xcode Command Line Tools
# (no full Xcode), SwiftPM's manifest step fails to link, so `swift build`
# does not work. Compiling with swiftc sidesteps that entirely.
#
# A menu bar app also needs an Info.plist with LSUIElement = true so it runs
# as a background accessory (no Dock icon), which this script writes.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Tasktarrasque"
BUNDLE_ID="com.tasktarrasque.app"
VERSION="1.0"
BUILD_VERSION="1"
INSTALL_AND_LAUNCH=false

usage() {
    cat <<USAGE
Usage: ./build.sh [--install]

Build Tasktarrasque into build/Tasktarrasque.app.

Options:
  --install    Copy the app to /Applications and launch that copy.
  -h, --help   Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install|--install-and-launch|--launch)
            INSTALL_AND_LAUNCH=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

SDK_PATH="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
fi
TARGET="$ARCH-apple-macosx14.0"

APP_DIR="build/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"

echo "==> Preparing $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$APP_DIR/Contents/Resources"

SOURCES=()
while IFS= read -r source; do
    SOURCES+=("$source")
done < <(find Sources/Tasktarrasque -name '*.swift' -print | sort)

if [[ "${#SOURCES[@]}" -eq 0 ]]; then
    echo "No Swift sources found." >&2
    exit 1
fi

echo "==> Compiling with swiftc"
swiftc \
    -parse-as-library \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    -framework SwiftUI \
    -framework AppKit \
    "${SOURCES[@]}" \
    -o "$MACOS_DIR/$APP_NAME"

echo "==> Copying resources"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "==> Writing Info.plist"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing"
if ! codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1; then
    echo "warning: ad-hoc signing failed; leaving unsigned local build" >&2
fi

echo "==> Done: $APP_DIR"
if [[ "$INSTALL_AND_LAUNCH" == true ]]; then
    echo "==> Installing to /Applications"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_DIR" /Applications/
    echo "==> Launching /Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app" || {
        sleep 1
        open "/Applications/$APP_NAME.app"
    }
else
    echo "    Run it with: open \"$APP_DIR\""
    echo "    Install and launch it with: ./build.sh --install"
fi

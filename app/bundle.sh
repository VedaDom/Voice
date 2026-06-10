#!/bin/zsh
# Build Voice.app from the SwiftPM executable.
#
# Signing: set CODESIGN_IDENTITY to a "Developer ID Application: …" identity
# (see scripts/notarize.sh for the full distribution flow). If unset, the
# script auto-detects a Developer ID certificate in the keychain and falls
# back to ad-hoc signing for local development.
set -e
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/VoiceApp"
BUNDLE_RES=".build/$CONFIG/VoiceApp_VoiceApp.bundle"
APP="../Voice.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Voice"
[ -d "$BUNDLE_RES" ] && cp -R "$BUNDLE_RES" "$APP/Contents/Resources/"

# app icon
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# embedded engine: worker + streaming engine + relocatable python runtime
mkdir -p "$APP/Contents/Resources/engine"
cp ../engine/worker.py ../engine/online_stream.py "$APP/Contents/Resources/engine/" 2>/dev/null \
    || cp ../engine/worker.py ../online_stream.py "$APP/Contents/Resources/engine/"
if [ -d runtime/python ]; then
    cp -R runtime "$APP/Contents/Resources/runtime"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Voice</string>
    <key>CFBundleIdentifier</key><string>com.wistfare.voice</string>
    <key>CFBundleName</key><string>Voice</string>
    <key>CFBundleDisplayName</key><string>Voice</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Voice listens to your microphone to transcribe your speech — entirely on this Mac.</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# ---------------------------------------------------------------- signing
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
fi

if [ -n "$IDENTITY" ]; then
    echo "signing with: $IDENTITY"
    # sign nested code first (embedded python runtime), then the app with
    # hardened runtime — required for notarization
    find "$APP/Contents/Resources/runtime" -type f \( -name "*.dylib" -o -name "*.so" \) -exec \
        codesign --force --timestamp --options runtime --sign "$IDENTITY" {} + 2>/dev/null || true
    [ -f "$APP/Contents/Resources/runtime/python/bin/python3.12" ] && \
        codesign --force --timestamp --options runtime \
            --entitlements entitlements.plist --sign "$IDENTITY" \
            "$APP/Contents/Resources/runtime/python/bin/python3.12"
    codesign --force --timestamp --options runtime \
        --entitlements entitlements.plist --sign "$IDENTITY" "$APP"
else
    echo "no Developer ID certificate found — ad-hoc signing (local dev only)"
    codesign --force --deep --sign - "$APP"
fi

echo "Built $APP"

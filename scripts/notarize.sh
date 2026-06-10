#!/bin/zsh
# Notarize and staple Voice.dmg so macOS trusts it on any Mac.
#
# ONE-TIME SETUP (with the wistfare.com Apple Developer account):
#   1. Create a "Developer ID Application" certificate:
#      Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application
#      (or developer.apple.com ▸ Certificates). It appears in the keychain.
#   2. Create an app-specific password at appleid.apple.com ▸ Sign-In & Security.
#   3. Store the credentials once:
#        xcrun notarytool store-credentials voice-notary \
#            --apple-id you@wistfare.com \
#            --team-id <TEAMID> \
#            --password <app-specific-password>
#
# THEN, for every release:
#   ./app/bundle.sh release        (auto-signs with the Developer ID cert)
#   ./app/make_dmg.sh
#   ./scripts/notarize.sh
set -e
cd "$(dirname "$0")/.."

DMG="Voice.dmg"
PROFILE="${NOTARY_PROFILE:-voice-notary}"

[ -f "$DMG" ] || { echo "$DMG not found — run app/make_dmg.sh first"; exit 1; }

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "⚠️  No 'Developer ID Application' certificate in the keychain."
    echo "    Follow the ONE-TIME SETUP steps at the top of this script first."
    exit 1
fi

echo "submitting to Apple notary service…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "stapling ticket…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "✅ $DMG is notarized — installs cleanly on any Mac."

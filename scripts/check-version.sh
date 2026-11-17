#!/bin/sh
# Fails if version.txt isn't X.Y.Z or disagrees with .release-please-manifest.json, with the release tag (when
# given), or with what's in dist/ (app Info.plist, zip name, cask) when dist/ has been built.
# Usage: scripts/check-version.sh [vX.Y.Z]   (the dist/ checks run after build-app.sh + package-release.sh)
set -eu
cd "$(dirname "$0")/.."
WANT=$(tr -d '[:space:]' < version.txt)
fail() { echo "::error::$1"; exit 1; }
echo "$WANT" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "version.txt ($WANT) is not X.Y.Z"
MANIFEST=$(sed -n 's/.*"\.": *"\([^"]*\)".*/\1/p' .release-please-manifest.json)
[ "$MANIFEST" = "$WANT" ] || fail ".release-please-manifest.json ($MANIFEST) != version.txt ($WANT)"
if [ "${1:-}" != "" ]; then [ "${1#v}" = "$WANT" ] || fail "tag $1 does not match version.txt $WANT"; fi
PLIST=dist/Zoe.app/Contents/Info.plist
if [ ! -f "$PLIST" ]; then echo "Version check OK: $WANT${1:+, tag $1} (no dist/ build to check)"; exit 0; fi
APPV=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")
[ "$APPV" = "$WANT" ] || fail "app CFBundleShortVersionString $APPV != $WANT"
echo "$BUILD" | grep -Eq '^[1-9][0-9]*$' || fail "CFBundleVersion '$BUILD' is not a positive integer"
/usr/libexec/PlistBuddy -c "Print NSHumanReadableCopyright" "$PLIST" >/dev/null 2>&1 || fail "Info.plist has no NSHumanReadableCopyright (About panel)"
/usr/libexec/PlistBuddy -c "Print NSMicrophoneUsageDescription" "$PLIST" >/dev/null 2>&1 || fail "Info.plist has no NSMicrophoneUsageDescription"
[ -x dist/Zoe.app/Contents/Resources/core/launch.sh ] || fail "the app bundle has no core launcher"
[ -f "dist/Zoe-$WANT.zip" ] || fail "dist/Zoe-$WANT.zip missing"
grep -q "version \"$WANT\"" dist/zoe.rb || fail "cask version != $WANT"
echo "Version check OK: $WANT (build $BUILD)${1:+, tag $1}"

#!/bin/sh
# Fails if version.txt isn't X.Y.Z, if it disagrees with .release-please-manifest.json, or (when a tag is given)
# with the release tag. Usage: scripts/check-version.sh [vX.Y.Z]
# Phase 1 adds the app bundle, zip and cask checks (as in maclens) once there is an app to package.
set -eu
cd "$(dirname "$0")/.."
WANT=$(tr -d '[:space:]' < version.txt)
fail() { echo "::error::$1"; exit 1; }
echo "$WANT" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "version.txt ($WANT) is not X.Y.Z"
MANIFEST=$(sed -n 's/.*"\.": *"\([^"]*\)".*/\1/p' .release-please-manifest.json)
[ "$MANIFEST" = "$WANT" ] || fail ".release-please-manifest.json ($MANIFEST) != version.txt ($WANT)"
if [ "${1:-}" != "" ]; then [ "${1#v}" = "$WANT" ] || fail "tag $1 does not match version.txt $WANT"; fi
echo "Version check OK: $WANT${1:+, tag $1}"

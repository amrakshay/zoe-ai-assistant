#!/bin/sh
# Zips dist/Zoe.app for a release and writes its SHA-256 and a Homebrew cask.
#   Output: dist/Zoe-<version>.zip, dist/Zoe-<version>.zip.sha256, dist/zoe.rb
# Run ./scripts/build-app.sh first. Safe to run locally; it only writes into dist/.
set -eu
cd "$(dirname "$0")/.."
VERSION=$(tr -d '[:space:]' < version.txt)
ZIP="dist/Zoe-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent dist/Zoe.app "$ZIP"   # ditto keeps the code signature intact
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo "$SHA  Zoe-$VERSION.zip" > "$ZIP.sha256"

./scripts/make-cask.sh "$VERSION" "$SHA" > dist/zoe.rb
echo "Packaged $ZIP"
echo "sha256 $SHA"
